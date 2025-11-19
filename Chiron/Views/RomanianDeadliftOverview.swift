//
//  RomanianDeadliftOverview.swift
//  Chiron
//
//  Exercise library detail view for Romanian Deadlift (RDL) exercise.
//  Displays video demonstration, setup instructions, dos, and don'ts.
//  Matches the style and structure of BodyweightSquatOverview.
//

import SwiftUI
import AVKit
import AVFoundation

/// Overview screen for Romanian Deadlift (RDL) exercise.
/// 
/// Displays a collapsing video header with exercise demonstration, followed by
/// three tabs: Setup (4-step setup process), Dos (7 best practices), and Don'ts (7 common mistakes).
/// Uses shared components from BodyweightSquatOverview (TabSelector, StepRow, DoDontRow, CroppedDemoVideoHeader).
struct RomanianDeadliftOverview: View {
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
                                CroppedDemoVideoHeader(videoName: "RomanianDeadlift")
                                
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
                            
                            Text("Romanian Deadlift (RDL)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                                .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 2)
                            
                            switch selectedTab {
                            case 0:
                                RomanianDeadliftSetupContent()
                            case 1:
                                RomanianDeadliftDosContent()
                            case 2:
                                RomanianDeadliftDontsContent()
                            default:
                                RomanianDeadliftSetupContent()
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

// MARK: - Content Views

/// Setup instructions for Romanian Deadlift exercise (Tab 0: Setup).
/// Displays the four-step setup process with proper form cues.
struct RomanianDeadliftSetupContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Master the basics: strong hip hinge, controlled descent, neutral spine.")
                .font(.subheadline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                StepRow(number: 1, text: "Stand tall with feet hip-width and the bar in your hands. Grip just outside your legs.")
                StepRow(number: 2, text: "Pull your shoulder blades down and back. Keep the bar close to your body.")
                StepRow(number: 3, text: "Create a soft knee bend (about 15–20 degrees). Brace your core.")
                StepRow(number: 4, text: "Hinge at your hips by pushing them backward while keeping your back flat.")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

/// Best practices (dos) for Romanian Deadlift exercise (Tab 1: Dos).
/// Lists key form points to focus on during the lift.
struct RomanianDeadliftDosContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key things to focus on during your lift:")
                .font(.subheadline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                DoDontRow(isDo: true, text: "Keep your spine neutral from start to finish")
                DoDontRow(isDo: true, text: "Push your hips back instead of squatting down")
                DoDontRow(isDo: true, text: "Keep the bar close to your legs during the entire movement")
                DoDontRow(isDo: true, text: "Maintain a slight bend in the knees")
                DoDontRow(isDo: true, text: "Stop your descent when your hamstrings hit their stretch limit")
                DoDontRow(isDo: true, text: "Drive your hips forward to stand tall")
                DoDontRow(isDo: true, text: "Reset your brace each rep")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

/// Common mistakes (don'ts) to avoid for Romanian Deadlift exercise (Tab 2: Don'ts).
/// Lists form errors and safety concerns to prevent.
struct RomanianDeadliftDontsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Common mistakes to avoid:")
                .font(.subheadline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                DoDontRow(isDo: false, text: "Rounding your lower back")
                DoDontRow(isDo: false, text: "Overarching your lower back at the top")
                DoDontRow(isDo: false, text: "Letting the bar drift away from your body")
                DoDontRow(isDo: false, text: "Turning it into a squat (knees bending too much)")
                DoDontRow(isDo: false, text: "Locking out your knees rigidly")
                DoDontRow(isDo: false, text: "Rushing the eccentric (downward phase)")
                DoDontRow(isDo: false, text: "Going lower than your mobility allows")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}