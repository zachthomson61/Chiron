//
//  BarbellBenchPressOverview.swift
//  Chiron
//
//  Exercise library detail view for Barbell Bench Press exercise.
//  Displays video demonstration, setup instructions, dos, and don'ts.
//  Matches the style and structure of BodyweightSquatOverview.
//

import SwiftUI
import AVKit
import AVFoundation

/// Overview screen for Barbell Bench Press exercise.
/// 
/// Displays a collapsing video header and tabbed content (Setup, Dos, Don'ts).
/// Matches the visual style and structure of `BodyweightSquatOverview`.
struct BarbellBenchPressOverview: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    /// When true, a History button appears at the bottom of the overview. Only set
    /// by the Research-tab Exercise Library router.
    var showHistoryButton: Bool = false

    init(viewModel: WorkoutViewModel, showHistoryButton: Bool = false) {
        self.viewModel = viewModel
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
                                CroppedDemoVideoHeader(videoName: "BarbellBenchPress")
                                
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
                            
                            Text("Barbell Bench Press")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                                .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 2)
                            
                            switch selectedTab {
                            case 0:
                                BarbellBenchPressSetupContent()
                            case 1:
                                BarbellBenchPressDosContent()
                            case 2:
                                BarbellBenchPressDontsContent()
                            default:
                                BarbellBenchPressSetupContent()
                            }

                            if showHistoryButton {
                                ExerciseHistoryFooterButton(
                                    exerciseName: "Barbell Bench Press"
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

/// Setup instructions for barbell bench press.
/// Displays 4-step setup process with form cues.
struct BarbellBenchPressSetupContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Master the basics: stable shoulder position, tight upper back, controlled bar path.")
                .font(.subheadline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                StepRow(number: 1, text: "Lie on the bench with eyes directly under the bar. Plant your feet firmly on the floor.")
                StepRow(number: 2, text: "Grip the bar slightly wider than shoulder width. Keep wrists stacked over your elbows.")
                StepRow(number: 3, text: "Pinch your shoulder blades together and slightly down to create a strong upper-back base.")
                StepRow(number: 4, text: "Unrack the bar by straightening your arms. Bring the bar over your mid-chest before lowering.")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

/// Best practices (dos) for barbell bench press.
/// Lists key form points to focus on during the press.
struct BarbellBenchPressDosContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key things to focus on during your press:")
                .font(.subheadline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                DoDontRow(isDo: true, text: "Keep your shoulder blades pulled back the entire time")
                DoDontRow(isDo: true, text: "Maintain a slight arch in your upper back (natural lifting position)")
                DoDontRow(isDo: true, text: "Lower the bar under control to your mid-chest")
                DoDontRow(isDo: true, text: "Keep your elbows at ~45–60 degrees from your body")
                DoDontRow(isDo: true, text: "Press the bar up and slightly back toward the rack")
                DoDontRow(isDo: true, text: "Keep your feet planted and maintain full-body tension")
                DoDontRow(isDo: true, text: "Keep your wrists neutral, not bent backward")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

/// Common mistakes (don'ts) to avoid for barbell bench press.
/// Lists form errors and safety concerns to prevent.
struct BarbellBenchPressDontsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Common mistakes to avoid:")
                .font(.subheadline)
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 12) {
                DoDontRow(isDo: false, text: "Flaring your elbows too wide")
                DoDontRow(isDo: false, text: "Letting your shoulders roll forward off the bench")
                DoDontRow(isDo: false, text: "Bouncing the bar off your chest")
                DoDontRow(isDo: false, text: "Letting your wrists collapse backward")
                DoDontRow(isDo: false, text: "Stopping short of full range")
                DoDontRow(isDo: false, text: "Lifting your feet or hips off the bench")
                DoDontRow(isDo: false, text: "Lowering the bar too high toward your neck")
                DoDontRow(isDo: false, text: "Rushing your reps without control")
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
    }
}

