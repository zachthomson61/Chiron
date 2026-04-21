//
//  CoachInterstitialView.swift
//  Chiron
//
//  Storytelling interstitial before the coach-persona question. No options —
//  just narrative momentum and a single Continue CTA (Opal pattern).
//

import SwiftUI

struct CoachInterstitialView: View {
    @Bindable var coordinator: ChironOnboardingCoordinator

    @State private var animateIn = false

    var body: some View {
        OnboardingScreenScaffold(
            ctaTitle: "Continue",
            ctaEnabled: true,
            currentStep: coordinator.progressStepIndex,
            totalSteps: coordinator.totalProgressSteps,
            onContinue: { coordinator.advance() },
            onBack: { coordinator.goBack() },
            hideTopBar: false
        ) {
            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: 40)

                Text("Every coach sounds different.")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 12)

                Text("The wrong one and you'll mute the app by rep 3.")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(OnboardingTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 12)

                Text("Let's pick yours.")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.accentGradient)
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 12)

                Spacer()
            }
            .padding(.top, 40)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55).delay(0.1)) {
                animateIn = true
            }
        }
    }
}

#Preview {
    CoachInterstitialView(coordinator: ChironOnboardingCoordinator(store: InMemoryUserProfileStore()))
}
