import SwiftUI

// MARK: - Screen 01: Identity Hook

struct OnboardingIdentityHookView: View, OnboardingScreen {
    let screenId = "screen_01"
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var selectedOption: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let options = ["That's me", "Tell me more"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer().frame(height: 24)

                Text("You want more from your training")
                    .font(.neueMontrealBold(size: 28))
                    .foregroundColor(Color.pureWhite)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)

                Text("Most people work out. Few people train with intention. You opened this app because you know the difference.")
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
        .accessibilityHint("Choose which statement best describes you. Both options continue to the next screen.")
    }

    private func handleSelection(_ option: String) {
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.12)) {
            selectedOption = option
        }

        // Haptic feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        // Affirmation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            coordinator.showAffirmationToast("Thought so.", forScreen: screenId)
        }

        // Auto-advance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            coordinator.completeScreen(screenId, answer: option)
        }
    }
}
