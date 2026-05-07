//
//  SessionCSVWriter.swift
//  Chiron
//
//  Per-session CSV capture for the developer-facing telemetry pipeline.
//
//  One instance per session, owned by `TelemetryCoordinator`. The file lands
//  under `Application Support/Telemetry/Pending/{relative_path}.csv`, with
//  the same `{user}/{exercise}/{ts}_{build}_{viewpoint}_{session}` layout
//  used for the matching mp4 — this is the R2 object key, mirrored locally.
//
//  Format (non-negotiable):
//    Line 1: `# {json metadata}` — schema_version + IDs + device. Pandas can
//            skip via `read_csv(comment='#')`. Extending this dict is forward-
//            compatible; readers ignore unknown keys.
//    Line 2: column headers
//    Line 3+: one row per pose-detection frame
//
//  Threading: `recordFrame(timestampMs:formAnalysis:)` is `nonisolated`-safe
//  to call from the MediaPipe worker queue. It builds a snapshot inline and
//  hands it to a serial DispatchQueue that owns the FileHandle. Frame ordering
//  is preserved as long as `recordFrame` itself is called from a single
//  thread (`OnDevicePoseManager.handleMediaPipeResult` already serializes).
//

import Foundation

final class SessionCSVWriter {
    static let schemaVersion = 1

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

    /// Final on-disk URL once `start()` succeeds. Nil before, and nil after
    /// `finalize()` clears the handle on failure.
    private(set) var fileURL: URL?

