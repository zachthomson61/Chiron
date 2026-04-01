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
    
    /// Preview layer used for pose overlay mapping; registered from preview UIViews in `layoutSubviews`.
    weak var poseOverlayPreviewLayer: AVCaptureVideoPreviewLayer?
    
    func registerPoseOverlayPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        poseOverlayPreviewLayer = layer
    }
    
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
    
    /// Ends a Track-tab set without stopping camera pose updates, so the skeleton overlay keeps moving between sets.
    /// Full coaching still only runs during an active set from the Track UI; this only clears shared form UI and rep count.
    func endTrackSetKeepingPoseActive() {
        DispatchQueue.main.async {
            self.currentFormAnalysis = nil
        }
        poseManager.resetRepCount()
    }
    
    func stopCamera() {
        poseOverlayPreviewLayer = nil
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
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    private func ensurePreviewLayer() {
        guard previewLayer == nil else { return }
        guard let session = SharedCameraSessionManager.shared.getCaptureSession() else { return }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.automaticallyAdjustsVideoMirroring = false
        layer.connection?.isVideoMirrored = true
        self.layer.addSublayer(layer)
        previewLayer = layer
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        ensurePreviewLayer()
        previewLayer?.frame = bounds
        if let pl = previewLayer {
            SharedCameraSessionManager.shared.registerPoseOverlayPreviewLayer(pl)
        }
    }
}

// MARK: - Pose Visualization Overlay

/// Skeleton edges for overlay; joint names match MediaPipePoseAdapter overlay keys.
/// Legs include ankle→heel and ankle→footIndex so the lowest dots reflect actual foot position.
private let poseSkeletonEdges: [(String, String)] = [
    ("leftShoulder", "rightShoulder"),
    ("leftShoulder", "leftElbow"),
    ("rightShoulder", "rightElbow"),
    ("leftElbow", "leftWrist"),
    ("rightElbow", "rightWrist"),
    ("leftWrist", "leftPinky"),
    ("rightWrist", "rightPinky"),
    ("leftWrist", "leftIndex"),
    ("rightWrist", "rightIndex"),
    ("leftWrist", "leftThumb"),
    ("rightWrist", "rightThumb"),
    ("leftShoulder", "leftHip"),
    ("rightShoulder", "rightHip"),
    ("leftHip", "rightHip"),
    ("leftHip", "leftKnee"),
    ("rightHip", "rightKnee"),
    ("leftKnee", "leftAnkle"),
    ("rightKnee", "rightAnkle"),
    ("leftAnkle", "leftHeel"),
    ("rightAnkle", "rightHeel"),
    ("leftAnkle", "leftFootIndex"),
    ("rightAnkle", "rightFootIndex"),
    ("nose", "leftEye"),
    ("nose", "rightEye"),
    ("leftEye", "leftEar"),
    ("rightEye", "rightEar"),
]

struct PoseVisualizationOverlay: View {
    @ObservedObject private var poseManager = OnDevicePoseManager.shared
    
    var body: some View {
        GeometryReader { _ in
            ZStack {
                // Landmark skeleton and joints (normalized 0–1, origin top-left)
                if let landmarks = poseManager.currentNormalizedLandmarks, !landmarks.isEmpty {
                    PoseLandmarkSkeletonView(landmarks: landmarks)
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
                            
                            Text(poseManager.trackedExerciseType == .bodyweight ? "Reps: —" : "Reps: \(poseManager.repCount)")
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
        .ignoresSafeArea()
    }
}

// MARK: - Pose Landmark Skeleton (lines + joints)

/// Draws skeleton edges and landmark circles from normalized landmarks (0–1, origin top-left).
/// Points are mapped through `SharedCameraSessionManager.poseOverlayPreviewLayer` via `OverlayMapper`.
struct PoseLandmarkSkeletonView: View {
    let landmarks: [String: CGPoint]
    
    var body: some View {
        Canvas { context, canvasSize in
            let previewLayer = SharedCameraSessionManager.shared.poseOverlayPreviewLayer

            func viewPoint(_ p: CGPoint) -> CGPoint? {
                OverlayMapper.map(normalizedPoint: p, previewLayer: previewLayer, overlaySize: canvasSize)
            }

            for (a, b) in poseSkeletonEdges {
                guard let pa = landmarks[a], let pb = landmarks[b] else { continue }
                guard let va = viewPoint(pa), let vb = viewPoint(pb) else { continue }
                var path = Path()
                path.move(to: va)
                path.addLine(to: vb)
                context.stroke(path, with: .color(.green), lineWidth: 3)
            }

            for (_, point) in landmarks {
                guard let center = viewPoint(point) else { continue }
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

