//
//  AccuracyFlagStore.swift
//  Chiron
//
//  Captures tester-reported set-tracking inaccuracies and lands them in
//  the standard telemetry pipeline (Pending/ → R2 via TelemetryUploader).
//
//  Lifecycle:
//    1. `beginSet(exerciseType:exerciseName:currentWeight:)` — call when
//       the user starts a new set. Mints a fresh `setId`, records start
//       time, clears prior per-set state.
//    2. `recordSetEnd(...)` — call at the moment OpenAICoachingManager
//       returns. Snapshots the inputs the coach saw (FormAnalysis,
//       SetEndAggregatedMetrics) and the line it produced. This is the
//       "ground truth" for an after-set flag.
//    3. `submit(category:phase:)` — called from the AccuracyFlagSheet
//       when the user picks an option. Reads the appropriate snapshot
//       (current state if `.duringSet`, recorded end snapshot if
//       `.afterSet`), serialises the JSON, writes it under
//       `Telemetry/Pending/{user}/accuracy_flags/...`, then hands it to
//       `TelemetryUploader.enqueue(...)` for the existing R2 upload path.
//

import Foundation
import UIKit

@MainActor
final class AccuracyFlagStore: ObservableObject {
    static let shared = AccuracyFlagStore()

    // MARK: - Per-set capture state

    private var currentSetId: UUID?
    private var currentSetStartedAt: Date?
    private var currentExerciseType: TrackedExerciseType?
    private var currentExerciseName: String?
    private var currentWeight: Double?
    private var currentSetIndexInSession: Int?

    /// Snapshot recorded at set-end. Used when the user flags after the set
    /// has already finished — we replay the exact inputs the coach saw.
    private struct EndSnapshot {
        let setId: UUID
        let setStartedAt: Date?
        let setEndedAt: Date
        let exerciseType: TrackedExerciseType
        let exerciseName: String?
        let weight: Double?
        let setIndexInSession: Int?
        let formAnalysis: FormAnalysis?
        let aggregatedMetrics: SetEndAggregatedMetrics
        let coachFeedback: SetEndFeedback?
        let displayedRepCount: Int
        let viewpointBucket: SquatViewpointBucket
        let viewpointProfileName: String
    }

    private var lastEndSnapshot: EndSnapshot?

    private init() {}

    // MARK: - Public lifecycle

    /// Called when a new set begins (pose tracking started). Mints a fresh
    /// `setId` and clears the prior set's snapshot so a flag during the
    /// new set never accidentally reports the old data.
    func beginSet(
        exerciseType: TrackedExerciseType,
        exerciseName: String?,
        currentWeight: Double?,
        setIndexInSession: Int? = nil
    ) {
        self.currentSetId = UUID()
        self.currentSetStartedAt = Date()
        self.currentExerciseType = exerciseType
        self.currentExerciseName = exerciseName
        self.currentWeight = currentWeight
        self.currentSetIndexInSession = setIndexInSession
        // A flag during the new set should never replay the prior set's
        // recorded end snapshot.
        self.lastEndSnapshot = nil
    }

    /// Called at set-end after `OpenAICoachingManager.generateSetEndFeedback`
    /// returns. Captures the inputs the coach saw plus the line it produced.
    /// Pass `feedback = nil` if the set ended with zero reps and feedback
    /// was skipped — the snapshot still records the rep count + metrics.
    func recordSetEnd(
        formAnalysis: FormAnalysis?,
        aggregatedMetrics: SetEndAggregatedMetrics,
        feedback: SetEndFeedback?,
        displayedRepCount: Int
    ) {
        guard let setId = currentSetId,
              let exerciseType = currentExerciseType else {
            return
        }
        let poseManager = OnDevicePoseManager.shared
        lastEndSnapshot = EndSnapshot(
            setId: setId,
            setStartedAt: currentSetStartedAt,
            setEndedAt: Date(),
            exerciseType: exerciseType,
            exerciseName: currentExerciseName,
            weight: currentWeight,
            setIndexInSession: currentSetIndexInSession,
            formAnalysis: formAnalysis,
            aggregatedMetrics: aggregatedMetrics,
            coachFeedback: feedback,
            displayedRepCount: displayedRepCount,
            viewpointBucket: poseManager.currentSquatViewpointBucket,
            viewpointProfileName: poseManager.currentSquatProfileName
        )
    }

    /// True when there's a flagged-able set available — either a set in
    /// progress (`beginSet` was called) or a completed set with a recorded
    /// end snapshot. The UI uses this to decide whether to render the
    /// flag button.
    var hasFlaggableSet: Bool {
        currentSetId != nil || lastEndSnapshot != nil
    }

    // MARK: - Submit

    /// Build the payload from the appropriate snapshot, write the JSON
    /// under `Telemetry/Pending/`, and queue it for R2 upload. Returns
    /// `true` on successful write; the upload itself is async + retried
    /// by `TelemetryUploader`.
    @discardableResult
    func submit(category: AccuracyFlagCategory, phase: AccuracyFlagPhase) -> Bool {
        let payload: AccuracyFlagPayload
        switch phase {
        case .afterSet:
            guard let snap = lastEndSnapshot else { return false }
            payload = buildPayload(category: category, phase: .afterSet, from: snap)
        case .duringSet:
            guard let live = buildLivePayload(category: category) else { return false }
            payload = live
        }

        return writeAndEnqueue(payload: payload)
    }

