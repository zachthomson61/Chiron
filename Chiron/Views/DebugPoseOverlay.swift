//
//  DebugPoseOverlay.swift
//
//  Developer-only landmark labels. Toggle: `DebugPoseOverlay.isEnabled` (e.g. Settings → Pose Metrics).
//  Coordinates: `PoseOverlayCoordinateMapping` in SharedCameraSessionManager (must match main skeleton).
//

import SwiftUI

struct DebugPoseOverlay: View {
    @ObservedObject private var poseManager = OnDevicePoseManager.shared
    static var isEnabled: Bool = false

    var body: some View {
        if DebugPoseOverlay.isEnabled {
            GeometryReader { _ in
                Canvas { context, canvasSize in
                    guard let landmarks = poseManager.currentNormalizedLandmarks, !landmarks.isEmpty else { return }
                    for (name, point) in landmarks {
                        let viewPt = PoseOverlayCoordinateMapping.viewPoint(normalized: point, canvasSize: canvasSize)
                        let r: CGFloat = 5
                        let rect = CGRect(x: viewPt.x - r, y: viewPt.y - r, width: r * 2, height: r * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(.yellow.opacity(0.9)))
                        let text = Text(abbrev(for: name)).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(.white)
                        context.draw(text, at: CGPoint(x: viewPt.x, y: viewPt.y - 10))
                    }
                }
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
        }
    }

    private func abbrev(for jointName: String) -> String {
        switch jointName {
        case "leftShoulder": return "LS"
        case "rightShoulder": return "RS"
        case "leftElbow": return "LE"
        case "rightElbow": return "RE"
        case "leftWrist": return "LW"
        case "rightWrist": return "RW"
        case "leftHip": return "LH"
        case "rightHip": return "RH"
        case "leftKnee": return "LK"
        case "rightKnee": return "RK"
        case "leftAnkle": return "LA"
        case "rightAnkle": return "RA"
        case "nose": return "N"
        case "leftEye": return "LEy"
        case "rightEye": return "REy"
        case "leftEar": return "LEr"
        case "rightEar": return "REr"
        case "neck": return "Nk"
        default: return String(jointName.prefix(3))
        }
    }
}
