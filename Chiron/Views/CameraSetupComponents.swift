//
//  CameraSetupComponents.swift
//  Chiron
//
//  Shared UI components for camera setup views.
//
//  These components are used by the unified CameraSetupView to handle the camera preview
//  and segmentation overlay display. They work with any exercise type.
//
//  Components:
//  - SegmentationOverlayView: Displays the colored silhouette overlay (green/yellow/red based on setup quality)
//  - SetupCameraPreviewRepresentable: SwiftUI wrapper for the UIKit camera preview
//  - SetupCameraPreviewView: UIKit view that manages the camera preview layer and segmentation delegate
//

import SwiftUI
import AVFoundation

// MARK: - Segmentation Overlay View

/// Displays the person segmentation overlay as a colored silhouette.
/// Color indicates setup quality: green (good), yellow (partial), red (poor).
struct SegmentationOverlayView: View {
    @ObservedObject var processor: SegmentationProcessor
    
    var body: some View {
        GeometryReader { geo in
            if let cg = processor.overlayImage {
                Image(uiImage: UIImage(cgImage: cg))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - Camera Preview (Setup Mode)

/// SwiftUI wrapper for the UIKit camera preview used during setup mode.
struct SetupCameraPreviewRepresentable: UIViewRepresentable {
    @ObservedObject var processor: SegmentationProcessor
    func makeUIView(context: Context) -> SetupCameraPreviewView {
        SetupCameraPreviewView(processor: processor)
    }
    func updateUIView(_ uiView: SetupCameraPreviewView, context: Context) {
        uiView.updateProcessor(processor)
        uiView.rebindSegmentationDelegate()
    }
}

/// UIKit view that manages the camera preview layer and segmentation processing during setup mode.
/// Handles preview layer setup, video delegate binding, and connection configuration.
final class SetupCameraPreviewView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var processor: SegmentationProcessor?
    private var videoDelegate: VideoDelegate?
    private var segmentationQueue: DispatchQueue?
    
    init(processor: SegmentationProcessor? = nil) {
        self.processor = processor
        super.init(frame: .zero)
        setup()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        // Set up immediately; will retry quickly if session isn't ready yet
        setupPreviewLayer()
    }
    
    private func setupPreviewLayer() {
        guard let session = SharedCameraSessionManager.shared.getCaptureSession() else {
            // Retry quickly if session isn't ready yet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.setupPreviewLayer()
            }
            return
        }
        
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        // Mirror for front camera UI only; analysis buffers are unmirrored in manager
        layer.connection?.automaticallyAdjustsVideoMirroring = false
        layer.connection?.isVideoMirrored = true
        previewLayer = layer
        self.layer.addSublayer(layer)
        layer.frame = bounds
        
        // Attach video output delegate for segmentation during setup mode
        rebindSegmentationDelegate()
        
        // Ensure session is running
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
    
    deinit {
        // Detach delegate when view goes away
        SharedCameraSessionManager.shared.getVideoDataOutput()?.setSampleBufferDelegate(nil, queue: nil)
    }
    
    func updateProcessor(_ processor: SegmentationProcessor) {
        self.processor = processor
        videoDelegate?.processor = processor
    }
    
    /// Rebinds the video output delegate to segmentation processing.
    /// Only rebinds if in setup mode to avoid overriding the pose analysis delegate during workouts.
    func rebindSegmentationDelegate() {
        guard SharedCameraSessionManager.shared.isInSetupMode else {
            return
        }
        guard let videoOutput = SharedCameraSessionManager.shared.getVideoDataOutput() else { return }
        bindSegmentationDelegate(to: videoOutput)
    }
    
    private func bindSegmentationDelegate(to videoOutput: AVCaptureVideoDataOutput) {
        if segmentationQueue == nil {
            segmentationQueue = DispatchQueue(label: "segmentationVideoQueue")
        }
        if videoDelegate == nil {
            videoDelegate = VideoDelegate(processor: processor)
        } else {
            videoDelegate?.processor = processor
        }
        
        videoOutput.setSampleBufferDelegate(videoDelegate, queue: segmentationQueue)
        configureVideoConnection(for: videoOutput)
    }
    
    private func configureVideoConnection(for output: AVCaptureVideoDataOutput) {
        guard let connection = output.connection(with: .video) else { return }
        if #available(iOS 17.0, *) {
            connection.videoRotationAngle = 90.0
        } else {
            connection.videoOrientation = .portrait
        }
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = false
        }
    }
    
    // MARK: - Delegate proxy
    private final class VideoDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        weak var processor: SegmentationProcessor?
        init(processor: SegmentationProcessor?) {
            self.processor = processor
        }
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            processor?.process(sampleBuffer: sampleBuffer, mirrored: true)
        }
    }
}

