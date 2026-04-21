import SwiftUI

// MARK: - Screen 06: Goal Overflow (Remaining 3)

struct OnboardingGoalOverflowView: View, OnboardingScreen {
    let screenId = "screen_06"
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var selectedGoal: PrimaryGoal?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Remaining 3 goals.
    private let goals: [(PrimaryGoal, String)] = [
        (.enhanceAthleticPerformance, "Enhance athletic performance"),
        (.improveHealthLongevity, "Improve health & longevity"),
        (.rehabPreventInjury, "Rehabilitate or prevent injury"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer().frame(height: 24)

                Text("What's driving you right now?")
                    .font(.neueMontrealBold(size: 28))
                    .foregroundColor(Color.pureWhite)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)

                Text("Or is it one of these?")
                    .font(.neueMontrealRegular(size: 17))
                    .foregroundColor(Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)

                VStack(spacing: 12) {
                    ForEach(goals, id: \.0) { goal, label in
                        OnboardingOptionCard(
                            text: label,
                            isSelected: selectedGoal == goal,
                            isDimmed: selectedGoal != nil && selectedGoal != goal,
                            action: {
                                guard selectedGoal == nil else { return }
                                handleSelection(goal)
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)

                Spacer()
            }
        }
        .accessibilityHint("Additional goal options. Select one if the previous screen did not have your goal.")
    }

    private func handleSelection(_ goal: PrimaryGoal) {
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.12)) {
            selectedGoal = goal
        }

        coordinator.setPrimaryGoal(goal, fromScreen5: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            coordinator.showAffirmationToast("That helps us calibrate.", forScreen: screenId)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            coordinator.completeScreen(screenId, answer: goal.rawValue)
        }
    }
}
