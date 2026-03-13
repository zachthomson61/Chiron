import SwiftUI

struct HomeScreenSpacing {
    static let topInset: CGFloat = 12
    static let topTitlePad: CGFloat = 24
    static let headerStackSpacing: CGFloat = 18
    static let sectionSpacing: CGFloat = 28
    static let bottomInset: CGFloat = 28
}

/// Landing surface for the Home tab.
///
/// When users tap "Start Workout" (either the play button or the primary button),
/// they are presented with a workout selection menu via sheet modal.
///
/// **Note:** The `onStartWorkout` callback parameter is currently unused but retained
/// for potential future use or external integrations.
struct HomeView: View {
    var onStartWorkout: (() -> Void)? = nil
    @StateObject private var preferencesManager = UserPreferencesManager.shared
    @State private var showGoalSelector = false
    @State private var showWorkoutSelection = false
    @State private var contentHeight: CGFloat = 0
    @State private var pulseGoal = false
    @State private var homeSelectedPlan: TrainingPlan? = nil
    @EnvironmentObject private var planStore: PlanStore
    /// Drives the header animation so we can animate shadow and offset without
    /// triggering extra layout changes.
    @State private var animateTitle = false
    
    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let h = proxy.size.height
                let goalDisplayName = preferencesManager.primaryGoal?.displayName ?? "Choose one"
                
                ScrollView {
                    VStack(spacing: HomeScreenSpacing.sectionSpacing) {
                        // HEADER
                        VStack(alignment: .leading, spacing: HomeScreenSpacing.headerStackSpacing) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("LET'S GET IT!")
                                    .font(.neueMontrealBold(size: 38))
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .fixedSize()
                                    .padding(.trailing, 24)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .shadow(color: Color.primaryPurple.opacity(animateTitle ? 0.65 : 0.3),
                                            radius: animateTitle ? 26 : 10,
                                            y: animateTitle ? 6 : 0)
                                    .rotationEffect(.degrees(animateTitle ? 1.75 : -1.75))
                                    .offset(x: animateTitle ? 3 : -3)
                                    .scaleEffect(animateTitle ? 1.03 : 1.0)
                                    .allowsTightening(true)
                                    .animation(
                                        Animation.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                                        value: animateTitle
                                    )
                            }

                            MyGoalCard(
                                goalName: goalDisplayName,
                                pulse: pulseGoal,
                                onTap: { showGoalSelector = true }
                            )
                        }
                        .padding(.top, HomeScreenSpacing.topTitlePad)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onAppear(perform: startTitleAnimationIfNeeded)
                        .onDisappear(perform: resetTitleAnimation)

                        // CORE
                        VStack(spacing: HomeScreenSpacing.sectionSpacing) {
                            // Ready to train section
                            VStack(spacing: 8) {
                                Text("Ready to train?")
                                    .font(.neueMontrealBold(size: 22))
                                    .foregroundColor(.textPrimary)
                            }

                            // Primary action button - Start Workout
                            // Note: "Build Workout Plan" button moved to Plans tab
                            Button(action: handleStartWorkout) {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                        .font(.neueMontrealSemiBold(size: 17))
                                    Text("Start Workout")
                                        .font(.neueMontrealSemiBold(size: 17))
                                }
                                .foregroundColor(.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.primaryPurple)
                                .cornerRadius(28)
                            }
                        }

                        myWorkoutPlanSection

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
            .preferredColorScheme(.dark)
            .navigationDestination(isPresented: Binding(
                get: { homeSelectedPlan != nil },
                set: { if !$0 { homeSelectedPlan = nil } }
            )) {
                if let plan = homeSelectedPlan {
                    PlanPreviewView(plan: plan, source: .savedList)
                }
            }
            .sheet(isPresented: $showWorkoutSelection) {
                WorkoutSelectionView()
            }
            .sheet(isPresented: $showGoalSelector) {
                GoalSelectorView(preferencesManager: preferencesManager, isPresented: $showGoalSelector)
            }
        }
    }
}

private extension HomeView {
    /// Handles "Start Workout" action from both the play button and primary button.
    ///
    /// Presents the workout selection menu as a sheet modal. Both buttons
    /// (the circular play button and the "Start Workout" button) call this
    /// function to ensure consistent behavior.
    func handleStartWorkout() {
        showWorkoutSelection = true
    }
    
