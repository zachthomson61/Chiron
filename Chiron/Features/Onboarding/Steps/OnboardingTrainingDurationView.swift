import SwiftUI

// MARK: - Screen 07: Training Duration

struct OnboardingTrainingDurationView: View, OnboardingScreen {
    let screenId = "screen_07"
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var selectedOption: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let options = ["Less than 3 months", "3-12 months", "1-3 years", "3+ years"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer().frame(height: 24)

                Text("How long have you been training consistently?")
                    .font(.neueMontrealBold(size: 28))
                    .foregroundColor(Color.pureWhite)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)

                Text("Consistency means most weeks, not every single day.")
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
        .accessibilityHint("Select how long you have been training consistently. This helps build your personalized plan.")
    }

    private func handleSelection(_ option: String) {
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.12)) {
            selectedOption = option
        }

        coordinator.setTrainingDuration(option)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            coordinator.showAffirmationToast("Solid foundation.", forScreen: screenId)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            coordinator.completeScreen(screenId, answer: option)
        }
    }
}
