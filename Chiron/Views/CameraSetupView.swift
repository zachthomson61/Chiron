import SwiftUI
import AVFoundation

struct CameraSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var workoutActive: Bool = false
    @State private var currentRepCount: Int = 0
    @State private var repUpdateTimer: Timer?
    @State private var showExerciseSelection: Bool = false

    var body: some View {
        ZStack {
            // Live camera preview (shared session)
            SetupCameraPreviewRepresentable()
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    Spacer()

                    if workoutActive {
                        VStack(spacing: 0) {
                            Text("\(currentRepCount)")
                                .font(.largeTitle).fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                            Text("reps")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        .shadow(color: .black, radius: 2, x: 1, y: 1)
                    }

                    // Spacer to balance layout
                    Spacer().frame(width: 1)
                }
                .padding()

                Spacer()

                if !workoutActive {
                    Spacer()
                    
                    InstructionCard()
                        .padding(.horizontal, 20)
                    
                    Spacer()

                    Button(action: startWorkout) {
                        Text("Start Bodyweight Squat")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(width: 280, height: 48)
                            .background(Color.primaryPurple)
                            .cornerRadius(24)
                    }
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
                    .padding(.bottom, 40)
                } else {
                    // Bottom Finish button in workout mode
                    Button(action: finishWorkout) {
                        Text("Finish Bodyweight Squat")
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
        }
        .preferredColorScheme(.dark)
        .onAppear { setupCameraForSetupMode() }
        .onDisappear { stopRepCounterTimer() }
        .fullScreenCover(isPresented: $showExerciseSelection) {
            ExerciseSelectionView(viewModel: WorkoutViewModel())
        }
    }

    private func setupCameraForSetupMode() {
        // Ensure shared session exists and is properly configured
        SharedCameraSessionManager.shared.setupCameraSession()
        SharedCameraSessionManager.shared.switchToSetupMode()
        
        // Start running the session if needed so the preview is live
        if let session = SharedCameraSessionManager.shared.getCaptureSession() {
            if !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async {
                    session.startRunning()
                }
            }
        }
    }

    private func startWorkout() {
        SharedCameraSessionManager.shared.switchToWorkoutMode()
        SharedCameraSessionManager.shared.startPoseAnalysis()
        startRepCounterTimer()
        withAnimation(.easeInOut(duration: 0.25)) { workoutActive = true }
    }

    private func finishWorkout() {
        stopRepCounterTimer()
        if SharedCameraSessionManager.shared.isAnalyzingPose {
            SharedCameraSessionManager.shared.stopPoseAnalysis()
        }
        // Keep camera session alive but return to setup mode
        SharedCameraSessionManager.shared.switchToSetupMode()
        showExerciseSelection = true
    }

    private func startRepCounterTimer() {
        stopRepCounterTimer()
        repUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            currentRepCount = SharedCameraSessionManager.shared.poseManager.getCurrentRepCount()
        }
    }

    private func stopRepCounterTimer() {
        repUpdateTimer?.invalidate()
        repUpdateTimer = nil
    }
}

// MARK: - Camera Preview (Setup)
struct SetupCameraPreviewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> SetupCameraPreviewView {
        SetupCameraPreviewView()
    }
    func updateUIView(_ uiView: SetupCameraPreviewView, context: Context) {}
}

final class SetupCameraPreviewView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Wait a bit for the shared manager to be ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.setupPreviewLayer()
        }
    }
    
    private func setupPreviewLayer() {
        guard let session = SharedCameraSessionManager.shared.getCaptureSession() else {
            // Retry if session isn't ready yet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
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
}

// MARK: - Instruction Card
private struct InstructionCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.title3)
                    .foregroundColor(.primaryPurple)
                Text("Attempt to Place Your Phone:")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "ruler").foregroundColor(.primaryPurple)
                    Text("6-8' Away")
                        .foregroundColor(.white)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "angle").foregroundColor(.primaryPurple)
                    Text("45° to Your Body")
                        .foregroundColor(.white)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "person.fill").foregroundColor(.primaryPurple)
                    Text("At Waist to Chest Height")
                        .foregroundColor(.white)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "figure.walk").foregroundColor(.primaryPurple)
                    Text("With Feet in View")
                        .foregroundColor(.white)
                }
            }
            .padding(.leading, 20)
        }
        .padding(16)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.35)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.primaryPurple.opacity(0.5), Color.white.opacity(0.2)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ), lineWidth: 1
                )
        )
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 12)
        .opacity(0.9)
    }
}


