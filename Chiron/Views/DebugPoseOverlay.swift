//
//  DebugPoseOverlay.swift
//  Chiron
//
//  Optional overlay that draws MediaPipe landmark points and short labels on the
//  camera feed. Toggle via DebugPoseOverlay.isEnabled (e.g. Settings → Developer →
//  Pose Metrics → “Show debug overlay”). Uses same coordinate transform as the
//  main skeleton overlay so it aligns with the mirrored preview.
//

import SwiftUI

struct DebugPoseOverlay: View {
    @ObservedObject private var poseManager = OnDevicePoseManager.shared
    static var isEnabled: Bool = false

    var body: some View {
        if DebugPoseOverlay.isEnabled {
            GeometryReader { geometry in
                Canvas { context, canvasSize in
                    guard let landmarks = poseManager.currentNormalizedLandmarks, !landmarks.isEmpty else { return }
                    let previewLayer = SharedCameraSessionManager.shared.poseOverlayPreviewLayer
                    for (name, point) in landmarks {
                        guard let viewPt = OverlayMapper.map(
                            normalizedPoint: point,
                            previewLayer: previewLayer,
                            overlaySize: canvasSize
                        ) else { continue }
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
        case "leftPinky": return "LP"
        case "rightPinky": return "RP"
        case "leftIndex": return "LI"
        case "rightIndex": return "RI"
        case "leftThumb": return "LTh"
        case "rightThumb": return "RTh"
        case "leftHip": return "LH"
        case "rightHip": return "RH"
        case "leftKnee": return "LK"
        case "rightKnee": return "RK"
        case "leftAnkle": return "LA"
        case "rightAnkle": return "RA"
        case "leftHeel": return "LHe"
        case "rightHeel": return "RHe"
        case "leftFootIndex": return "LFi"
        case "rightFootIndex": return "RFi"
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
