//
//  MediaPipePoseAdapter.swift
//  Chiron
//
//  Maps MediaPipe Pose Landmarker output into the app’s pose types. Single responsibility:
//  input = PoseLandmarkerResult, output = Skeleton3D + overlay [String: CGPoint].
//  Used by OnDevicePoseManager; does not reference Vision or create the landmarker.
//

import Foundation
import CoreGraphics
import simd
import MediaPipeTasksVision

// MARK: - Adapter Output

struct PoseAdapterResult {
    let skeleton: Skeleton3D
    let overlayLandmarks: [String: CGPoint]
    let perJointConfidence: [String: Float]
    let timestampMs: Int
}

// MARK: - MediaPipe Pose Adapter

struct MediaPipePoseAdapter {

    /// Returns nil if the result has no pose.
    func adapt(_ result: PoseLandmarkerResult, timestampMs: Int) -> PoseAdapterResult? {
        guard let worldPose = result.worldLandmarks.first,
              let imagePose = result.landmarks.first else {
            return nil
        }

        let (skeleton, confidence3D) = buildSkeleton(from: worldPose)
        let (overlay, confidence2D) = buildOverlayLandmarks(from: imagePose)

        var mergedConfidence = confidence3D
        for (key, val) in confidence2D where mergedConfidence[key] == nil {
            mergedConfidence[key] = val
        }

        return PoseAdapterResult(
            skeleton: skeleton,
            overlayLandmarks: overlay,
            perJointConfidence: mergedConfidence,
            timestampMs: timestampMs
        )
    }

    // MARK: - Skeleton (world landmarks, meters, hip origin)

    private func buildSkeleton(from worldPose: [Landmark]) -> (Skeleton3D, [String: Float]) {
        var joints: [String: Joint3D] = [:]
        var confidence: [String: Float] = [:]

        for (index, mapping) in MediaPipePoseAdapter.worldIndexMap {
            guard index < worldPose.count else { continue }
            let lm = worldPose[index]
            let pos = SIMD3<Float>(lm.x, lm.y, lm.z)
            let vis = lm.visibility?.floatValue ?? 1.0
            joints[mapping] = Joint3D(position: pos, confidence: vis)
            confidence[mapping] = vis
        }

        if let ls = joints["leftShoulder"], let rs = joints["rightShoulder"] {
            let mid = (ls.position + rs.position) / 2.0
            joints["centerShoulder"] = Joint3D(position: mid, confidence: min(ls.confidence, rs.confidence))
            confidence["centerShoulder"] = min(ls.confidence, rs.confidence)
        }
        if let lh = joints["leftHip"], let rh = joints["rightHip"] {
            let mid = (lh.position + rh.position) / 2.0
            joints["root"] = Joint3D(position: mid, confidence: min(lh.confidence, rh.confidence))
            confidence["root"] = min(lh.confidence, rh.confidence)
        }
        if let cs = joints["centerShoulder"], let rt = joints["root"] {
            let mid = (cs.position + rt.position) / 2.0
            joints["spine"] = Joint3D(position: mid, confidence: min(cs.confidence, rt.confidence))
            confidence["spine"] = min(cs.confidence, rt.confidence)
        }
        if let nose = joints["nose"] {
            joints["centerHead"] = Joint3D(position: nose.position, confidence: nose.confidence)
            confidence["centerHead"] = nose.confidence
            joints["topHead"] = Joint3D(position: nose.position + SIMD3<Float>(0, 0.08, 0), confidence: nose.confidence)
            confidence["topHead"] = nose.confidence
        }

        return (Skeleton3D(joints: joints), confidence)
    }

    // MARK: - Overlay (normalised image coords, same keys as overlay UI)
    //
    // These CGPoints become `OnDevicePoseManager.currentNormalizedLandmarks`. On-screen mapping
    // for the mirrored front camera is `PoseOverlayCoordinateMapping` (SharedCameraSessionManager).

    private func buildOverlayLandmarks(from imagePose: [NormalizedLandmark]) -> ([String: CGPoint], [String: Float]) {
        var overlay: [String: CGPoint] = [:]
        var confidence: [String: Float] = [:]

        for (index, key) in MediaPipePoseAdapter.overlayIndexMap {
            guard index < imagePose.count else { continue }
            let lm = imagePose[index]
            overlay[key] = CGPoint(x: CGFloat(lm.x), y: CGFloat(lm.y))
            confidence[key] = lm.visibility?.floatValue ?? 1.0
        }

        if let ls = overlay["leftShoulder"], let rs = overlay["rightShoulder"] {
            overlay["neck"] = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
        }

        return (overlay, confidence)
    }

    /// MediaPipe 33-landmark index → app joint name. See MediaPipe Pose landmark spec.
    private static let worldIndexMap: [(Int, String)] = [
        (0, "nose"), (11, "leftShoulder"), (12, "rightShoulder"),
        (13, "leftElbow"), (14, "rightElbow"), (15, "leftWrist"), (16, "rightWrist"),
        (23, "leftHip"), (24, "rightHip"), (25, "leftKnee"), (26, "rightKnee"),
        (27, "leftAnkle"), (28, "rightAnkle"),
    ]

    private static let overlayIndexMap: [(Int, String)] = [
        (0, "nose"), (2, "leftEye"), (5, "rightEye"), (7, "leftEar"), (8, "rightEar"),
        (11, "leftShoulder"), (12, "rightShoulder"), (13, "leftElbow"), (14, "rightElbow"),
        (15, "leftWrist"), (16, "rightWrist"), (23, "leftHip"), (24, "rightHip"),
        (25, "leftKnee"), (26, "rightKnee"), (27, "leftAnkle"), (28, "rightAnkle"),
    ]
}