    func startTitleAnimationIfNeeded() {
        guard !animateTitle else { return }
        animateTitle = true
    }
    
    func resetTitleAnimation() {
        animateTitle = false
    }

    /// Shows the pinned training plan with a lightweight active badge and a progress slider.
    private var myWorkoutPlanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Workout Plan")
                .font(.neueMontrealBold(size: 20))
                .foregroundColor(.textPrimary)

            if let plan = planStore.lastSelectedPlan {
                let planGoalsText = plan.goals.map { $0.rawValue }.joined(separator: ", ")
                Button(action: {
                    homeSelectedPlan = plan
                }) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(plan.name)
                                    .font(.neueMontrealBold(size: 22))
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)

                                if !planGoalsText.isEmpty {
                                    Text(planGoalsText)
                                        .font(.neueMontrealRegular(size: 15))
                                        .foregroundColor(.planTextSecondary)
                                        .lineLimit(2)
                                }
                            }

                            Spacer()

                            Text("Active")
                                .font(.neueMontrealBold(size: 11))
                                .foregroundColor(.primaryPurple)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.primaryPurple.opacity(0.15))
                                .clipShape(Capsule())
                        }

                        HStack(spacing: 6) {
                            Text("\(plan.duration) weeks")
                            Text("•")
                            Text("\(plan.daysPerWeek) days/week")
                        }
                        .font(.neueMontrealRegular(size: 12))
                        .foregroundColor(.planTextSecondary)

                        if let progressValue = planProgress(for: plan) {
                            ProgressView(value: progressValue)
                                .progressViewStyle(LinearProgressViewStyle(tint: Color.secondaryPurple))
                                .frame(height: 6)
                                .padding(.vertical, 2)
                                .background(Color.secondaryPurple.opacity(0.15))
                                .cornerRadius(3)

                            Text("\(Int(progressValue * 100))% complete")
                                .font(.neueMontrealRegular(size: 11))
                                .foregroundColor(.planTextSecondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.planCardBackground)
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.primaryPurple.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No plan pinned yet")
                        .font(.neueMontrealBold(size: 17))
                        .foregroundColor(.textPrimary)
                    Text("Select a plan on the Plans tab and it will be shown here for quick access.")
                        .font(.neueMontrealRegular(size: 15))
                        .foregroundColor(.planTextSecondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.planCardBackground)
                .cornerRadius(16)
            }
        }
        .padding(.top, 4)
    }

    /// Estimates completion by comparing wall time since creation with the target duration.
    private func planProgress(for plan: TrainingPlan) -> Double? {
        guard plan.duration > 0 else { return nil }
        let totalSeconds = Double(plan.duration) * 7 * 24 * 60 * 60
        guard totalSeconds > 0 else { return nil }
        let elapsed = min(max(Date().timeIntervalSince(plan.createdAt), 0), totalSeconds)
        return min(max(elapsed / totalSeconds, 0), 1)
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

private struct MyGoalCard: View {
    let goalName: String
    let pulse: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                Text("My Goal")
                    .font(.neueMontrealSemiBold(size: 24))
                    .foregroundColor(.white.opacity(0.6))
                
                HStack(alignment: .top, spacing: 10) {
                    Text(goalName)
                        .font(.neueMontrealBold(size: 40))
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "square.and.pencil")
                        .font(.neueMontrealBold(size: 22))
                        .foregroundColor(.textPrimary.opacity(0.9))
                }
                
                Text("This is why you're here. Every rep gets you closer 🚀")
                    .font(.neueMontrealRegular(size: 16))
                    .foregroundColor(.textPrimary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 26)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.primaryPurple.opacity(0.85),
                                Color.secondaryPurple.opacity(0.65),
                                Color.primaryPurple.opacity(0.6)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: Color.secondaryPurple.opacity(0.45), radius: 28, y: 14)
            // Base shadow provides the glow; avoid extra blur layers to keep render fast.
        }
        .buttonStyle(.plain)
        .scaleEffect(pulse ? 1.03 : 1.0)
        .animation(
            pulse ? Animation.easeInOut(duration: 0.6).repeatCount(2, autoreverses: true) : nil,
            value: pulse
        )
        .accessibilityLabel("My Goal. Currently \(goalName). Double tap to change")
    }
}



