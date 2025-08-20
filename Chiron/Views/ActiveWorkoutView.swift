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

// MARK: - Active Workout Camera Manager (Legacy - keeping for compatibility)
class ActiveWorkoutCameraManager: NSObject, ObservableObject {
    static let shared = ActiveWorkoutCameraManager()
    
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    
    // Pose analysis components
    let poseManager = OnDevicePoseManager.shared
    private let coachingManager = OpenAICoachingManager.shared
    
    @Published var isAnalyzingPose = false
    @Published var currentFormAnalysis: FormAnalysis?
    @Published var coachingFeedback: String = ""
    
    private override init() {
        super.init()
    }
    
    func receiveSession(_ session: AVCaptureSession, videoOutput: AVCaptureVideoDataOutput) {
        print("📹 ActiveWorkout: Receiving camera session from setup")
        
        // Store the transferred session
        self.captureSession = session
        self.videoDataOutput = videoOutput
        
        // Don't create a new preview layer - the existing one from setup view should continue working
        // Just ensure our video output delegate is set for pose analysis
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "activeWorkoutVideoQueue"))
        
        // Ensure the session continues running
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
        
        print("📹 ActiveWorkout: Camera session transfer completed")
    }
    
    private func setupCamera() {
        // Only setup camera if we don't already have a session
        guard captureSession == nil else { return }
        
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else { return }
        
        captureSession.sessionPreset = .high
        
        // Try to get front camera, fallback to back camera if needed
        var camera: AVCaptureDevice?
        
        // First try front camera
        if let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            camera = frontCamera
            print("📹 Using front camera")
        } else if let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            camera = backCamera
            print("📹 Front camera not available, using back camera")
        } else {
            print("❌ No camera available")
            return
        }
        
        guard let selectedCamera = camera else {
            print("❌ Failed to get camera device")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: selectedCamera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                print("📹 Camera input added successfully")
            } else {
                print("❌ Failed to add camera input")
                return
            }
        } catch {
            print("❌ Error setting up camera input: \(error)")
            return
        }
        
        // Setup video data output for pose analysis
        videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "activeWorkoutVideoQueue"))
        if let videoDataOutput = videoDataOutput, captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            print("📹 Video data output added successfully")
        } else {
            print("❌ Failed to add video data output")
            return
        }
        
        // Setup preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
        print("📹 Camera setup completed successfully")
    }
    
    func startCamera() {
        // If we don't have a session yet, setup a new one
        if captureSession == nil {
            setupCamera()
        }
        
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            if granted {
                DispatchQueue.global(qos: .userInitiated).async {
                    self?.captureSession?.startRunning()
                }
            } else {
                print("Camera permission denied")
            }
        }
    }
    
    func stopCamera() {
        print("📹 ActiveWorkoutCameraManager: Stopping camera")
        captureSession?.stopRunning()
        
        // Also stop pose analysis when camera stops
        stopPoseAnalysis()
        
        // Clear any cached form analysis
        DispatchQueue.main.async {
            self.currentFormAnalysis = nil
        }
    }
    
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        return previewLayer
    }
    
    func startPoseAnalysis() {
        isAnalyzingPose = true
        print("🎯 ActiveWorkout: Starting pose analysis")
        
        // Reset rep count for new set
        poseManager.resetRepCount()
        
        // Only start camera if it's not already running (e.g., from setup view transfer)
        if let session = captureSession, !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        } else if captureSession?.isRunning == true {
            print("📹 ActiveWorkout: Camera already running from setup view")
        }
    }
    
    func stopPoseAnalysis() {
        isAnalyzingPose = false
        print("🛑 ActiveWorkout: Stopping pose analysis")
        
        // Clear current form analysis
        DispatchQueue.main.async {
            self.currentFormAnalysis = nil
        }
        
        // Reset pose manager state
        poseManager.resetRepCount()
    }
    
    func getCoachingFeedback(completion: @escaping (String) -> Void) {
        guard let formAnalysis = currentFormAnalysis else {
            completion("No pose detected. Please ensure you are visible in the camera frame.")
            return
        }
        
        coachingManager.analyzeAndGetFeedback(formAnalysis: formAnalysis, isDetailed: false) { feedback in
            DispatchQueue.main.async {
                self.coachingFeedback = feedback
                completion(feedback)
            }
        }
    }
    
    func getDetailedCoachingFeedback(completion: @escaping (String) -> Void) {
        guard let formAnalysis = currentFormAnalysis else {
            completion("No pose detected. Please ensure you are visible in the camera frame.")
            return
        }
        
        coachingManager.analyzeAndGetFeedback(formAnalysis: formAnalysis, isDetailed: true) { feedback in
            DispatchQueue.main.async {
                self.coachingFeedback = feedback
                completion(feedback)
            }
        }
    }
    
    func getCurrentFormSummary() -> String {
        return currentFormAnalysis?.summary ?? "No pose detected"
    }
    
    func getCurrentFormScore() -> Float {
        return currentFormAnalysis?.overallScore ?? 0.0
    }
}

// MARK: - Video Data Output Delegate
extension ActiveWorkoutCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    // Static property for frame counting (moved to type level)
    private static var frameCount = 0
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Only analyze pose if pose analysis is active
        guard isAnalyzingPose else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Analyze pose on device
        poseManager.analyzeFrame(pixelBuffer)
        
        // Update form analysis
        DispatchQueue.main.async {
            self.currentFormAnalysis = self.poseManager.currentFormAnalysis
        }
        
        // Debug logging for pose detection (reduced frequency)
        if poseManager.poseDetected {
            // Only log every 100 frames to reduce console spam
            Self.frameCount += 1
            if Self.frameCount % 100 == 0 {
                print("🎯 ActiveWorkout: Pose detected - Form score: \(poseManager.currentFormAnalysis?.overallScore ?? 0.0)")
            }
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
                    VStack {
                        Text("\(currentRepCount)")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.textPrimary)
                        Text("reps")
                            .font(.caption)
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
                

                
                Spacer()
                

                
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
    
    private func startRepCountTimer() {
        // Update rep count every 0.5 seconds
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            currentRepCount = SharedCameraSessionManager.shared.poseManager.getCurrentRepCount()
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
        
        // Check if any reps were completed
        let totalReps = SharedCameraSessionManager.shared.poseManager.getCurrentRepCount()
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
