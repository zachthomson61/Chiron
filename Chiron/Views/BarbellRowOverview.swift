//
//  BarbellRowOverview.swift
//  Chiron
//
//  Exercise library detail view for Barbell Row exercise.
//  Displays video demonstration, setup instructions, dos, and don'ts.
//  Matches the style and structure of BodyweightSquatOverview.
//

import SwiftUI
import AVKit
import AVFoundation

/// Overview screen for Barbell Row exercise.
///
/// Displays a collapsing video header, tabbed content (Setup, Dos, Don'ts), and navigation
/// to camera setup. Matches the visual style and structure of `BodyweightSquatOverview`.
struct BarbellRowOverview: View {
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
                                CroppedDemoVideoHeader(videoName: "BarbellRow")
                                
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
                            
                            Text("Barbell Row")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                                .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 2)
                            
                            switch selectedTab {
                            case 0:
                                BarbellRowSetupContent()
                            case 1:
                                BarbellRowDosContent()
                            case 2:
                                BarbellRowDontsContent()
                            default:
                                BarbellRowSetupContent()
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
                .ignoresSafeArea(.container, edges: .top)

                // Top-left back chevron. Sits naturally in the top safe area,
                // below the Dynamic Island, while the video extends behind it.
                VStack {
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.textPrimary)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.35))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Back")
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    Spacer()
                }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showCameraSetup) {
            CameraSetupView(exerciseType: .barbellRow, viewModel: viewModel)
        }
    }
}

// MARK: - Content Views

/// Setup instructions for barbell row.
/// Displays 4-step setup process with form cues.
struct BarbellRowSetupContent: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Master the basics: strong hinge, neutral spine, tight lats.")
                .font(.subheadline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                StepRow(number: 1, text: "Stand with feet hip-width. Grip the bar slightly wider than shoulder width.")
                StepRow(number: 2, text: "Hinge at the hips until your torso is roughly 30–45 degrees from the floor. Keep your knees softly bent.")
                StepRow(number: 3, text: "Pull your shoulder blades down and back. Brace your core and keep your spine neutral.")
                StepRow(number: 4, text: "Let the bar hang directly under your shoulders with straight arms.")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

/// Best practices (dos) for barbell row.
/// Lists key form points to focus on during the row.
struct BarbellRowDosContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key things to focus on during your row:")
                .font(.subheadline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                DoDontRow(isDo: true, text: "Keep your spine neutral throughout the set")
                DoDontRow(isDo: true, text: "Maintain your hip hinge; don't stand up as you row")
                DoDontRow(isDo: true, text: "Pull your elbows back toward your hips, not straight out")
                DoDontRow(isDo: true, text: "Keep the bar close to your torso")
                DoDontRow(isDo: true, text: "Squeeze your shoulder blades at the top")
                DoDontRow(isDo: true, text: "Control the bar all the way down")
                DoDontRow(isDo: true, text: "Keep your core braced to prevent torso sway")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

/// Common mistakes (don'ts) to avoid for barbell row.
/// Lists form errors and safety concerns to prevent.
struct BarbellRowDontsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Common mistakes to avoid:")
                .font(.subheadline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                DoDontRow(isDo: false, text: "Rounding your lower back")
                DoDontRow(isDo: false, text: "Overarching your lower back at the top")
                DoDontRow(isDo: false, text: "Jerking or using momentum to move the bar")
                DoDontRow(isDo: false, text: "Letting your torso rise as the reps get harder")
                DoDontRow(isDo: false, text: "Pulling with your arms only instead of engaging your back")
                DoDontRow(isDo: false, text: "Letting the bar drift away from your body")
                DoDontRow(isDo: false, text: "Shrugging your shoulders upward")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