    private var fileHandle: FileHandle?
    private var frameIndex: Int = 0
    private var lastRepCount: Int = 0
    private var lastFlush: Date = Date()
    private let flushInterval: TimeInterval = 5.0
    private let writeQueue: DispatchQueue
    private var priorDebugLoggerState: Bool = false

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
        self.writeQueue = DispatchQueue(label: "com.chiron.telemetry.csv-writer.\(sessionUUID.uuidString)")
    }

    // MARK: - Lifecycle

    func start() throws {
        let pendingRoot = try TelemetryFilesystem.pendingRoot()
        let relPath = TelemetryFilesystem.relativePath(
            firebaseUserId: firebaseUserId,
            exerciseTypeName: "\(exerciseType)",
            startedAt: startedAt,
            appBuild: appBuild,
            viewpointProfile: viewpointProfile,
            sessionUUID: sessionUUID,
            ext: "csv"
        )
        let url = pendingRoot.appendingPathComponent(relPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
        let handle = try FileHandle(forWritingTo: url)

        try writeHeaderLine(to: handle)
        try writeColumnHeaderLine(to: handle)

        self.fileHandle = handle
        self.fileURL = url

        // Force the SquatRepDebugLogger on so its `latestFrame` carries the
        // rep_phase / primary_angle / reject_reason fields we read per row.
        // We restore the prior state on finalize so the developer's manual
        // debug-overlay toggle is unaffected.
        priorDebugLoggerState = SquatRepDebugLogger.shared.isEnabled
        SquatRepDebugLogger.shared.isEnabled = true
    }

    /// Build the row snapshot inline (this MUST run on the calling thread to
    /// capture this-frame state before the next handleMediaPipeResult callback)
    /// and hand it to the serial write queue.
    func recordFrame(timestampMs: Int, formAnalysis: FormAnalysis?) {
        let manager = OnDevicePoseManager.shared
        let debugFrame = SquatRepDebugLogger.shared.latestFrame

        let repCount = manager.repCount
        let snapshot = FrameSnapshot(
            timestampMs: timestampMs,
            frameIndex: frameIndex,
            poseDetected: manager.poseDetected,
            exerciseType: "\(manager.trackedExerciseType)",
            viewpointBucketSmoothed: manager.currentSquatViewpointBucket.rawValue,
            cameraHeightCategory: manager.currentCameraHeightCategory.rawValue,
            cameraViewCategory: manager.currentCameraViewCategory.rawValue,
            squatExtensionFrameState: manager.currentSquatExtensionFrameState.rawValue,
            hipDepth3D: debugFrame?.hipDepth3D,
            backAngle3D: formAnalysis?.backAngle,
            kneeAlignment3D: formAnalysis?.kneeAlignment,
            formOverallScore: formAnalysis?.overallScore,
            currentFormIssues: (formAnalysis?.issues ?? []).map { $0.rawValue }.joined(separator: ";"),
            repCount: repCount,
            repPhase: debugFrame?.phase ?? "",
            bwPrimaryAngleSmoothed: debugFrame?.primaryAngleSmoothed,
            bwPrimaryAngleRaw: debugFrame?.primaryAngleRaw,
            repValidatedThisFrame: repCount > lastRepCount,
            repRejectedReasonThisFrame: debugFrame?.rejectReason
        )
        lastRepCount = repCount
        frameIndex += 1

        writeQueue.async { [weak self] in
            self?.writeRow(snapshot)
        }
    }

    /// Flushes any buffered writes, closes the handle, and returns the file URL.
    /// Idempotent — calling more than once returns the same URL and is a no-op.
    @discardableResult
    func finalize() -> URL? {
        let url = fileURL
        writeQueue.sync { [weak self] in
            guard let self = self, let handle = self.fileHandle else { return }
            try? handle.synchronize()
            try? handle.close()
            self.fileHandle = nil
        }
        SquatRepDebugLogger.shared.isEnabled = priorDebugLoggerState
        if !priorDebugLoggerState {
            // We turned the logger on solely for telemetry; clear the buffered
            // frames so the next session/debug-overlay starts clean.
            SquatRepDebugLogger.shared.reset()
        }
        return url
    }

    // MARK: - Snapshot type

    private struct FrameSnapshot {
        let timestampMs: Int
        let frameIndex: Int
        let poseDetected: Bool
        let exerciseType: String
        let viewpointBucketSmoothed: String
        let cameraHeightCategory: String
        let cameraViewCategory: String
        let squatExtensionFrameState: String
        let hipDepth3D: Float?
        let backAngle3D: Float?
        let kneeAlignment3D: Float?
        let formOverallScore: Float?
        let currentFormIssues: String
        let repCount: Int
        let repPhase: String
        let bwPrimaryAngleSmoothed: Float?
        let bwPrimaryAngleRaw: Float?
        let repValidatedThisFrame: Bool
        let repRejectedReasonThisFrame: String?
    }

    // MARK: - Format

    private static let columnHeaders = [
        "timestamp_ms",
        "frame_index",
        "pose_detected",
        "exercise_type",
        "viewpoint_bucket_smoothed",
        "camera_height_category",
        "camera_view_category",
        "squat_extension_frame_state",
        "hip_depth_3d",
        "back_angle_3d",
        "knee_alignment_3d",
        "form_overall_score",
        "current_form_issues",
        "rep_count",
        "rep_phase",
        "bw_primary_angle_smoothed",
        "bw_primary_angle_raw",
        "rep_validated_this_frame",
        "rep_rejected_reason_this_frame"
    ]

    private func writeHeaderLine(to handle: FileHandle) throws {
        let metadata: [String: Any] = [
            "schema_version": Self.schemaVersion,
            "app_build": appBuild,
            "app_version": appVersion,
            "exercise_type": "\(exerciseType)",
            "viewpoint_profile": viewpointProfile,
            "firebase_user_id": firebaseUserId,
            "anonymous_uuid": anonymousUUID,
            "session_uuid": sessionUUID.uuidString,
            "device_model": deviceModel,
            "ios_version": iosVersion
        ]
        let json = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        guard let jsonStr = String(data: json, encoding: .utf8) else { return }
        let line = "# \(jsonStr)\n"
        guard let data = line.data(using: .utf8) else { return }
        try handle.write(contentsOf: data)
    }

    private func writeColumnHeaderLine(to handle: FileHandle) throws {
        let line = Self.columnHeaders.joined(separator: ",") + "\n"
        guard let data = line.data(using: .utf8) else { return }
        try handle.write(contentsOf: data)
    }

    private func writeRow(_ snap: FrameSnapshot) {
        guard let handle = fileHandle else { return }
        let row: [String] = [
            "\(snap.timestampMs)",
            "\(snap.frameIndex)",
            snap.poseDetected ? "true" : "false",
            csvEscape(snap.exerciseType),
            csvEscape(snap.viewpointBucketSmoothed),
            csvEscape(snap.cameraHeightCategory),
            csvEscape(snap.cameraViewCategory),
            csvEscape(snap.squatExtensionFrameState),
            fmtFloat(snap.hipDepth3D),
            fmtFloat(snap.backAngle3D),
            fmtFloat(snap.kneeAlignment3D),
            fmtFloat(snap.formOverallScore),
            csvEscape(snap.currentFormIssues),
            "\(snap.repCount)",
            csvEscape(snap.repPhase),
            fmtFloat(snap.bwPrimaryAngleSmoothed),
            fmtFloat(snap.bwPrimaryAngleRaw),
            snap.repValidatedThisFrame ? "true" : "false",
            csvEscape(snap.repRejectedReasonThisFrame ?? "")
        ]
        let line = row.joined(separator: ",") + "\n"
        if let data = line.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }

        if Date().timeIntervalSince(lastFlush) >= flushInterval {
            try? handle.synchronize()
            lastFlush = Date()
        }
    }

    private func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return s
    }

    private func fmtFloat(_ v: Float?) -> String {
        guard let v = v else { return "" }
        return String(format: "%.5f", v)
    }
}
