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
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.textPrimary)
                    }
                    .shadow(color: .black, radius: 2, x: 1, y: 1)
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
                    InstructionCard()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

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
        // Ensure shared session exists
        SharedCameraSessionManager.shared.setupCameraSession()
        SharedCameraSessionManager.shared.switchToSetupMode()
        // Start running the session if needed so the preview is live
        if let session = SharedCameraSessionManager.shared.getCaptureSession(), !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
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
        if let session = SharedCameraSessionManager.shared.getCaptureSession() {
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            // Mirror for front camera UI only; analysis buffers are unmirrored in manager
            layer.connection?.automaticallyAdjustsVideoMirroring = false
            layer.connection?.isVideoMirrored = true
            previewLayer = layer
            self.layer.addSublayer(layer)
            layer.frame = bounds
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
                Text("Attempt to Place Your Camera")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "1.circle.fill").foregroundColor(.primaryPurple)
                Text("Stand side-on to the camera")
                    .foregroundColor(.white)
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "2.circle.fill").foregroundColor(.primaryPurple)
                Text("Center yourself in frame")
                    .foregroundColor(.white)
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "3.circle.fill").foregroundColor(.primaryPurple)
                Text("At Chest to Head Height")
                    .foregroundColor(.white)
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "4.circle.fill").foregroundColor(.primaryPurple)
                Text("With Feet in View")
                    .foregroundColor(.white)
            }
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


