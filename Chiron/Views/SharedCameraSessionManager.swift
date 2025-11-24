//
//  SharedCameraSessionManager.swift
//  Chiron
//
//  Shared camera session manager and workout UI components used by all active workout views.
//
//  Architecture:
//  - Single camera session shared across all exercise types (bodyweight squat, barbell back squat, etc.)
//  - SquatType is set by camera setup views before calling switchToWorkoutMode()
//  - This allows one camera session and pose manager to serve all squat variations
//  - Related UI components (ActiveWorkoutCameraView, PoseVisualizationOverlay, RestTimerClockView)
//    are also defined here as they're shared across all workout views.
//
//  Usage Pattern:
//  1. Camera setup view sets: SharedCameraSessionManager.shared.poseManager.squatType = .bodyweight (or .barbell)
//  2. Camera setup view calls: SharedCameraSessionManager.shared.switchToWorkoutMode()
//  3. Active workout view calls: SharedCameraSessionManager.shared.startPoseAnalysis()
//  4. Pose manager uses the pre-set squatType for exercise-specific analysis
//

import SwiftUI
import AVFoundation

// MARK: - Shared Camera Session Manager

/// Manages a single camera session shared across all exercise types.
/// The camera session is reused to avoid the overhead of creating multiple sessions.
/// Exercise-specific behavior is controlled via OnDevicePoseManager.squatType, which should be
/// set by the camera setup view before transitioning to workout mode.
class SharedCameraSessionManager: NSObject, ObservableObject {
    static let shared = SharedCameraSessionManager()
    
    private var captureSession: AVCaptureSession?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var isSetupMode = true
    
    // Pose analysis components
    let poseManager = OnDevicePoseManager.shared
    private let coachingManager = OpenAICoachingManager.shared
    
    @Published var isAnalyzingPose = false
    @Published var currentFormAnalysis: FormAnalysis?
    @Published var coachingFeedback: String = ""
    
    private override init() {
        super.init()
    }
    
    func setupCameraSession() {
        guard captureSession == nil else { return }
        
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else { return }
        
        captureSession.sessionPreset = .hd1280x720
        
        // Use FRONT camera only
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: cam),
              captureSession.canAddInput(input) else { return }
        
        captureSession.addInput(input)
        
        // Setup video data output
        videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput?.alwaysDiscardsLateVideoFrames = true
        // Prefer BGRA for downstream Vision/CI processing
        videoDataOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        
        if let videoDataOutput = videoDataOutput, captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }
        
        // Don't start the session here - let the coordinator handle it
        // This prevents conflicts with other coordinators that might be configuring the session
        
        print("📹 SharedCameraSessionManager: Camera session setup completed")
    }
    
    func getCaptureSession() -> AVCaptureSession? {
        return captureSession
    }
    
    func getVideoDataOutput() -> AVCaptureVideoDataOutput? {
        return videoDataOutput
    }
    
    /// Switches camera session to workout mode for pose analysis.
    ///
    /// **Important**: SquatType must be set by the calling camera setup view before this method is called:
    /// ```swift
    /// SharedCameraSessionManager.shared.poseManager.squatType = .bodyweight // or .barbell
    /// SharedCameraSessionManager.shared.switchToWorkoutMode()
    /// ```
    ///
    /// This design allows one camera session to serve all squat variations without duplication.
    func switchToWorkoutMode() {
        isSetupMode = false
        print("📹 SharedCameraSessionManager: Switching to workout mode")
        
        // Update video output delegate for pose analysis
        if let videoDataOutput = videoDataOutput {
            videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "workoutVideoQueue"))
            // Ensure correct orientation and mirroring for analysis buffers
            if let conn = videoDataOutput.connection(with: .video) {
                if #available(iOS 17.0, *) {
                    conn.videoRotationAngle = 90.0
                } else {
                    conn.videoOrientation = .portrait
                }
                if conn.isVideoMirroringSupported {
                    // Do not mirror analysis buffers; preview layer handles user-facing mirroring
                    conn.isVideoMirrored = false
                }
            }
        }
        
        // Note: SquatType should already be set by the calling view (camera setup view)
        // before this method is called. We don't set it here to allow flexibility.
    }
    
    func switchToSetupMode() {
        isSetupMode = true
        print("📹 SharedCameraSessionManager: Switching to setup mode")
        
        // Remove video output delegate (setup view will handle it)
        videoDataOutput?.setSampleBufferDelegate(nil, queue: nil)
    }
    
    func startPoseAnalysis() {
        isAnalyzingPose = true
        print("🎯 SharedCameraSessionManager: Starting pose analysis")
        poseManager.resetRepCountingState()  // Reset all rep counting state
    }
    
    func stopPoseAnalysis() {
        isAnalyzingPose = false
        print("🛑 SharedCameraSessionManager: Stopping pose analysis")
        
        DispatchQueue.main.async {
            self.currentFormAnalysis = nil
        }
        poseManager.resetRepCount()
    }
    
    func stopCamera() {
        print("📹 SharedCameraSessionManager: Stopping camera")
        captureSession?.stopRunning()
        captureSession = nil
        videoDataOutput = nil
    }
}

