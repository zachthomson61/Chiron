//
//  DeadliftOverview.swift
//  Chiron
//
//  Exercise library detail view for Deadlift exercise.
//  Displays video demonstration, setup instructions, dos, and don'ts.
//  Matches the style and structure of BodyweightSquatOverview.
//

import SwiftUI
import AVKit
import AVFoundation

/// Overview screen for Deadlift exercise.
/// Displays video demonstration, setup instructions, dos, and don'ts.
struct DeadliftOverview: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    /// Optional callback to navigate back to exercise selection
    var onFinishExercise: (() -> Void)?
    /// When true, a History button appears at the bottom of the overview. Only set
    /// by the Research-tab Exercise Library router.
    var showHistoryButton: Bool = false

    init(viewModel: WorkoutViewModel, onFinishExercise: (() -> Void)? = nil, showHistoryButton: Bool = false) {
        self.viewModel = viewModel
        self.onFinishExercise = onFinishExercise
        self.showHistoryButton = showHistoryButton
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
                                CroppedDemoVideoHeader(videoName: "Deadlift")
                                
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
                            
                            Text("Deadlift")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                                .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 2)
                            
                            switch selectedTab {
                            case 0:
                                DeadliftSetupContent()
                            case 1:
                                DeadliftDosContent()
                            case 2:
                                DeadliftDontsContent()
                            default:
                                DeadliftSetupContent()
                            }

                            if showHistoryButton {
                                ExerciseHistoryFooterButton(
                                    exerciseName: "Deadlift"
                                )
                                .padding(.top, 8)
                            }
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
    }
}

// MARK: - Content Views

/// Setup instructions for deadlift exercise (Tab 0: Setup).
/// Displays the four-step setup process with proper form cues.
struct DeadliftSetupContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Master the basics: strong hinge, neutral spine, full-foot balance, controlled bar path.")
                .font(.subheadline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                StepRow(number: 1, text: "Stand with feet hip-width. Bar should be over mid-foot (about 1 inch from shins).")
                StepRow(number: 2, text: "Hinge at the hips and reach down. Grip the bar just outside your legs. Keep shins mostly vertical.")
                StepRow(number: 3, text: "Pull your chest up, flatten your back, and tighten your lats (imagine squeezing oranges in your armpits).")
                StepRow(number: 4, text: "Brace your core, push the floor away, and stand tall. Keep the bar close to your body the entire time.")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

/// Best practices (dos) for deadlift exercise (Tab 1: Dos).
/// Lists key form points to focus on during the lift.
struct DeadliftDosContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key things to focus on during your lift:")
                .font(.subheadline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                DoDontRow(isDo: true, text: "Keep your spine neutral from start to finish")
                DoDontRow(isDo: true, text: "Push the floor away rather than \"yanking\" the bar")
                DoDontRow(isDo: true, text: "Keep the bar close to your shins and thighs")
                DoDontRow(isDo: true, text: "Engage your lats to keep the bar path straight")
                DoDontRow(isDo: true, text: "Drive through mid-foot and heels")
                DoDontRow(isDo: true, text: "Stand tall at the top without leaning back")
                DoDontRow(isDo: true, text: "Reset your brace before every rep")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

/// Common mistakes (don'ts) to avoid for deadlift exercise (Tab 2: Don'ts).
/// Lists form errors and safety concerns to prevent.
struct DeadliftDontsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Common mistakes to avoid:")
                .font(.subheadline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                DoDontRow(isDo: false, text: "Rounding your lower back")
                DoDontRow(isDo: false, text: "Overarching your lower back at the top")
                DoDontRow(isDo: false, text: "Letting the bar drift away from your body")
                DoDontRow(isDo: false, text: "Bending your arms while pulling")
                DoDontRow(isDo: false, text: "Shooting your hips up faster than your chest")
                DoDontRow(isDo: false, text: "Jerking the bar off the floor")
                DoDontRow(isDo: false, text: "Hyperextending (\"leaning back\") at lockout")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

