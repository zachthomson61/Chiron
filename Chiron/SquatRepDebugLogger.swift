//
//  SquatRepDebugLogger.swift
//  Chiron
//
//  Per-frame telemetry for bodyweight squat rep detection.
//  Captures knee-angle signals and state machine for diagnosing
//  missed/phantom reps via the debug overlay or CSV export.
//

import Foundation

// MARK: - Per-Frame Debug Snapshot

struct SquatRepDebugFrame {
    let timestamp: CFTimeInterval
    let frameIndex: Int

    // Exercise context
    var exerciseType: String = ""
    var viewBucket: String = ""

    // Primary 3D signal driving the validator (degrees):
    //   bodyweight / barbell squat → knee angle (hip→knee→ankle)
    //   deadlift / RDL             → hip angle  (shoulder→hip→knee)
    //   row                        → elbow angle (shoulder→elbow→wrist)
    //   bench / closeGripBench     → not populated; see `benchDepth`
    var primaryAngleRaw: Float?
    var primaryAngleSmoothed: Float?

    // 2D image-coord fallback (RDL hip angle, row elbow angle). Other exercises leave nil.
    var secondaryAngle2DSmoothed: Float?

    // Bench-press elbow-derived depth (0 = lockout, 1 = chest). Replaces angle for bench paths.
    var benchDepth: Float?

    // Validator selection / state
    var selectedSide: String = ""
    var phase: String = ""

    // 2D overlay landmarks (normalized 0-1)
    var overlayShoulderY: Float?
    var overlayHipY: Float = 0
    var overlayKneeY: Float = 0
    var overlayAnkleY: Float = 0
    var overlayLegSpan: Float?

    // Wrist Y + per-wrist visibility for hinge/bar-path diagnostics (RDL/deadlift/row).
    var overlayLeftWristY: Float?
    var overlayRightWristY: Float?
    var leftWristConfidence: Float?
    var rightWristConfidence: Float?

    // 3D hip depth (squat calibration only — empty for other exercises)
    var hipDepth3D: Float = 0
    var standingHipHeight: Float?
    var standingLegLength: Float?

    // Hysteresis thresholds for the active validator (degrees, or 0..1 for bench depth).
    var thresholdEnter: Float?
    var thresholdExit: Float?

    // Stationary-feet gate state (active rep cycle window; empty when not in cycle).
    var ankleStabilityMinY: Float?
    var ankleStabilityMaxY: Float?

    // Bodyweight squat rep accumulation (other exercises leave at 0).
    var peakDepthThisRep: Float = 0
    var repFrameCount: Int = 0
    var kneeWindowSamples: Int = 0

    // Events
    var repCounted: Bool = false
    var repCommitValid: Bool?
    var rejectReason: String?
}

// MARK: - Debug Logger Singleton

final class SquatRepDebugLogger {
    static let shared = SquatRepDebugLogger()

    var isEnabled: Bool = false

    private(set) var recentFrames: [SquatRepDebugFrame] = []
    private let maxFrames = 600

    private(set) var allFrames: [SquatRepDebugFrame] = []

    private var frameCounter: Int = 0

    var nextFrameIndex: Int { frameCounter }

    func log(_ frame: SquatRepDebugFrame) {
        guard isEnabled else { return }
        recentFrames.append(frame)
        allFrames.append(frame)
        if recentFrames.count > maxFrames {
            recentFrames.removeFirst(recentFrames.count - maxFrames)
        }
        frameCounter += 1
    }

    func reset() {
        recentFrames.removeAll()
        allFrames.removeAll()
        frameCounter = 0
    }

    var latestFrame: SquatRepDebugFrame? {
        recentFrames.last
    }

    var chartFrames: ArraySlice<SquatRepDebugFrame> {
        let count = min(90, recentFrames.count)
        return recentFrames.suffix(count)
    }

    // MARK: - CSV Export

    func exportCSV() -> String {
        var csv = "frame,elapsed,exercise,viewBucket,phase,selectedSide,"
        csv += "primaryAngleRaw,primaryAngleSmoothed,secondaryAngle2DSmoothed,benchDepth,"
        csv += "overlayShoulderY,overlayHipY,overlayKneeY,overlayAnkleY,overlayLegSpan,"
        csv += "overlayLeftWristY,overlayRightWristY,leftWristConf,rightWristConf,"
        csv += "hipDepth3D,standingHipH,standingLegL,"
        csv += "threshEnter,threshExit,"
        csv += "ankleStabMinY,ankleStabMaxY,"
        csv += "peakDepth,repFrames,kneeWindowN,"
        csv += "repCounted,commitValid,rejectReason\n"

        let t0 = allFrames.first?.timestamp ?? 0

        for f in allFrames {
            let elapsed = f.timestamp - t0
            let row = [
                "\(f.frameIndex)",
                String(format: "%.3f", elapsed),
                f.exerciseType, f.viewBucket, f.phase, f.selectedSide,
                fmt(f.primaryAngleRaw), fmt(f.primaryAngleSmoothed),
                fmt(f.secondaryAngle2DSmoothed), fmt(f.benchDepth),
                fmt(f.overlayShoulderY), fmt(f.overlayHipY), fmt(f.overlayKneeY), fmt(f.overlayAnkleY),
                fmt(f.overlayLegSpan),
                fmt(f.overlayLeftWristY), fmt(f.overlayRightWristY),
                fmt(f.leftWristConfidence), fmt(f.rightWristConfidence),
                fmt(f.hipDepth3D),
                fmt(f.standingHipHeight), fmt(f.standingLegLength),
                fmt(f.thresholdEnter), fmt(f.thresholdExit),
                fmt(f.ankleStabilityMinY), fmt(f.ankleStabilityMaxY),
                fmt(f.peakDepthThisRep), "\(f.repFrameCount)", "\(f.kneeWindowSamples)",
                "\(f.repCounted)", f.repCommitValid.map { "\($0)" } ?? "",
                f.rejectReason ?? ""
            ].joined(separator: ",")
            csv += row + "\n"
        }
        return csv
    }

    private func fmt(_ v: Float?) -> String {
        guard let v = v else { return "" }
        return String(format: "%.5f", v)
    }
    private func fmt(_ v: Float) -> String {
        return String(format: "%.5f", v)
    }
}
