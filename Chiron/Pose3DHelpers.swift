//
//  Pose3DHelpers.swift
//  Chiron
//
//  Shared 3D pose types (Skeleton3D, Joint3D), angle helpers, and temporal
//  smoothers. Backend-specific joint mapping lives in MediaPipePoseAdapter.
//

import Foundation
import CoreGraphics
import simd

// MARK: - Pose Analysis Source

enum PoseAnalysisSource {
    case pose2D
    case pose3D
}

// MARK: - 3D Joint

struct Joint3D {
    let position: SIMD3<Float>
    let confidence: Float
}

// MARK: - 3D Skeleton

struct Skeleton3D {
    let joints: [String: Joint3D]

    func position(_ name: String) -> SIMD3<Float>? {
        joints[name]?.position
    }

    /// Checks whether the minimum joints required for the given exercise are present.
    /// Allows at most one missing joint from the required set.
    func meetsMinimumRequirements(for exerciseType: TrackedExerciseType) -> Bool {
        let requiredJoints: [String]
        switch exerciseType {
        case .bodyweight, .barbell:
            requiredJoints = [
                "leftHip", "rightHip", "leftKnee", "rightKnee",
                "leftAnkle", "rightAnkle", "centerShoulder"
            ]
        case .benchPress, .closeGripBenchPress:
            requiredJoints = [
                "leftShoulder", "rightShoulder", "leftElbow", "rightElbow",
                "leftWrist", "rightWrist", "leftHip", "rightHip"
            ]
        }
        let present = requiredJoints.filter { joints[$0] != nil }.count
        return present >= requiredJoints.count - 1
    }
}

// MARK: - 3D Angle Helper

/// Returns the angle at vertex `b` formed by rays b→a and b→c, in degrees (0–180).
/// All inputs are 3D positions — never use projected 2D image points here.
func angleDegrees(a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>) -> Float {
    let ba = a - b
    let bc = c - b
    let lenBA = length(ba)
    let lenBC = length(bc)
    guard lenBA > .ulpOfOne, lenBC > .ulpOfOne else { return 0 }
    let cosAngle = dot(ba, bc) / (lenBA * lenBC)
    return acos(max(-1, min(1, cosAngle))) * 180.0 / .pi
}

// MARK: - Joint Smoother (Two-stage EMA for 3D positions)

/// Low-latency temporal smoothing for 3D joint positions.
/// Uses two-stage exponential moving average to reduce jitter while staying responsive.
class JointSmoother {
    private var firstPass: [String: SIMD3<Float>] = [:]
    private var secondPass: [String: SIMD3<Float>] = [:]
    private let alpha1: Float
    private let alpha2: Float

    /// - Parameters:
    ///   - alpha: Single-stage EMA weight for new sample (0.15–0.25 typical). Lower = smoother, higher lag.
    ///   - twoStage: If true, applies a second EMA pass for extra smoothness (recommended for live camera).
    init(alpha: Float = 0.2, twoStage: Bool = true) {
        self.alpha1 = alpha
        self.alpha2 = twoStage ? alpha : 1.0
    }

    func smooth(_ skeleton: Skeleton3D) -> Skeleton3D {
        var out: [String: Joint3D] = [:]
        for (name, joint) in skeleton.joints {
            let raw = joint.position
            let s1: SIMD3<Float>
            if let p1 = firstPass[name] {
                s1 = alpha1 * raw + (1 - alpha1) * p1
            } else {
                s1 = raw
            }
            firstPass[name] = s1

            let s2: SIMD3<Float>
            if let p2 = secondPass[name] {
                s2 = alpha2 * s1 + (1 - alpha2) * p2
            } else {
                s2 = s1
            }
            secondPass[name] = s2

            out[name] = Joint3D(position: s2, confidence: joint.confidence)
        }
        return Skeleton3D(joints: out)
    }

    func reset() {
        firstPass.removeAll()
        secondPass.removeAll()
    }
}

// MARK: - 2D Landmark Smoother (for overlay drawing)

/// Smooths normalized 2D landmarks for stable overlay drawing.
/// Uses adaptive alpha: when movement is small (user still), smooths heavily to stop jitter;
/// when movement is large, uses higher alpha so the overlay stays responsive.
class Landmark2DSmoother {
    private var previous: [String: CGPoint] = [:]
    private let alphaWhenMoving: CGFloat
    private let alphaWhenStill: CGFloat
    /// Movement threshold in normalized coords (0–1). Below this we treat as "still" and smooth more.
    private let stillThreshold: CGFloat

    /// - Parameters:
    ///   - alphaWhenMoving: EMA weight when pose is moving (e.g. 0.2). Higher = more responsive.
    ///   - alphaWhenStill: EMA weight when pose is nearly still (e.g. 0.06). Lower = less jitter.
    ///   - stillThreshold: Max average displacement to consider "still" (e.g. 0.012 ≈ 1.2% of frame).
    init(alphaWhenMoving: CGFloat = 0.2, alphaWhenStill: CGFloat = 0.06, stillThreshold: CGFloat = 0.012) {
        self.alphaWhenMoving = alphaWhenMoving
        self.alphaWhenStill = alphaWhenStill
        self.stillThreshold = stillThreshold
    }

    func smooth(_ landmarks: [String: CGPoint]) -> [String: CGPoint] {
        // Measure how much the pose moved from previous smoothed frame
        var totalDistance: CGFloat = 0
        var count: Int = 0
        for (name, point) in landmarks {
            if let prev = previous[name] {
                let dx = point.x - prev.x
                let dy = point.y - prev.y
                totalDistance += sqrt(dx * dx + dy * dy)
                count += 1
            }
        }
        let avgDisplacement = count > 0 ? totalDistance / CGFloat(count) : 0
        let isStill = avgDisplacement <= stillThreshold
        let alpha = isStill ? alphaWhenStill : alphaWhenMoving

        var out: [String: CGPoint] = [:]
        for (name, point) in landmarks {
            let smoothed: CGPoint
            if let prev = previous[name] {
                smoothed = CGPoint(
                    x: alpha * point.x + (1 - alpha) * prev.x,
                    y: alpha * point.y + (1 - alpha) * prev.y
                )
            } else {
                smoothed = point
            }
            previous[name] = smoothed
            out[name] = smoothed
        }
        return out
    }

    func reset() {
        previous.removeAll()
    }
}

