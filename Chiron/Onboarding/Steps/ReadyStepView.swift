//
//  ReadyStepView.swift
//  Chiron
//
//  Step 13 — final summary. Clean card stack showing selected lifts, coach persona,
//  and intensity. Primary CTA "Start My First Session" persists the profile and fires
//  `onFinish`.
//

import SwiftUI

struct ReadyStepView: View {
    @Bindable var coordinator: ChironOnboardingCoordinator

    @State private var appeared = false

    var body: some View {
        OnboardingScreenScaffold(
            ctaTitle: "Start My First Session",
            ctaEnabled: true,
            currentStep: coordinator.progressStepIndex,
            totalSteps: coordinator.totalProgressSteps,
            onContinue: { coordinator.finish() },
            onBack: nil,
            hideTopBar: false
        ) {
            VStack(alignment: .leading, spacing: 24) {
                header

                liftsCard

                coachCard

                intensityCard
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(.easeOut(duration: 0.5).delay(0.05), value: appeared)
        }
        .onAppear { appeared = true }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOU'RE READY")
                .font(.system(size: 12, weight: .bold))
                .tracking(3)
                .foregroundStyle(OnboardingTheme.accentGradient)

            Text("Here's what we locked in.")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(OnboardingTheme.textPrimary)
        }
    }

    // MARK: - Cards

    private var liftsCard: some View {
        summaryCard(title: "Tracked lifts") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(sortedLifts, id: \.storageKey) { lift in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(OnboardingTheme.accentGradient)
                        Text(lift.displayName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(OnboardingTheme.textPrimary)
                    }
                }
            }
        }
    }

    private var coachCard: some View {
        summaryCard(title: "Your coach") {
            VStack(alignment: .leading, spacing: 6) {
                Text(coordinator.draft.coachPersona?.displayName ?? "—")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.textPrimary)

                if let descriptor = coordinator.draft.coachPersona?.descriptor {
                    Text(descriptor)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(OnboardingTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var intensityCard: some View {
        summaryCard(title: "Intensity") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { rung in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                rung <= coordinator.draft.coachIntensity
                                ? AnyShapeStyle(OnboardingTheme.accentGradient)
                                : AnyShapeStyle(OnboardingTheme.stroke)
                            )
                            .frame(height: 8)
                    }
                }

                Text(CoachIntensityLevel.from(clamped: coordinator.draft.coachIntensity).label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.textSecondary)
            }
        }
    }

    // MARK: - Card scaffold

    @ViewBuilder
    private func summaryCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(OnboardingTheme.textSecondary)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OnboardingTheme.cornerRadiusLarge, style: .continuous)
                .fill(OnboardingTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OnboardingTheme.cornerRadiusLarge, style: .continuous)
                .strokeBorder(OnboardingTheme.stroke, lineWidth: 1)
        )
    }

    private var sortedLifts: [TrackedExerciseType] {
        coordinator.draft.trackedExercises.sorted { $0.displayName < $1.displayName }
    }
}

#Preview {
    let coordinator: ChironOnboardingCoordinator = {
        let c = ChironOnboardingCoordinator(store: InMemoryUserProfileStore())
        c.draft.topGoal = .getStronger
        c.draft.experienceLevel = .someExperience
        c.draft.gender = .male
        c.draft.birthYear = 1995
        c.draft.heightCm = 178
        c.draft.weightKg = 80
        c.draft.hasInjuryConcerns = true
        c.draft.injuryFlags = [.knee]
        c.draft.coachPersona = .technician
        c.draft.coachIntensity = 4
        return c
    }()
    ReadyStepView(coordinator: coordinator)
}
