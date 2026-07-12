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
import QuartzCore

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
    
    /// When `true`, pose frames still run but rep validation does not advance (e.g. Track tab while framing or between sets).
    var suppressRepCounting: Bool = false
    
    /// When `true`, Track tab has started a set via "Begin Set" — skip inactivity-based `handleSetEnd` so pauses between reps do not zero the counter.
    var trackExplicitSetActive: Bool = false

    /// Timestamp of the last frame forwarded to MediaPipe. Touched only on the video
    /// data output queue (`captureOutput`); used for thermal/idle frame decimation.
    private var lastInferenceAt: CFTimeInterval = 0

    /// Serial queue for all startRunning/stopRunning work. Pause and resume used to
    /// dispatch to the CONCURRENT global queue, so a fast pause→resume (sheet dismiss,
    /// tab switch) could execute out of order and leave the camera permanently dark:
    /// resume's `!isRunning` guard no-ops while the session still runs, then the stale
    /// pause stops it. Serializing preserves caller order.
    private let sessionControlQueue = DispatchQueue(label: "cameraSessionControl")

    /// Whether the capture session should be restarted when the app returns to the
    /// foreground (i.e. it was running when the app backgrounded). Touched only on
    /// `sessionControlQueue` so it reflects the settled state after pending pause/resume
    /// work, not a possibly-stale `isRunning` snapshot.
    private var resumeOnForeground = false
    /// Whether pose analysis was active when the app backgrounded. Main queue only.
    private var wasAnalyzingOnBackground = false
    
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

        // Cap capture at 30 fps. The pose pipeline assumes ~30 fps; on devices whose
        // default active format delivers 60 fps this would double inference load
        // (and heat) for zero coaching benefit. Only the ceiling is pinned — leaving
        // the max frame duration alone lets auto-exposure drop below 30 fps in dim
        // gyms, which saves power rather than costing it.
        if (try? cam.lockForConfiguration()) != nil {
            cam.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            cam.unlockForConfiguration()
        }
        
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
    
    /// Use when ending a **Track** set only. Does **not** set `isAnalyzingPose = false`.
    ///
    /// `captureOutput` only calls `poseManager.analyzeFrame` while `isAnalyzingPose` is true.
    /// `stopPoseAnalysis()` therefore freezes the skeleton until the next **Begin Set**. This method
    /// resets rep/UI state while keeping frames flowing so the overlay stays live in `.armed`.
    func endTrackSetKeepingPoseActive() {
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

    /// Pauses the capture session without tearing it down, so the preview layer goes dark
    /// and the camera hardware stops drawing power while an overlay (e.g. the Track info sheet)
    /// is covering the preview. Pair with `resumeCaptureSession()` when the overlay is dismissed.
    ///
    /// Also flips `isAnalyzingPose` off so `captureOutput` short-circuits on any already-queued frames.
    /// Callers that had pose analysis running should track that and call `startPoseTrackingOnly()` /
    /// `startPoseAnalysis()` on resume.
    func pauseCaptureSession() {
        isAnalyzingPose = false
        sessionControlQueue.async { [weak self] in
            guard let session = self?.captureSession, session.isRunning else { return }
            session.stopRunning()
        }
    }

    /// Resumes a previously paused capture session. Safe no-op if the session is already running
    /// or was never set up.
    func resumeCaptureSession() {
        sessionControlQueue.async { [weak self] in
            guard let session = self?.captureSession, !session.isRunning else { return }
            session.startRunning()
        }
    }

    // MARK: - App lifecycle (scene phase)

    /// Called when the app moves to the background. iOS interrupts camera capture on its
    /// own, but stopping the session explicitly also halts delegate/inference churn and
    /// gives a deterministic resume instead of relying on interruption recovery.
    /// Call on the main queue (ChironApp scene-phase handler).
    func handleAppBackgrounded() {
        wasAnalyzingOnBackground = isAnalyzingPose
        isAnalyzingPose = false
        sessionControlQueue.async { [weak self] in
            guard let self else { return }
            // Sampled on the control queue AFTER any pending pause/resume has drained,
            // so this is the settled state — not a snapshot that an in-flight
            // stopRunning is about to falsify.
            let running = self.captureSession?.isRunning == true
            self.resumeOnForeground = running
            if running {
                self.captureSession?.stopRunning()
            }
        }
    }

    /// Called when the app returns to the foreground; restores whatever camera/analysis
    /// state `handleAppBackgrounded` tore down, and nothing more. Call on the main queue.
    func handleAppForegrounded() {
        if wasAnalyzingOnBackground {
            isAnalyzingPose = true
        }
        wasAnalyzingOnBackground = false
        sessionControlQueue.async { [weak self] in
            guard let self, self.resumeOnForeground else { return }
            self.resumeOnForeground = false
            guard let session = self.captureSession, !session.isRunning else { return }
            session.startRunning()
        }
    }
}

