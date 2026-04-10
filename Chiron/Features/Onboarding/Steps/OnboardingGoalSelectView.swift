import SwiftUI

// MARK: - Screen 05: Goal Select (Top 5)

struct OnboardingGoalSelectView: View, OnboardingScreen {
    let screenId = "screen_05"
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var selectedGoal: PrimaryGoal?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Top 5 goals shown on this screen.
    private let goals: [(PrimaryGoal, String)] = [
        (.loseFat, "Lose fat"),
        (.getToned, "Get toned"),
        (.buildMuscle, "Build muscle"),
        (.getStronger, "Get stronger"),
        (.improveEndurance, "Improve endurance"),
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

                Text("Pick the goal that feels most urgent. You can always adjust later.")
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

                // Social proof element
                Text("83,000 people improved their squat form in their first week")
                    .font(.neueMontrealRegular(size: 13))
                    .foregroundColor(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                Spacer()
            }
        }
        .accessibilityHint("Choose your primary fitness goal. This determines how the AI coach calibrates your workouts. If none of these match, the next screen has more options.")
    }

    private func handleSelection(_ goal: PrimaryGoal) {
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.12)) {
            selectedGoal = goal
        }

        coordinator.setPrimaryGoal(goal, fromScreen5: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            coordinator.showAffirmationToast("Strong choice.", forScreen: screenId)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            coordinator.completeScreen(screenId, answer: goal.rawValue)
        }
    }
}
