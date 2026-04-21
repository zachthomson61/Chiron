//
//  MovementLimitationStepView.swift
//  Chiron
//
//  Step 6c — severity of the flagged issue. Drives how aggressively the coaching
//  layer will cue the user and whether certain movements get suppressed entirely.
//

import SwiftUI

struct MovementLimitationStepView: View {
    @Bindable var coordinator: ChironOnboardingCoordinator

    var body: some View {
        OnboardingScreenScaffold(
            title: "How much does this affect movement?",
            subtitle: "Be honest — we'd rather dial back than hurt you.",
            ctaTitle: "Continue",
            ctaEnabled: coordinator.draft.movementLimitation != nil,
            currentStep: coordinator.progressStepIndex,
            totalSteps: coordinator.totalProgressSteps,
            onContinue: { coordinator.advance() },
            onBack: { coordinator.goBack() }
        ) {
            VStack(spacing: 10) {
                ForEach(MovementLimitation.allCases) { level in
                    OnboardingOptionRow(
                        title: level.displayName,
                        descriptor: level.detail,
                        isSelected: coordinator.draft.movementLimitation == level
                    ) {
                        coordinator.draft.movementLimitation = level
                    }
                }
            }
        }
    }
}

#Preview {
    let coordinator: ChironOnboardingCoordinator = {
        let c = ChironOnboardingCoordinator(store: InMemoryUserProfileStore())
        c.draft.hasInjuryConcerns = true
        c.draft.injuryFlags = [.knee]
        return c
    }()
    MovementLimitationStepView(coordinator: coordinator)
}
