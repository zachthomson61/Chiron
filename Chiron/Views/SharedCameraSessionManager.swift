//
//  SharedCameraSessionManager.swift
//  Chiron
//
//  Shared camera session manager and workout UI components used by all active workout views.
//
//  Architecture:
//  - Single camera session shared across all exercise types (bodyweight squat, barbell back squat, etc.)
//  - TrackedExerciseType is set by camera setup views before calling switchToWorkoutMode()
//  - This allows one camera session and pose manager to serve all squat variations
//  - Related UI components (ActiveWorkoutCameraView, PoseVisualizationOverlay, RestTimerClockView)
//    are also defined here as they're shared across all workout views.
//
//  Usage Pattern:
//  1. Camera setup view sets: SharedCameraSessionManager.shared.poseManager.trackedExerciseType = .bodyweight (or .barbell)
//  2. Camera setup view calls: SharedCameraSessionManager.shared.switchToWorkoutMode()
//  3. Active workout view calls: SharedCameraSessionManager.shared.startPoseAnalysis()
//  4. Pose manager uses the pre-set trackedExerciseType for exercise-specific analysis
//

import SwiftUI
import AVFoundation

// MARK: - Shared Camera Session Manager

/// Manages a single camera session shared across all exercise types.
/// The camera session is reused to avoid the overhead of creating multiple sessions.
/// Exercise-specific behavior is controlled via OnDevicePoseManager.trackedExerciseType, which should be
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
        // BGRA for downstream MediaPipe / CI processing
        videoDataOutput?.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        
        if let videoDataOutput = videoDataOutput, captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        }
        
        // Don't start the session here - let the coordinator handle it
        // This prevents conflicts with other coordinators that might be configuring the session
        
    }
    
    func getCaptureSession() -> AVCaptureSession? {
        return captureSession
    }
    
    func getVideoDataOutput() -> AVCaptureVideoDataOutput? {
        return videoDataOutput
    }
    
    /// Returns `true` if currently in setup mode (segmentation), `false` if in workout mode (pose analysis).
    /// Used by camera preview views to determine whether to bind segmentation or pose analysis delegates.
    var isInSetupMode: Bool {
        return isSetupMode
    }
    
    /// Switches camera session to workout mode for pose analysis.
    ///
    /// **Important**: TrackedExerciseType must be set by the calling camera setup view before this method is called:
    /// ```swift
    /// SharedCameraSessionManager.shared.poseManager.trackedExerciseType = .bodyweight // or .barbell
    /// SharedCameraSessionManager.shared.switchToWorkoutMode()
    /// ```
    ///
    /// This design allows one camera session to serve all squat variations without duplication.
    func switchToWorkoutMode() {
        isSetupMode = false
        
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
        
        // Note: TrackedExerciseType should already be set by the calling view (camera setup view)
        // before this method is called. We don't set it here to allow flexibility.
    }
    
    func switchToSetupMode() {
        isSetupMode = true
        
        // Remove video output delegate (setup view will handle it)
        videoDataOutput?.setSampleBufferDelegate(nil, queue: nil)
    }
    
    /// Starts pose analysis and resets all rep/session state (use when starting a coached workout flow).
    func startPoseAnalysis() {
        isAnalyzingPose = true
        poseManager.resetRepCountingState()
    }
    
    /// Starts pose tracking only (overlay, smoothing) without resetting state.
    /// Use when you want tracking to run before the user starts a set (e.g. Track tab on appear).
    /// Coaching API should only receive form data from Begin Set → End Set.
    func startPoseTrackingOnly() {
        isAnalyzingPose = true
    }
    
    func stopPoseAnalysis() {
        isAnalyzingPose = false
        
        DispatchQueue.main.async {
            self.currentFormAnalysis = nil
        }
        poseManager.resetRepCount()
    }
    
    func stopCamera() {
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

/// Skeleton edges in Vision body pose order (joint names from OnDevicePoseManager.extractKeyPoints).
private let poseSkeletonEdges: [(String, String)] = [
    ("leftShoulder", "rightShoulder"),
    ("leftShoulder", "leftElbow"),
    ("rightShoulder", "rightElbow"),
    ("leftElbow", "leftWrist"),
    ("rightElbow", "rightWrist"),
    ("leftShoulder", "leftHip"),
    ("rightShoulder", "rightHip"),
    ("leftHip", "rightHip"),
    ("leftHip", "leftKnee"),
    ("rightHip", "rightKnee"),
    ("leftKnee", "leftAnkle"),
    ("rightKnee", "rightAnkle"),
    ("nose", "leftEye"),
    ("nose", "rightEye"),
    ("leftEye", "leftEar"),
    ("rightEye", "rightEar"),
]

struct PoseVisualizationOverlay: View {
    @ObservedObject private var poseManager = OnDevicePoseManager.shared
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Landmark skeleton and joints (normalized 0–1, origin top-left)
                if let landmarks = poseManager.currentNormalizedLandmarks, !landmarks.isEmpty {
                    PoseLandmarkSkeletonView(landmarks: landmarks, size: geometry.size)
                }
                
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

// MARK: - Pose Landmark Skeleton (lines + joints)

/// Draws skeleton edges and landmark circles from normalized landmarks (0–1, origin top-left).
/// Transform: portrait (normX, normY) → preview view, with horizontal flip so overlay matches
/// the mirrored front-camera preview.
struct PoseLandmarkSkeletonView: View {
    let landmarks: [String: CGPoint]
    let size: CGSize
    
    var body: some View {
        Canvas { context, canvasSize in
            func viewPoint(_ p: CGPoint) -> CGPoint {
                let viewX = (1.0 - p.y) * size.width   // flip X so overlay matches mirrored preview
                let viewY = (1.0 - p.x) * size.height
                return CGPoint(x: viewX, y: viewY)
            }
            
            // Draw skeleton edges
            for (a, b) in poseSkeletonEdges {
                guard let pa = landmarks[a], let pb = landmarks[b] else { continue }
                var path = Path()
                path.move(to: viewPoint(pa))
                path.addLine(to: viewPoint(pb))
                context.stroke(path, with: .color(.green), lineWidth: 3)
            }
            
            // Draw landmark circles
            for (_, point) in landmarks {
                let center = viewPoint(point)
                let r: CGFloat = 6
                let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.cyan))
                context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
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

