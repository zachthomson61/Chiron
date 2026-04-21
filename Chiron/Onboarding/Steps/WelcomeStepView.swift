//
//  WelcomeStepView.swift
//  Chiron
//
//  Step 1 — brand moment. Centered wordmark, hero subtitle, single CTA "Get Started."
//

import SwiftUI

struct WelcomeStepView: View {
    @Bindable var coordinator: ChironOnboardingCoordinator
    @State private var animateIn = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        OnboardingScreenScaffold(
            ctaTitle: "Get Started",
            ctaEnabled: true,
            currentStep: 0,
            totalSteps: coordinator.totalProgressSteps,
            onContinue: { coordinator.advance() },
            onBack: { clearDataAndDismiss() },
            hideTopBar: true
        ) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 60)

                HStack(spacing: 12) {
                    ChironMark()
                    Text("CHIRON")
                        .font(.system(size: 14, weight: .bold, design: .default))
                        .tracking(4)
                        .foregroundStyle(OnboardingTheme.textSecondary)
                }
                .padding(.bottom, 48)

                Text("Bad form is\nwasting your time.")
                    .font(.system(size: 40, weight: .semibold))
                    .lineSpacing(4)
                    .foregroundStyle(OnboardingTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: animateIn ? 0 : 16)

                Spacer(minLength: 24)

                Text("Real-time form coaching built by strength coaches and physical therapists help you achieve your goals faster")
                    .font(.system(size: 16, weight: .regular))
                    .lineSpacing(4)
                    .foregroundStyle(OnboardingTheme.textSecondary)
                    .opacity(animateIn ? 1 : 0)

                Spacer(minLength: 80)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) {
                animateIn = true
            }
        }
    }

    private func clearDataAndDismiss() {
        UserDefaults.standard.removeObject(forKey: "chiron.onboarding_completed.v1")
        UserDefaults.standard.removeObject(forKey: "chiron.user_profile.v1")
        dismiss()
    }
}

/// Simple gradient-stroked chevron mark used on the welcome screen.
private struct ChironMark: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(OnboardingTheme.accentGradient, lineWidth: 2)
                .frame(width: 28, height: 28)

            Image(systemName: "chevron.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(OnboardingTheme.accentGradient)
        }
    }
}

#Preview {
    WelcomeStepView(coordinator: ChironOnboardingCoordinator(store: InMemoryUserProfileStore()))
}
