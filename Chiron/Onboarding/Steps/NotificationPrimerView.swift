//
//  NotificationPrimerView.swift
//  Chiron
//
//  Step 12 — custom primer explaining *why* we want notifications, then the
//  system prompt. Declining the system prompt still advances the flow (Cal AI pattern).
//

import SwiftUI
import UserNotifications

struct NotificationPrimerView: View {
    @Bindable var coordinator: ChironOnboardingCoordinator

    @State private var requesting = false

    var body: some View {
        OnboardingScreenScaffold(
            ctaTitle: requesting ? "Requesting…" : "Enable notifications",
            ctaEnabled: !requesting,
            currentStep: coordinator.progressStepIndex,
            totalSteps: coordinator.totalProgressSteps,
            onContinue: { requestPermission() },
            onBack: { coordinator.goBack() }
        ) {
            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 20)

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.accentGradient)

                OnboardingTypography.questionTitle("Stay in the pocket.")

                OnboardingTypography.subtitle(
                    "We'll send you rest-timer pings between sets and the occasional nudge when you skip a session. No marketing. Ever."
                )
                .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 14) {
                    bullet(icon: "timer", title: "Rest-timer pings", detail: "So you don't have to watch the clock between sets.")
                    bullet(icon: "calendar", title: "Session reminders", detail: "Only when you've set a training schedule — not a drip campaign.")
                    bullet(icon: "nosign", title: "Never marketing", detail: "We don't run growth loops through your lock screen.")
                }
                .padding(.top, 4)

                Spacer()

                Button("Not now") { coordinator.advance() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(OnboardingTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 8)
            }
        }
    }

    private func bullet(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(OnboardingTheme.surface)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.accentGradient)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(OnboardingTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func requestPermission() {
        guard !requesting else { return }
        requesting = true

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            // Always advance — we've already shown the primer. The system prompt outcome
            // is a nice-to-have; blocking the flow on it creates a dead-end for users
            // who decline.
            DispatchQueue.main.async {
                requesting = false
                coordinator.advance()
            }
        }
    }
}

#Preview {
    NotificationPrimerView(coordinator: ChironOnboardingCoordinator(store: InMemoryUserProfileStore()))
}