// MARK: - Video Data Output Delegate
extension SharedCameraSessionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Forwards pixels to MediaPipe only when not in setup mode and `isAnalyzingPose` is true (`stopPoseAnalysis` vs `endTrackSetKeepingPoseActive`).
    ///
    /// Frames are decimated per `ThermalGovernor` policy before inference: full rate only
    /// during an active set on a cool device, ~12 fps while framing / resting / waiting,
    /// lower under thermal pressure or Low Power Mode. Rest periods dominate a workout's
    /// wall-clock time, and full-model inference was previously running through all of
    /// them — the single largest heat source in the app.
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isSetupMode && isAnalyzingPose else { return }

        // Cross-queue enum read of workoutState, codebase idiom (see OnDevicePoseManager).
        // `.waiting` with rep counting live is ALSO an active window: coached workouts
        // auto-start a set only after the first validated rep, and the bench validators
        // need several consecutive analyzed frames at the bottom/lockout — at idle rates
        // a touch-and-go rep may never validate, and the state would never escalate.
        // Track keeps suppressRepCounting=true between sets, so its rest/framing periods
        // still decimate.
        let workoutState = poseManager.workoutState
        let activeSet = trackExplicitSetActive
            || workoutState == .exercising
            || (workoutState == .waiting && !suppressRepCounting)
        let minInterval = ThermalGovernor.shared.minInferenceInterval(activeSet: activeSet)
        if minInterval > 0 {
            let now = CACurrentMediaTime()
            guard now - lastInferenceAt >= minInterval else { return }
            lastInferenceAt = now
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Analyze pose on device. Downstream form analysis publishes from
        // OnDevicePoseManager itself; the duplicate per-frame main-queue publish of
        // `currentFormAnalysis` that used to live here had no readers and cost a
        // main-thread wakeup + SwiftUI invalidation per frame.
        poseManager.analyzeFrame(pixelBuffer)
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

// MARK: - Pose overlay (2D skeleton)

/// Maps MediaPipe **normalized image** landmarks (top-left origin, x right, y down, \[0,1\]) into
/// full-screen SwiftUI coordinates for a **mirrored** front-camera preview in portrait.
///
/// The transform branches on whether `connection.videoRotationAngle = 90` actually rotated the buffer
/// before MediaPipe saw it. On iPhone 17/17 Pro/17 Max the rotation is a no-op and the buffer arrives
/// in native landscape, so we rotate the landmarks 90° (CCW) and mirror. On older iPhones the buffer is
/// pre-rotated to portrait, so we just mirror horizontally.
///
/// Used for the main pose skeleton overlay on the camera preview.
enum PoseOverlayCoordinateMapping {
    static func viewPoint(normalized p: CGPoint, canvasSize: CGSize, bufferIsPortrait: Bool = false) -> CGPoint {
        if bufferIsPortrait {
            return CGPoint(x: (1.0 - p.x) * canvasSize.width, y: p.y * canvasSize.height)
        }
        return CGPoint(x: (1.0 - p.y) * canvasSize.width, y: (1.0 - p.x) * canvasSize.height)
    }
}

/// Skeleton segments; joint names match `MediaPipePoseAdapter` overlay keys.
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

/// Displays the MediaPipe pose skeleton overlay when the user toggles it on via the stick figure button.
/// Shows real-time pose landmarks and skeleton edges from the pose detector.
struct PoseVisualizationOverlay: View {
    @ObservedObject private var poseManager = OnDevicePoseManager.shared

    var body: some View {
        GeometryReader { _ in
            ZStack {
                if let landmarks = poseManager.currentNormalizedLandmarks, !landmarks.isEmpty {
                    PoseLandmarkSkeletonView(landmarks: landmarks, bufferIsPortrait: poseManager.landmarkBufferIsPortrait)
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Renders `poseSkeletonEdges` and joint dots using `PoseOverlayCoordinateMapping` (Canvas uses `canvasSize`, not an external `GeometryReader` size).
struct PoseLandmarkSkeletonView: View {
    let landmarks: [String: CGPoint]
    let bufferIsPortrait: Bool

    var body: some View {
        Canvas { context, canvasSize in
            func viewPoint(_ p: CGPoint) -> CGPoint {
                PoseOverlayCoordinateMapping.viewPoint(normalized: p, canvasSize: canvasSize, bufferIsPortrait: bufferIsPortrait)
            }

            for (a, b) in poseSkeletonEdges {
                guard let pa = landmarks[a], let pb = landmarks[b] else { continue }
                var path = Path()
                path.move(to: viewPoint(pa))
                path.addLine(to: viewPoint(pb))
                context.stroke(path, with: .color(.green), lineWidth: 3)
            }

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

