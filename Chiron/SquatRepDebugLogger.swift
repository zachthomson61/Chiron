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

    // Knee angle (degrees)
    var kneeAngleRaw: Float?
    var kneeAngleSmoothed: Float?
    var selectedSide: String = ""

    // State machine
    var phase: String = "up"

    // 2D overlay landmarks (normalized 0-1)
    var overlayHipY: Float = 0
    var overlayKneeY: Float = 0
    var overlayAnkleY: Float = 0
    var overlayLegSpan: Float?

    // Depth
    var hipDepth3D: Float = 0

    // Calibration
    var standingHipHeight: Float?
    var standingLegLength: Float?

    // Thresholds
    var downAngleThreshold: Float = 0
    var upAngleThreshold: Float = 0

    // Rep accumulation
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
        var csv = "frame,elapsed,phase,"
        csv += "kneeAngleRaw,kneeAngleSmoothed,selectedSide,"
        csv += "overlayHipY,overlayKneeY,overlayAnkleY,overlayLegSpan,"
        csv += "hipDepth3D,"
        csv += "standingHipH,standingLegL,"
        csv += "threshDown,threshUp,"
        csv += "peakDepth,repFrames,kneeWindowN,"
        csv += "repCounted,commitValid,rejectReason\n"

        let t0 = allFrames.first?.timestamp ?? 0

        for f in allFrames {
            let elapsed = f.timestamp - t0
            let row = [
                "\(f.frameIndex)",
                String(format: "%.3f", elapsed),
                f.phase,
                fmt(f.kneeAngleRaw), fmt(f.kneeAngleSmoothed), f.selectedSide,
                fmt(f.overlayHipY), fmt(f.overlayKneeY), fmt(f.overlayAnkleY),
                fmt(f.overlayLegSpan),
                fmt(f.hipDepth3D),
                fmt(f.standingHipHeight), fmt(f.standingLegLength),
                fmt(f.downAngleThreshold), fmt(f.upAngleThreshold),
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