    // MARK: - Payload builders

    private func buildPayload(
        category: AccuracyFlagCategory,
        phase: AccuracyFlagPhase,
        from snap: EndSnapshot
    ) -> AccuracyFlagPayload {
        let (firebaseUserId, anonymousUUID) = Self.currentIdentities()
        return AccuracyFlagPayload(
            schemaVersion: AccuracyFlagPayload.schemaVersion,
            flagId: UUID().uuidString,
            firebaseUserId: firebaseUserId,
            anonymousUUID: anonymousUUID,
            category: category,
            capturedDuring: phase,
            flaggedAtIso: Self.iso(Date()),
            setStartIso: snap.setStartedAt.map(Self.iso),
            setEndIso: Self.iso(snap.setEndedAt),
            setId: snap.setId.uuidString,
            setIndexInSession: snap.setIndexInSession,
            exerciseType: "\(snap.exerciseType)",
            exerciseName: snap.exerciseName,
            viewpointBucket: snap.viewpointBucket.rawValue,
            viewpointProfileName: snap.viewpointProfileName,
            displayedRepCount: snap.displayedRepCount,
            coachAggregatedMetrics: AccuracyFlagAggregatedMetricsJSON(snap.aggregatedMetrics),
            coachFormAnalysis: snap.formAnalysis.map(AccuracyFlagFormAnalysisJSON.init),
            coachOutput: snap.coachFeedback.map(AccuracyFlagCoachOutputJSON.init),
            currentWeightLbs: snap.weight,
            appVersion: Self.appVersion,
            appBuild: Self.appBuild,
            deviceModel: UIDevice.current.model,
            iosVersion: UIDevice.current.systemVersion
        )
    }

    private func buildLivePayload(category: AccuracyFlagCategory) -> AccuracyFlagPayload? {
        guard let setId = currentSetId,
              let exerciseType = currentExerciseType else {
            return nil
        }
        let (firebaseUserId, anonymousUUID) = Self.currentIdentities()
        let poseManager = OnDevicePoseManager.shared
        let liveAnalysis = poseManager.currentFormAnalysis ?? poseManager.lastRepFormAnalysis
        let liveMetrics = poseManager.aggregatedMetricsSnapshot()
        return AccuracyFlagPayload(
            schemaVersion: AccuracyFlagPayload.schemaVersion,
            flagId: UUID().uuidString,
            firebaseUserId: firebaseUserId,
            anonymousUUID: anonymousUUID,
            category: category,
            capturedDuring: .duringSet,
            flaggedAtIso: Self.iso(Date()),
            setStartIso: currentSetStartedAt.map(Self.iso),
            setEndIso: nil,
            setId: setId.uuidString,
            setIndexInSession: currentSetIndexInSession,
            exerciseType: "\(exerciseType)",
            exerciseName: currentExerciseName,
            viewpointBucket: poseManager.currentSquatViewpointBucket.rawValue,
            viewpointProfileName: poseManager.currentSquatProfileName,
            displayedRepCount: poseManager.repCount,
            coachAggregatedMetrics: AccuracyFlagAggregatedMetricsJSON(liveMetrics),
            coachFormAnalysis: liveAnalysis.map(AccuracyFlagFormAnalysisJSON.init),
            // Mid-set, the coach hasn't been called yet — no output to record.
            coachOutput: nil,
            currentWeightLbs: currentWeight,
            appVersion: Self.appVersion,
            appBuild: Self.appBuild,
            deviceModel: UIDevice.current.model,
            iosVersion: UIDevice.current.systemVersion
        )
    }

    // MARK: - Persistence

    private func writeAndEnqueue(payload: AccuracyFlagPayload) -> Bool {
        guard let pendingRoot = try? TelemetryFilesystem.pendingRoot() else {
            return false
        }
        let rel = TelemetryFilesystem.relativePath(
            firebaseUserId: payload.firebaseUserId,
            exerciseTypeName: "accuracy_flags",
            startedAt: Date(),
            appBuild: payload.appBuild,
            viewpointProfile: payload.viewpointBucket,
            sessionUUID: UUID(uuidString: payload.flagId) ?? UUID(),
            ext: "json"
        )
        let absURL = pendingRoot.appendingPathComponent(rel)
        do {
            try FileManager.default.createDirectory(
                at: absURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: absURL, options: .atomic)
        } catch {
            print("[AccuracyFlagStore] write failed: \(error)")
            return false
        }
        TelemetryUploader.shared.enqueue(relativePath: rel)
        print("[AccuracyFlagStore] queued \(rel) (\(payload.category.rawValue), \(payload.capturedDuring.rawValue))")
        return true
    }

    // MARK: - Helpers

    private static func currentIdentities() -> (firebaseUserId: String, anonymousUUID: String) {
        let id = UserManager.shared.getUserId()
        return (id, id)
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private static var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func iso(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }
}
