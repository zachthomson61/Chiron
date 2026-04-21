import SwiftUI

// MARK: - Screen 11: Motivation

struct OnboardingMotivationView: View, OnboardingScreen {
    let screenId = "screen_11"
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var selectedOption: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let options = [
        "It makes me feel capable",
        "I want to look my best",
        "It keeps my head clear",
        "I refuse to slow down",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer().frame(height: 24)

                Text("You train because...")
                    .font(.neueMontrealBold(size: 28))
                    .foregroundColor(Color.pureWhite)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)

                Text("Pick the one that resonates most. There's no ranking here.")
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
        .accessibilityHint("Select the statement that best describes why you train. This helps personalize your experience.")
    }

    private func handleSelection(_ option: String) {
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.12)) {
            selectedOption = option
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            coordinator.showAffirmationToast("That says a lot.", forScreen: screenId)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            coordinator.completeScreen(screenId, answer: option)
        }
    }
}