// MARK: - Video Data Output Delegate
extension SharedCameraSessionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Only analyze pose if we're in workout mode and pose analysis is active
        guard !isSetupMode && isAnalyzingPose else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Debug: Log that we're analyzing frames
        if Int.random(in: 0..<60) == 0 {  // Log occasionally
            print("📹 SharedCameraSessionManager: Analyzing frame in workout mode")
        }
        
        // Analyze pose on device
        poseManager.analyzeFrame(pixelBuffer)
        
        // Update form analysis
        DispatchQueue.main.async {
            self.currentFormAnalysis = self.poseManager.currentFormAnalysis
        }
    }
}

// MARK: - Active Workout Camera View
struct ActiveWorkoutCameraView: UIViewRepresentable {
    func makeUIView(context: Context) -> ActiveWorkoutCameraPreviewView {
        let cameraView = ActiveWorkoutCameraPreviewView()
        return cameraView
    }
    
    func updateUIView(_ uiView: ActiveWorkoutCameraPreviewView, context: Context) {
        // Nothing needed here
    }
}

class ActiveWorkoutCameraPreviewView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupCamera()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCamera()
    }
    
    private func setupCamera() {
        // Use the shared camera session manager
        if let session = SharedCameraSessionManager.shared.getCaptureSession() {
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(previewLayer)
            previewLayer.frame = bounds
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Update the frame of the preview layer
        if let previewLayer = layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = bounds
        }
    }
}

// MARK: - Pose Visualization Overlay
struct PoseVisualizationOverlay: View {
    @ObservedObject private var poseManager = OnDevicePoseManager.shared
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Pose detection status
                VStack {
                    HStack {
                        Circle()
                            .fill(poseManager.poseDetected ? Color.green : Color.red)
                            .frame(width: 12, height: 12)
                        Text(poseManager.poseDetected ? "Pose Detected" : "No Pose")
                            .font(.caption)
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    
                    Spacer()
                }
                .padding(.top, 100)
                .padding(.leading, 20)
                
                // Form analysis info
                VStack {
                    Spacer()
                    
                    if let formAnalysis = poseManager.currentFormAnalysis {
                        VStack(spacing: 8) {
                            Text("Form Score: \(Int(formAnalysis.overallScore * 100))%")
                                .font(.caption)
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 1)
                            
                            Text("Depth: \(Int(formAnalysis.depth * 100))%")
                                .font(.caption)
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 1)
                            
                            Text("Back Angle: \(Int(formAnalysis.backAngle))°")
                                .font(.caption)
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 1)
                            
                            Text("Reps: \(poseManager.repCount)")
                                .font(.caption)
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                    } else {
                        // Show when no form analysis is available
                        VStack(spacing: 8) {
                            Text("No Form Data")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .shadow(color: .black, radius: 1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                    }
                }
                .padding(.bottom, 200)
                .padding(.trailing, 20)
                
                // Center indicator for testing
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack {
                            Text("Pose Visualization Active")
                                .font(.caption)
                                .foregroundColor(.white)
                                .shadow(color: .black, radius: 1)
                            Text("Eye icon to toggle")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .shadow(color: .black, radius: 1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.6))
                        .cornerRadius(8)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Rest Timer Clock View
struct RestTimerClockView: View {
    let restTimeRemaining: TimeInterval
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                .frame(width: 200, height: 200)
            
            // Rotating light indicator
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90)) // Start from top
                .animation(.linear(duration: 1), value: progress)
            
            // Time display
            VStack(spacing: 4) {
                Text(timeString)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                
                Text("REST")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .shadow(color: .black, radius: 1)
            }
        }
        .shadow(color: .black, radius: 4, x: 2, y: 2)
    }
    
    private var timeString: String {
        let minutes = Int(restTimeRemaining) / 60
        let seconds = Int(restTimeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private var progress: Double {
        let totalRestTime: TimeInterval = 60.0 // 60 seconds rest period
        let remaining = max(0, restTimeRemaining)
        return 1.0 - (remaining / totalRestTime)
    }
}

