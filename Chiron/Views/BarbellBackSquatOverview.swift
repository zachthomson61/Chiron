import SwiftUI
import AVKit
import AVFoundation

struct BarbellBackSquatOverview: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCameraSetup = false
    @State private var showAlternativeSetup = false
    @State private var selectedTab = 0
    @State private var showActiveWorkout = false
    
    // Callback to navigate back to exercise selection
    var onFinishExercise: (() -> Void)?
    
    // Initialize with optional callback
    init(viewModel: WorkoutViewModel, onFinishExercise: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onFinishExercise = onFinishExercise
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        // Collapsing header that shrinks and fades as you scroll
                        let maxHeaderHeight = UIScreen.main.bounds.height * 0.7
                        GeometryReader { geo in
                            let offset = geo.frame(in: .named("scroll")).minY
                            let currentHeight = max(maxHeaderHeight - offset, 0)
                            let opacity = max(0, min(1, currentHeight / maxHeaderHeight))
                            
                            ZStack(alignment: .bottom) {
                                CroppedDemoVideoHeader(videoName: "BarbellBackSquat")
                                
                                // Gradient overlay for readability
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.0),
                                        Color.black.opacity(0.15),
                                        Color.black.opacity(0.35),
                                        Color.black.opacity(0.55)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: currentHeight)
                            .clipped()
                            .opacity(opacity)
                            .offset(y: offset < 0 ? -offset : 0)
                            .ignoresSafeArea(.container, edges: .top)
                        }
                        .frame(height: maxHeaderHeight)

                        // Scrollable menu content
                        VStack(alignment: .leading, spacing: 16) {
                            // Tab selector inside scroll
                            TabSelector(selectedTab: $selectedTab)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                            
                            Text("Barbell Back Squat")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                                .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 2)
                            
                            switch selectedTab {
                            case 0:
                                BarbellSetupContent()
                            case 1:
                                BarbellDosContent()
                            case 2:
                                BarbellDontsContent()
                            default:
                                BarbellSetupContent()
                            }
                            
                            Button(action: {
                                showCameraSetup = true
                                viewModel.startWorkout()
                            }) {
                                Text("Continue to Camera Setup")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(Color.primaryPurple)
                                    .cornerRadius(24)
                            }
                            .padding(.top, 16)
                        }
                        .padding(20)
                    }
                }
                .coordinateSpace(name: "scroll")

                // Floating back button in the top-left corner
                GeometryReader { geo in
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
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, geo.safeAreaInsets.top + 60) // Move below Dynamic Island
                        Spacer()
                    }
                }
                .ignoresSafeArea(.container, edges: .top)
                .allowsHitTesting(true)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showCameraSetup) {
            CameraSetupView()
        }
    }
}

struct BarbellSetupContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Master the basics: stable bar position, tight core, strong brace, controlled depth.")
                .font(.subheadline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                StepRow(number: 1, text: "Set the bar just below shoulder height. Grip slightly outside shoulder width; pull shoulder blades together.")
                StepRow(number: 2, text: "Duck under the bar and place it across your mid-traps (\"high bar\"). Elbows point down; wrists neutral.")
                StepRow(number: 3, text: "Unrack by standing tall. Take 1–2 small steps back. Set feet hip-to-shoulder width, toes slightly turned out.")
                StepRow(number: 4, text: "Brace your core (big breath into your belly and obliques). Keep your chest up and spine neutral.")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

struct BarbellDosContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key things to focus on during your squat:")
                .font(.subheadline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                DoDontRow(isDo: true, text: "Keep your chest up and maintain a neutral spine")
                DoDontRow(isDo: true, text: "Push your knees out in line with your toes")
                DoDontRow(isDo: true, text: "Sit back and down as if sitting into a chair")
                DoDontRow(isDo: true, text: "Keep your weight balanced through mid-foot and heels")
                DoDontRow(isDo: true, text: "Brace your core before every rep")
                DoDontRow(isDo: true, text: "Drive upward by pushing the floor away")
                DoDontRow(isDo: true, text: "Breathe steadily: inhale on the way down, exhale through the sticking point")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

struct BarbellDontsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Common mistakes to avoid:")
                .font(.subheadline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                DoDontRow(isDo: false, text: "Letting your knees cave inward")
                DoDontRow(isDo: false, text: "Rounding your lower back (loss of brace)")
                DoDontRow(isDo: false, text: "Letting your chest collapse under the bar")
                DoDontRow(isDo: false, text: "Lifting your heels off the ground")
                DoDontRow(isDo: false, text: "Going too fast or bouncing aggressively out of the bottom")
                DoDontRow(isDo: false, text: "Overarching your lower back at the top")
                DoDontRow(isDo: false, text: "Placing the bar too high on your neck")
                DoDontRow(isDo: false, text: "Taking large steps backward during the walkout")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

