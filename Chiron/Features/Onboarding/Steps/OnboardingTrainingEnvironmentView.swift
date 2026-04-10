import SwiftUI

// MARK: - Screen 08: Training Environment

struct OnboardingTrainingEnvironmentView: View, OnboardingScreen {
    let screenId = "screen_08"
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var selectedOption: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let options = ["Full gym", "Home gym", "Bodyweight only", "Mix of both"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer().frame(height: 24)

                Text("Where do you train?")
                    .font(.neueMontrealBold(size: 28))
                    .foregroundColor(Color.pureWhite)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)

                Text("This shapes the exercises we'll recommend and coach you on.")
                    .font(.neueMontrealRegular(size: 17))
                    .foregroundColor(Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)

                VStack(spacing: 12) {
                    ForEach(options, id: \.self) { option in
                        OnboardingOptionCard(
                            text: option,
                            isSelected: selectedOption == option,
                            isDimmed: selectedOption != nil && selectedOption != option,
                            action: {
                                guard selectedOption == nil else { return }
                                handleSelection(option)
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)

                Spacer()
            }
        }
        .accessibilityHint("Select your primary training environment. This determines which exercises the AI coach will focus on.")
    }

    private func handleSelection(_ option: String) {
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.12)) {
            selectedOption = option
        }

        coordinator.setTrainingEnvironment(option)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            coordinator.showAffirmationToast("Perfect setup.", forScreen: screenId)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            coordinator.completeScreen(screenId, answer: option)
        }
    }
}
