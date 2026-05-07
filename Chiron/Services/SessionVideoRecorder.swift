//
//  SessionVideoRecorder.swift
//  Chiron
//
//  Telemetry-side companion for `ScreenRecorder.shared` (ReplayKit). Does NOT
//  drive ReplayKit itself — that's owned by the existing TrackView debug-export
//  flow. Instead, this class takes the temp-directory mp4 that ReplayKit
//  produces, transcodes it down for upload economics, and lands it in
//  `Pending/{firebase_user_id}/{exercise}/...` matching the CSV's relative path.
//
//  Why no own ReplayKit driving: only one `RPScreenRecorder` session can be
//  active at a time, and TrackView already wires it up. Adding a second start
//  would conflict; instead, telemetry piggybacks on the file TrackView already
//  produces (and TrackView's manual share-sheet workflow stays untouched).
//
//  Transcode: `AVAssetExportPresetMediumQuality` ≈ 540p H.264 + AAC. Roughly
//  3-5 MB per minute, suitable for the developer's analysis pass. The spec
//  asked for a tighter 480p / 15fps target — that requires a custom
//  `AVAssetReader`/`AVAssetWriter` pipeline (see the TODO at `transcode`).
//

import Foundation
import AVFoundation

final class SessionVideoRecorder {
    let sessionUUID: UUID
    let firebaseUserId: String
    let anonymousUUID: String
    let exerciseType: TrackedExerciseType
    let viewpointProfile: String
    let appBuild: String
    let appVersion: String
    let deviceModel: String
    let iosVersion: String
    let startedAt: Date

    init(
        sessionUUID: UUID,
        firebaseUserId: String,
        anonymousUUID: String,
        exerciseType: TrackedExerciseType,
        viewpointProfile: String,
        appBuild: String,
        appVersion: String,
        deviceModel: String,
        iosVersion: String,
        startedAt: Date = Date()
    ) {
        self.sessionUUID = sessionUUID
        self.firebaseUserId = firebaseUserId
        self.anonymousUUID = anonymousUUID
        self.exerciseType = exerciseType
        self.viewpointProfile = viewpointProfile
        self.appBuild = appBuild
        self.appVersion = appVersion
        self.deviceModel = deviceModel
        self.iosVersion = iosVersion
        self.startedAt = startedAt
    }

    /// Computed final on-disk URL inside Pending/. Same convention as
    /// `SessionCSVWriter` — the mp4 lands next to its sibling CSV.
    func destinationURL() throws -> URL {
        let pending = try TelemetryFilesystem.pendingRoot()
        let rel = TelemetryFilesystem.relativePath(
            firebaseUserId: firebaseUserId,
            exerciseTypeName: "\(exerciseType)",
            startedAt: startedAt,
            appBuild: appBuild,
            viewpointProfile: viewpointProfile,
            sessionUUID: sessionUUID,
            ext: "mp4"
        )
        return pending.appendingPathComponent(rel)
    }

    /// Transcode `sourceURL` (a ReplayKit temp mp4) and land it under Pending/
    /// at the canonical relative path. Calls `completion` on the main queue
    /// with the new URL on success, nil on failure. The source file is not
    /// deleted — TrackView's manual-share-sheet flow may still reference it.
    func processAndStore(sourceURL: URL, completion: @escaping (URL?) -> Void) {
        do {
            let dest = try destinationURL()
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try? FileManager.default.removeItem(at: dest)
            transcode(from: sourceURL, to: dest, completion: completion)
        } catch {
            DispatchQueue.main.async { completion(nil) }
        }
    }

    /// Synchronous fallback: copy the source as-is into Pending/. Used when
    /// the transcode fails (preset not available on a device, etc.) — better
    /// to upload the larger file than to lose the recording entirely.
    func storeWithoutTranscode(sourceURL: URL) -> URL? {
        do {
            let dest = try destinationURL()
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    // MARK: - Private

    /// AVAssetExportSession path. Hits `MediumQuality` (~540p H.264).
    /// TODO(zach): swap for an AVAssetReader/AVAssetWriter pipeline when we
    /// want strict 480p / 15fps control — the export-session preset gives us
    /// resolution but not frame rate. Search "TODO_TELEMETRY_TRANSCODE" to
    /// find this site.
    private func transcode(from sourceURL: URL, to destURL: URL, completion: @escaping (URL?) -> Void) {
        let asset = AVURLAsset(url: sourceURL)
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetMediumQuality
        ) else {
            // Preset unavailable — fall back to a raw copy so we don't lose the recording.
            let fallback = storeWithoutTranscode(sourceURL: sourceURL)
            DispatchQueue.main.async { completion(fallback) }
            return
        }
        session.outputURL = destURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        session.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                switch session.status {
                case .completed:
                    completion(destURL)
                case .failed, .cancelled:
                    // Best-effort fallback — keep the larger source file rather than nothing.
                    let fallback = self?.storeWithoutTranscode(sourceURL: sourceURL)
                    completion(fallback)
                default:
                    completion(nil)
                }
            }
        }
    }
}
