//
//  TelemetryCoordinator.swift
//  Chiron
//
//  The single entry point that the rest of the app talks to for the
//  developer-facing telemetry pipeline. Holds the active `SessionCSVWriter`
//  and `SessionVideoRecorder`, queues finalized files into the
//  `TelemetryUploader` actor, and reads `TelemetryPreferencesManager` as the
//  one and only consent gate — so consumers (`OnDevicePoseManager`, the
//  TrackView/WorkoutActiveView lifecycle sites) never need to know about the
//  individual writers, the upload mechanics, or the consent flag check.
//
//  Threading model:
//    - The class is `@MainActor`. Lifecycle methods (`startSession`,
//      `endSession`, `attachRecordedVideo`) MUST be called on the main thread.
//    - The per-frame hooks (`recordFrame`, `recordRepEvent`,
//      `recordRepRejection`) are `nonisolated` so the MediaPipe worker queue
//      can call them at frame rate without main-thread hops.
//    - Per-frame access to the writer is via a `nonisolated(unsafe)` shadow
//      pointer that's set on main and read on the analysis thread. The only
//      possible race is a dropped frame at session-end boundaries; acceptable
//      for telemetry.
//

import Foundation
import UIKit

@MainActor
final class TelemetryCoordinator: ObservableObject {
    static let shared = TelemetryCoordinator()

    /// Active CSV writer for the current session. Set on `startSession`,
    /// cleared on `endSession`.
    private var activeCSVWriter: SessionCSVWriter?

    /// Active video recorder shell for the current session. Doesn't drive
    /// ReplayKit itself — it's parked here so `attachRecordedVideo` can hand
    /// it the source URL once TrackView's `ScreenRecorder.shared.stop`
    /// callback returns.
    private var activeVideoRecorder: SessionVideoRecorder?

    /// Most-recently-ended session, kept around until either `attachRecordedVideo`
    /// fires (handing the mp4 over) or the grace window elapses. `Pending/`
    /// already has the CSV — this only governs the video attach handoff.
    private var lastEndedSession: ParkedSession?

    /// Grace window for `attachRecordedVideo` after `endSession`. ReplayKit's
    /// stop callback usually returns within a few seconds; 60 s is a generous cap.
    private let videoAttachGraceSeconds: TimeInterval = 60

    /// Per-frame fast path: a non-isolated mirror of `activeCSVWriter`.
    /// MUST only be assigned on main, in lock-step with `activeCSVWriter`.
    nonisolated(unsafe) private var activeCSVWriterFastPath: SessionCSVWriter?

    private init() {}

    // MARK: - Lifecycle (main thread)

    /// Open a new telemetry session. No-op if telemetry is disabled or a session
    /// is already active. Caller (TrackView's `startSet`, WorkoutActiveView's
    /// equivalent) is responsible for arranging that ReplayKit also starts —
    /// telemetry piggybacks on the same recording for video capture.
    func startSession(exerciseType: TrackedExerciseType, viewpointProfile: String? = nil) {
        guard isEnabled else { return }
        guard activeCSVWriter == nil else { return }

        let sessionUUID = UUID()
        let userId = UserManager.shared.getUserId()
        // Two-ID seam: today both come from UserManager. When real FirebaseAuth
        // lands, swap firebaseUserId here. See TODO_FIREBASE_USER_ID_SWAP in
        // TelemetryUploader.swift for the matching site downstream.
        let firebaseUserId = userId
        let anonymousUUID = userId
        let appBuild = Self.appBuild
        let appVersion = Self.appVersion
        let deviceModel = UIDevice.current.model
        let iosVersion = UIDevice.current.systemVersion
        let resolvedViewpoint = viewpointProfile ?? OnDevicePoseManager.shared.currentSquatProfileName

        let writer = SessionCSVWriter(
            sessionUUID: sessionUUID,
            firebaseUserId: firebaseUserId,
            anonymousUUID: anonymousUUID,
            exerciseType: exerciseType,
            viewpointProfile: resolvedViewpoint,
            appBuild: appBuild,
            appVersion: appVersion,
            deviceModel: deviceModel,
            iosVersion: iosVersion
        )
        do {
            try writer.start()
        } catch {
            print("[TelemetryCoordinator] CSV writer start failed: \(error)")
            return
        }
        activeCSVWriter = writer
        activeCSVWriterFastPath = writer

        activeVideoRecorder = SessionVideoRecorder(
            sessionUUID: sessionUUID,
            firebaseUserId: firebaseUserId,
            anonymousUUID: anonymousUUID,
            exerciseType: exerciseType,
            viewpointProfile: resolvedViewpoint,
            appBuild: appBuild,
            appVersion: appVersion,
            deviceModel: deviceModel,
            iosVersion: iosVersion
        )
    }

