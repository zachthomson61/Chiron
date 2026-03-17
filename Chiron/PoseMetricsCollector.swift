//
//  PoseMetricsCollector.swift
//  Chiron
//
//  Tracks pipeline metrics for validation: frames sent/received, dropped frames,
//  rolling average inference latency, and per-joint jitter over a sliding window.
//  Used by OnDevicePoseManager and by PoseMetricsView (Settings → Developer).
//

import Foundation
import CoreGraphics
import QuartzCore

final class PoseMetricsCollector: ObservableObject {

    @Published private(set) var framesSent: Int = 0
    @Published private(set) var framesReceived: Int = 0
    @Published private(set) var droppedFrames: Int = 0
    @Published private(set) var avgLatencyMs: Double = 0
    @Published private(set) var overallJitter: Double = 0
    @Published private(set) var perJointJitter: [String: Double] = [:]

    private let windowSize = 30
    private var latencyBuffer: [Double] = []
    private var sendTimestamps: [CFTimeInterval] = []
    private var jitterWindow: [[String: CGPoint]] = []

    func frameSent() {
        framesSent += 1
        sendTimestamps.append(CACurrentMediaTime())
    }

    @discardableResult
    func frameReceived() -> Double {
        framesReceived += 1
        droppedFrames = max(0, framesSent - framesReceived)

        let now = CACurrentMediaTime()
        var latencyMs: Double = 0
        if let sendTime = sendTimestamps.first {
            sendTimestamps.removeFirst()
            latencyMs = (now - sendTime) * 1000.0
        }

        latencyBuffer.append(latencyMs)
        if latencyBuffer.count > windowSize { latencyBuffer.removeFirst() }
        avgLatencyMs = latencyBuffer.reduce(0, +) / Double(latencyBuffer.count)

        return latencyMs
    }

    func recordJitterSample(_ landmarks: [String: CGPoint]) {
        jitterWindow.append(landmarks)
        if jitterWindow.count > windowSize { jitterWindow.removeFirst() }
        guard jitterWindow.count >= 2 else { return }

        var perJoint: [String: Double] = [:]
        for key in Set(jitterWindow.flatMap(\.keys)) {
            let positions = jitterWindow.compactMap { $0[key] }
            guard positions.count >= 2 else { continue }
            let meanX = positions.map(\.x).reduce(0, +) / CGFloat(positions.count)
            let meanY = positions.map(\.y).reduce(0, +) / CGFloat(positions.count)
            let variance = positions.reduce(0.0) { acc, p in
                let dx = p.x - meanX, dy = p.y - meanY
                return acc + Double(dx * dx + dy * dy)
            } / Double(positions.count)
            perJoint[key] = variance
        }

        perJointJitter = perJoint
        overallJitter = perJoint.values.isEmpty ? 0 : perJoint.values.reduce(0, +) / Double(perJoint.values.count)
    }

    func reset() {
        framesSent = 0
        framesReceived = 0
        droppedFrames = 0
        avgLatencyMs = 0
        overallJitter = 0
        perJointJitter = [:]
        latencyBuffer.removeAll()
        sendTimestamps.removeAll()
        jitterWindow.removeAll()
    }
}
