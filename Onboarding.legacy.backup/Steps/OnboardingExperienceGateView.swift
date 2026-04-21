import SwiftUI

// MARK: - Screen 02: Experience Gate

struct OnboardingExperienceGateView: View, OnboardingScreen {
    let screenId = "screen_02"
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var selectedOption: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let options = ["Yes, I have", "I'm just starting"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer().frame(height: 24)

                Text("Have you trained with weights before?")
                    .font(.neueMontrealBold(size: 28))
                    .foregroundColor(Color.pureWhite)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)

                Text("No wrong answer. This helps us calibrate your starting point.")
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
        .accessibilityHint("Tell us about your weight training experience. Selecting 'I'm just starting' will simplify later questions.")
    }

    private func handleSelection(_ option: String) {
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.12)) {
            selectedOption = option
        }

        let isBeginner = option == "I'm just starting"
        coordinator.setExperienceGate(isBeginner: isBeginner)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            coordinator.showAffirmationToast("Got it.", forScreen: screenId)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            coordinator.completeScreen(screenId, answer: option)
        }
    }
}
