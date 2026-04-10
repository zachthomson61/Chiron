import SwiftUI

// MARK: - Screen 16: Completion

struct OnboardingCompletionView: View, OnboardingScreen {
    let screenId = "screen_16"
    @ObservedObject var coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .center, spacing: 24) {
                    Spacer().frame(height: 40)

                    Text("You train with intention now")
                        .font(.neueMontrealBold(size: 28))
                        .foregroundColor(Color.pureWhite)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    Text("You're the type of person who shows up, pays attention to form, and refuses to settle for reps that don't count. Your coach is ready when you are.")
                        .font(.neueMontrealRegular(size: 17))
                        .foregroundColor(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Spacer()
                }
            }

            OnboardingCTAButton(title: "Start training") {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                coordinator.completeOnboarding()
            }
            .padding(.bottom, 16)
        }
        .accessibilityHint("Onboarding is complete. Your personalized AI coaching plan is ready. Tap 'Start training' to begin your first workout.")
    }
}
