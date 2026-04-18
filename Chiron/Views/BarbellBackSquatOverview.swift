import SwiftUI
import AVKit
import AVFoundation

/// Overview screen for Barbell Back Squat exercise.
/// Displays video demonstration, setup instructions, dos, and don'ts.
/// Matches the style and structure of BodyweightSquatOverview.
struct BarbellBackSquatOverview: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showCameraSetup = false
    @State private var selectedTab = 0
    
    /// Optional callback to navigate back to exercise selection
    var onFinishExercise: (() -> Void)?
    
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

                // Top-left dismiss chevron. Matches the ExerciseHistorySheet's
                // close affordance (40×40 circle, semitransparent black,
                // `chevron.down` glyph) so sheet-dismiss iconography is
                // consistent across the app. GeometryReader keeps it clear
                // of the Dynamic Island while the video header still bleeds
                // into the top safe area.
                GeometryReader { geo in
                    VStack {
                        HStack {
                            Button(action: { dismiss() }) {
                                Image(systemName: "chevron.down")
                                    .font(.headline.weight(.semibold))
                                    .foregroundColor(.textPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Color.black.opacity(0.35))
                                    .clipShape(Circle())
                            }
                            .accessibilityLabel("Dismiss")
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, geo.safeAreaInsets.top + 12)
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
            CameraSetupView(exerciseType: .barbellBackSquat, viewModel: viewModel)
        }
    }
}

// MARK: - Content Views

/// Setup instructions for barbell back squat (Tab 0)
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

/// Dos (best practices) for barbell back squat (Tab 1)
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

/// Don'ts (common mistakes) for barbell back squat (Tab 2)
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

