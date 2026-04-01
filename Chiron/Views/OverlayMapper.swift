//
//  OverlayMapper.swift
//  Chiron
//
//  Maps MediaPipe normalized 2D landmarks onto SwiftUI overlay coordinates using the same
//  `AVCaptureVideoPreviewLayer` that draws the camera (aspect-fill crop + preview mirroring).
//  Video data output remains unmirrored for analysis; do not apply extra mirrors in Canvas.
//

import AVFoundation
import CoreGraphics

enum OverlayMapper {
    /// Converts a normalized landmark (origin top-left, x right, y down, range [0, 1]) into
    /// overlay coordinates. Returns nil if no preview layer or bounds are invalid.
    static func map(
        normalizedPoint: CGPoint,
        previewLayer: AVCaptureVideoPreviewLayer?,
        overlaySize: CGSize
    ) -> CGPoint? {
        guard let previewLayer else { return nil }
        guard previewLayer.session != nil else { return nil }
        let b = previewLayer.bounds
        guard b.width > 0, b.height > 0 else { return nil }
        // Rotate landmarks 90° counterclockwise before preview-layer conversion.
        let rotatedPoint = CGPoint(
            x: normalizedPoint.y,
            y: 1.0 - normalizedPoint.x
        )
        let layerPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: rotatedPoint)
        let sx = overlaySize.width / b.width
        let sy = overlaySize.height / b.height
        return CGPoint(x: layerPoint.x * sx, y: layerPoint.y * sy)
    }
}
