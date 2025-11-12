import SwiftUI
import AVFoundation

struct HomeScreenSpacing {
    static let topInset: CGFloat = 12
    static let topTitlePad: CGFloat = 8
    static let sectionSpacing: CGFloat = 20
    static let bottomInset: CGFloat = 28
}

struct HomeView: View {
    @StateObject private var viewModel = WorkoutViewModel()
    @StateObject private var preferencesManager = UserPreferencesManager.shared
    @State private var showGoalSelector = false
    @State private var showExerciseSelection = false
    @State private var showFeedback = false
    @State private var contentHeight: CGFloat = 0
    @State private var pulseGoal = false
    
    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let h = proxy.size.height
                
                ScrollView {
                    VStack(spacing: HomeScreenSpacing.sectionSpacing) {
                        // HEADER
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Chiron")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.textPrimary)
                            
                            // My Goal subtitle - tappable
                            Button(action: {
                                showGoalSelector = true
                            }) {
                                HStack(spacing: 4) {
                                    Text("My Goal:")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.textSecondary)
                                    
                                    Text(preferencesManager.primaryGoal?.displayName ?? "Choose one")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(preferencesManager.primaryGoal != nil ? .textPrimary : .primaryPurple)
                                    
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.textSecondary)
                                        .opacity(0.6)
                                }
                                .scaleEffect(pulseGoal ? 1.05 : 1.0)
                                .animation(
                                    pulseGoal ? Animation.easeInOut(duration: 0.6).repeatCount(2, autoreverses: true) : nil,
                                    value: pulseGoal
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .accessibilityLabel("My Goal. Currently \(preferencesManager.primaryGoal?.displayName ?? "not set"). Double tap to change")
                            
                            // Show hint on first run
                            if preferencesManager.primaryGoal == nil && !UserDefaults.standard.bool(forKey: "has_shown_goal_hint") {
                                Text("Tap to set your goal")
                                    .font(.caption)
                                    .foregroundColor(.primaryPurple)
                                    .opacity(0.8)
                                    .onAppear {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            pulseGoal = true
                                        }
                                        AnalyticsManager.shared.trackFirstRunGoalPrompt()
                                    }
                            }
                        }
                        .padding(.top, HomeScreenSpacing.topTitlePad)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // CORE
                        VStack(spacing: HomeScreenSpacing.sectionSpacing) {
                            // Play Button
                            Button(action: {
                                showExerciseSelection = true
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.primaryPurple)
                                        .frame(width: 80, height: 80)
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundColor(.textPrimary)
                                }
                            }

                            // Ready to train section
                            VStack(spacing: 8) {
                                Text("Ready to train?")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.textPrimary)
                                Text("Let's work on your squat form")
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                            }

                            // Primary action button - Start Workout
                            // Note: "Build Workout Plan" button moved to Plans tab
                            Button(action: {
                                showExerciseSelection = true
                            }) {
                                Text("Start Workout")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 56)
                                    .background(Color.primaryPurple)
                                    .cornerRadius(28)
                            }
                        }

                        // FLEX SPACER (shrinks/grows to balance)
                        Spacer()
                            .frame(height: max(0, min(40, h - contentHeight)))
                            .fixedSize()

                    }
                    .padding(.horizontal, 20)
                    .background(
                        ViewHeightReader(height: $contentHeight)
                    )
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .scrollDisabled(contentHeight <= h)
                .background(Color.background)
            }
            .safeAreaInset(edge: .top) { 
                Color.clear.frame(height: HomeScreenSpacing.topInset) 
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: {
                        showFeedback = true
                    }) {
                        Image(systemName: "text.bubble")
                            .font(.title2)
                            .foregroundColor(.textSecondary)
                    }
                    
                    Button(action: {
                        // TODO: Navigate to settings
                    }) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .preferredColorScheme(.dark)
            .fullScreenCover(isPresented: $showExerciseSelection) {
                ExerciseSelectionView(viewModel: viewModel)
            }
            .sheet(isPresented: $showGoalSelector) {
                GoalSelectorView(preferencesManager: preferencesManager, isPresented: $showGoalSelector)
            }
            .sheet(isPresented: $showFeedback) {
                FeedbackView(viewModel: viewModel)
            }
        }
    }
}


// Helper to measure the VStack height
struct ViewHeightReader: View {
    @Binding var height: CGFloat
    var body: some View {
        GeometryReader { gp in
            Color.clear
                .preference(key: HeightKey.self, value: gp.size.height)
        }
        .onPreferenceChange(HeightKey.self) { height = $0 }
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
