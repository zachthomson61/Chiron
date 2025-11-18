import SwiftUI
import AVFoundation

// MARK: - Shared Camera Session Manager
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
        
        // Ensure squat type is bodyweight for analysis defaults
        poseManager.squatType = .bodyweight
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

struct ActiveWorkoutView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSetComplete = false
    @State private var showSpeechControl = false
    @State private var isReadingAnalysis = false
    @State private var currentRepCount = 0
    @State private var updateTimer: Timer?
    @State private var shouldDismissToExerciseSelection = false
    @State private var showPoseVisualization = false
    @State private var restTimeRemaining: TimeInterval = 0
    @State private var restTimer: Timer?
    // Completed set summaries (rep counts per set)
    @State private var completedSetReps: [Int] = []
    @State private var totalRepsAtLastSetEnd: Int = 0
    
    // Callback to navigate back to exercise selection
    var onFinishExercise: (() -> Void)?
    
    // Initialize with automatic set detection
    init(viewModel: WorkoutViewModel, onFinishExercise: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onFinishExercise = onFinishExercise
    }
    
    var body: some View {
        ZStack {
            // Camera view fills entire screen
            ActiveWorkoutCameraView()
                .ignoresSafeArea()
            
            // Pose Visualization Overlay (for testing)
            if showPoseVisualization {
                PoseVisualizationOverlay()
                    .allowsHitTesting(false) // Don't block touch events
            }
            
            // UI overlay on top of camera
            VStack {
                // Navigation Header
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.textPrimary)
                    }
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                    Spacer()
                    
                    // Completed Sets Display (to the left of rep counter)
                    if !completedSetReps.isEmpty {
                        HStack(spacing: 12) {
                            ForEach(Array(completedSetReps.enumerated()), id: \.offset) { idx, reps in
                                VStack(spacing: 4) {
                                    Text("\(reps)")
                                        .font(.system(size: 42, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    Text("Set \(idx + 1)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [Color.green.opacity(0.6), Color.green.opacity(0.4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(
                                            LinearGradient(
                                                colors: [Color.green, Color.green.opacity(0.7)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2
                                        )
                                )
                                .cornerRadius(20)
                                .scaleEffect(idx == completedSetReps.count - 1 ? 1.05 : 1.0) // Slightly larger for most recent set
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: completedSetReps.count)
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                        .shadow(color: .green.opacity(0.3), radius: 8, x: 0, y: 4)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    
                    // Large Rep Counter in Header
                    VStack(spacing: 8) {
                        Text("\(currentRepCount)")
                            .font(.system(size: 140, weight: .bold, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                        Text("Reps")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.textSecondary)
                    }
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                    
                    Spacer()
                    // Invisible button for balance
                    Button("") { }
                        .opacity(0)
                }
                .padding()
                Spacer()
                
                // Rest Timer Clock Overlay (Center of Screen)
                if OnDevicePoseManager.shared.workoutState == .resting {
                    RestTimerClockView(restTimeRemaining: restTimeRemaining)
                        .transition(.opacity.combined(with: .scale))
                }
                
                Spacer()
                
                // Bottom Controls
                HStack(spacing: 40) {
                    Button(action: {
                        showSpeechControl = true
                    }) {
                        Image(systemName: SpeechManager.shared.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                            .font(.title2)
                            .foregroundColor(SpeechManager.shared.isSpeaking ? .green : .gray)
                    }
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                    
                    // Pose Visualization Toggle (for testing)
                    Button(action: {
                        showPoseVisualization.toggle()
                    }) {
                        Image(systemName: showPoseVisualization ? "eye.fill" : "eye")
                            .font(.title2)
                            .foregroundColor(showPoseVisualization ? .green : .gray)
                    }
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                    
                    // Automatic Status Display
                    VStack(spacing: 4) {
                        Text(getWorkoutStatusText())
                            .font(OnDevicePoseManager.shared.workoutState == .waiting ? .subheadline : .headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        if OnDevicePoseManager.shared.workoutState == .resting {
                            Text("Rest: \(formatRestTime())")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(width: 140, height: 48)
                    .background(getWorkoutStatusColor())
                    .cornerRadius(24)
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                    
                    Button(action: {
                        // TODO: Reset current set
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                }
                .padding(.bottom, 20)
                
                // Finish Exercise Button
                Button(action: {
                    finishExercise()
                }) {
                    Text("Finish Exercise")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.orange)
                        .cornerRadius(24)
                }
                .shadow(color: .black, radius: 2, x: 1, y: 1)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Start automatic pose analysis
            print("🎯 Starting automatic pose analysis")
            // Clear any previous workout data
            completedSetReps = []
            totalRepsAtLastSetEnd = 0
            currentRepCount = 0
            setInProgress = false
            lastRepCountSeen = 0
            SharedCameraSessionManager.shared.switchToWorkoutMode()
            SharedCameraSessionManager.shared.startPoseAnalysis()
            
            // Start rep count timer
            startRepCountTimer()
        }
        .onDisappear {
            // Stop pose analysis when leaving workout
            if SharedCameraSessionManager.shared.isAnalyzingPose {
                SharedCameraSessionManager.shared.stopPoseAnalysis()
            }
            // Stop timer
            stopRepCountTimer()
            stopRestTimer()
            
            // Switch back to setup mode but keep camera running
            SharedCameraSessionManager.shared.switchToSetupMode()
        }
        .sheet(isPresented: $showSpeechControl) {
            SpeechControlView()
        }
    }
    
    // MARK: - Helper Functions
    
    private func getWorkoutStatusText() -> String {
        let poseManager = OnDevicePoseManager.shared
        
        switch poseManager.workoutState {
        case .waiting:
            return "Ready"  // More subtle message
        case .exercising:
            return "Set \(poseManager.currentSet)\nRep \(poseManager.repCount)"
        case .resting:
            return "Set complete!\nRest for \(formatRestTime())"
        case .finished:
            return "Workout complete!"
        }
    }
    
    private func getWorkoutStatusColor() -> Color {
        let poseManager = OnDevicePoseManager.shared
        
        switch poseManager.workoutState {
        case .waiting:
            return Color.primaryPurple.opacity(0.6)  // More subtle color
        case .exercising:
            return Color.green
        case .resting:
            return Color.orange
        case .finished:
            return Color.gray
        }
    }
    
    private func formatRestTime() -> String {
        let remaining = max(0, Int(restTimeRemaining))
        return "\(remaining)s"
    }
    
    private func startRestTimer() {
        restTimeRemaining = 60.0 // 60 seconds rest period
        
        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if restTimeRemaining > 0 {
                restTimeRemaining -= 1.0
            } else {
                timer.invalidate()
                restTimer = nil
            }
        }
    }
    
    private func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
        restTimeRemaining = 0
    }
    
    // End-of-set detection state
    @State private var setInProgress: Bool = false
    @State private var lastRepCountSeen: Int = 0
    @State private var lastActivityTime: TimeInterval = Date().timeIntervalSince1970
    @State private var feedbackCooldownUntil: TimeInterval = 0
    private let inactivityThresholdSeconds: TimeInterval = 5.0
    private let feedbackCooldownSeconds: TimeInterval = 6.0

    private func startRepCountTimer() {
        // Update rep count every 0.5 seconds and monitor inactivity
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            _ = OnDevicePoseManager.shared
            let now = Date().timeIntervalSince1970

            // Current rep count (now resets between sets)
            let reps = SharedCameraSessionManager.shared.poseManager.getCurrentRepCount()
            currentRepCount = reps

            // Activity based only on rep changes
            if reps != lastRepCountSeen {
                print("🔄 Rep count changed: \(lastRepCountSeen) -> \(reps)")
                lastRepCountSeen = reps
                lastActivityTime = now
                if reps > 0 { setInProgress = true }
            }

            // Detect end of set via inactivity
            if setInProgress,
               now - lastActivityTime >= inactivityThresholdSeconds,
               reps > 0,
               now >= feedbackCooldownUntil {
                print("🏁 End-of-set detected. Inactivity: \(now - lastActivityTime)s, reps: \(reps)")
                setInProgress = false
                feedbackCooldownUntil = now + feedbackCooldownSeconds
                handleEndOfSetFeedback()
            }

        }
    }

    private func handleEndOfSetFeedback() {
        print("🗣️ Triggering end-of-set feedback")
        // Append set summary bubble and start rest timer
        // Use the current rep count as the completed reps for this set
        if currentRepCount > 0 {
            completedSetReps.append(currentRepCount)
            totalRepsAtLastSetEnd = currentRepCount
        }
        
        // Reset rep counter to 0 for next set
        currentRepCount = 0
        lastRepCountSeen = 0
        
        // Reset the pose manager's rep count state
        OnDevicePoseManager.shared.resetRepCount()
        
        startRestTimer()
        // Get latest form analysis snapshot (if available)
        if let analysis = OnDevicePoseManager.shared.currentFormAnalysis {
            print("📝 Using current form analysis for unified natural feedback")
            // Single, natural message (no interruptions). Speaking handled inside manager.
            OpenAICoachingManager.shared.analyzeAndGetNaturalFeedback(formAnalysis: analysis) { feedback in
                print("🗣️ Unified feedback spoken: \(feedback)")
            }
        } else {
            // Fallback if no analysis available - single natural sentence
            let fallback = "Nice control there, but let's aim for a little more depth next set."
            print("🗣️ Speaking fallback unified feedback: \(fallback)")
            SpeechManager.shared.speakCoachingFeedback(fallback)
        }
    }
    
    private func stopRepCountTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private func finishExercise() {
        print("🏁 Finishing exercise - checking for completed reps")
        isReadingAnalysis = true
        viewModel.currentFeedback = ""
        
        // Stop pose analysis and camera
        if SharedCameraSessionManager.shared.isAnalyzingPose {
            SharedCameraSessionManager.shared.stopPoseAnalysis()
        }
        SharedCameraSessionManager.shared.stopCamera()
        
        // Check if any reps were completed (sum of all completed sets)
        let totalReps = completedSetReps.reduce(0, +) + currentRepCount
        print("🏁 Total reps completed: \(totalReps)")
        
        if totalReps == 0 {
            print("🏁 No reps completed - navigating immediately without summary")
            DispatchQueue.main.async {
                self.isReadingAnalysis = false
                // Navigate back immediately if no reps were completed
                onFinishExercise?()
            }
        } else {
            print("🏁 Reps completed - getting detailed analysis")
            // Get detailed coaching feedback for end of workout (API-generated only)
            // Note: We need to implement this method in SharedCameraSessionManager
            // For now, just navigate back
            DispatchQueue.main.async {
                self.isReadingAnalysis = false
                onFinishExercise?()
            }
        }

    }
}

