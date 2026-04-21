import SwiftUI

// MARK: - Screen 10: Squat Experience

struct OnboardingSquatExperienceView: View, OnboardingScreen {
    let screenId = "screen_10"
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var selectedExperience: SquatExperience?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct ExperienceOption: Identifiable {
        let id: String
        let experience: SquatExperience
        let label: String
        let helper: String
    }

    private let options: [ExperienceOption] = [
        ExperienceOption(
            id: "newToSquats",
            experience: .newToSquats,
            label: "New to squats",
            helper: "Never done structured squatting"
        ),
        ExperienceOption(
            id: "someExperience",
            experience: .someExperience,
            label: "Some experience",
            helper: "Squat occasionally, unsure of depth"
        ),
        ExperienceOption(
            id: "confident",
            experience: .confident,
            label: "Confident",
            helper: "Squat regularly, know my depth targets"
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer().frame(height: 24)

                Text("How would you describe your squat experience?")
                    .font(.neueMontrealBold(size: 28))
                    .foregroundColor(Color.pureWhite)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)

                Text("This fine-tunes how strictly the AI evaluates your reps.")
                    .font(.neueMontrealRegular(size: 17))
                    .foregroundColor(Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)

                VStack(spacing: 12) {
                    ForEach(options) { option in
                        OnboardingOptionCardWithHelper(
                            text: option.label,
                            helper: option.helper,
                            isSelected: selectedExperience == option.experience,
                            isDimmed: selectedExperience != nil && selectedExperience != option.experience,
                            action: {
                                guard selectedExperience == nil else { return }
                                handleSelection(option.experience)
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)

                Spacer()
            }
        }
        .accessibilityHint("Select your squat experience level. This adjusts how the AI counts your reps and evaluates depth.")
    }

    private func handleSelection(_ experience: SquatExperience) {
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.12)) {
            selectedExperience = experience
        }

        coordinator.setSquatExperience(experience)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            coordinator.showAffirmationToast("Dialed in.", forScreen: screenId)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            coordinator.completeScreen(screenId, answer: experience.rawValue)
        }
    }
}
