//
//  HelpImproveChironPrimerView.swift
//  Chiron
//
//  Privacy-consent gate for the developer-facing telemetry pipeline (per-frame
//  CSV + screen-recording mp4 → R2). Sits just before NotificationPrimerView.
//
//  Tapping the primary CTA opts the user in; "Not now" opts out. Either choice
//  advances the flow. The choice is persisted to `TelemetryPreferencesManager`
//  so the rest of the app's consent gate (TelemetryCoordinator.isEnabled)
//  honors it without any further plumbing. Users can revoke or grant consent
//  later via the "Help Improve Chiron" toggle in `SettingsView`.
//

import SwiftUI

struct HelpImproveChironPrimerView: View {
    @Bindable var coordinator: ChironOnboardingCoordinator

    var body: some View {
        OnboardingScreenScaffold(
            ctaTitle: "Help improve Chiron",
            ctaEnabled: true,
            currentStep: coordinator.progressStepIndex,
            totalSteps: coordinator.totalProgressSteps,
            onContinue: { optInAndAdvance() },
            onBack: { coordinator.goBack() }
        ) {
            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 20)

                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.accentGradient)

                OnboardingTypography.questionTitle("Make Chiron sharper.")

                OnboardingTypography.subtitle(
                    "Share anonymous form data and short clips of your sets so we can keep tuning the coaching. Optional. Change your mind any time."
                )
                .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 14) {
                    bullet(
                        icon: "figure.strengthtraining.traditional",
                        title: "Per-rep form data",
                        detail: "Joint angles, rep timing, and form scores. Used only to fix coaching edge cases."
                    )
                    bullet(
                        icon: "video.fill",
                        title: "Short clips of your sets",
                        detail: "Screen recordings of the analyzed view. What the camera saw, nothing more."
                    )
                    bullet(
                        icon: "lock.shield.fill",
                        title: "No name, no email",
                        detail: "Tied to an opaque device handle. Never sold, never used for ads."
                    )
                }
                .padding(.top, 4)

                Spacer()

                Button("Not now") { optOutAndAdvance() }
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

    private func optInAndAdvance() {
        TelemetryPreferencesManager.shared.shareDataToImproveChiron = true
        coordinator.advance()
    }

    private func optOutAndAdvance() {
        TelemetryPreferencesManager.shared.shareDataToImproveChiron = false
        coordinator.advance()
    }
}

#Preview {
    HelpImproveChironPrimerView(coordinator: ChironOnboardingCoordinator(store: InMemoryUserProfileStore()))
}