    /// Close the active CSV writer and queue it for upload. Parks the video
    /// recorder so `attachRecordedVideo` can hand it the source URL once
    /// TrackView's screen-recorder stop callback returns.
    func endSession() {
        guard let writer = activeCSVWriter else { return }
        let csvURL = writer.finalize()
        activeCSVWriter = nil
        activeCSVWriterFastPath = nil

        if let url = csvURL {
            enqueueForUpload(fileURL: url)
        }

        if let recorder = activeVideoRecorder {
            lastEndedSession = ParkedSession(recorder: recorder, endedAt: Date())
            activeVideoRecorder = nil
        }
    }

    /// Hand off the temp mp4 produced by ReplayKit. TrackView (or any other
    /// set-lifecycle site) calls this from the `ScreenRecorder.shared.stop`
    /// callback. No-op if no parked session, the source URL is nil, or the
    /// grace window has elapsed.
    func attachRecordedVideo(at sourceURL: URL?) {
        guard let parked = lastEndedSession else { return }
        lastEndedSession = nil
        guard Date().timeIntervalSince(parked.endedAt) <= videoAttachGraceSeconds else { return }
        guard let sourceURL = sourceURL else { return }
        parked.recorder.processAndStore(sourceURL: sourceURL) { [weak self] storedURL in
            guard let storedURL = storedURL else { return }
            Task { @MainActor in
                self?.enqueueForUpload(fileURL: storedURL)
            }
        }
    }

    // MARK: - Per-frame hooks (analysis thread, nonisolated)

    /// Per-frame observation. Called from `OnDevicePoseManager.handleMediaPipeResult`
    /// on the MediaPipe worker queue. Forwards to the CSV writer's serial
    /// queue without any main-thread hop; reads `activeCSVWriterFastPath`
    /// without locking (see file header for the race tolerance rationale).
    nonisolated func recordFrame(timestampMs: Int, formAnalysis: FormAnalysis?) {
        activeCSVWriterFastPath?.recordFrame(timestampMs: timestampMs, formAnalysis: formAnalysis)
    }

    /// Rep-detected hook. MVP no-op — the per-frame CSV already encodes
    /// rep_validated_this_frame. Reserved for the future per-rep JSONL stream
    /// (see ARCHITECTURE notes in TELEMETRY_SETUP.md).
    nonisolated func recordRepEvent(repIndex: Int) {
        // Intentional no-op for MVP. Future: write a per-rep JSONL row with
        // form score, ROM peak, eccentric/concentric durations, etc.
    }

    /// Rep-rejected hook. MVP no-op — the per-frame CSV already encodes
    /// rep_rejected_reason_this_frame. Reserved for the same per-rep JSONL.
    nonisolated func recordRepRejection(reason: String) {
        // Intentional no-op for MVP.
    }

    // MARK: - Helpers

    private var isEnabled: Bool {
        TelemetryPreferencesManager.shared.shareDataToImproveChiron
    }

    private func enqueueForUpload(fileURL: URL) {
        guard let pendingRoot = try? TelemetryFilesystem.pendingRoot() else { return }
        let prefix = pendingRoot.path + "/"
        let path = fileURL.path
        guard path.hasPrefix(prefix) else { return }
        let rel = String(path.dropFirst(prefix.count))
        TelemetryUploader.shared.enqueue(relativePath: rel)
    }

    private static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}

// MARK: - Internal types

private struct ParkedSession {
    let recorder: SessionVideoRecorder
    let endedAt: Date
}
