//
//  CoachPersonaStepView.swift
//  Chiron
//
//  Step 8 — coach persona. Four cards, each with a short descriptor.
//

import SwiftUI

struct CoachPersonaStepView: View {
    @Bindable var coordinator: ChironOnboardingCoordinator

    var body: some View {
        OnboardingScreenScaffold(
            title: "How would you describe your ideal coach?",
            subtitle: "This sets the tone your coach uses during sets. You can switch later in settings.",
            ctaTitle: "Continue",
            ctaEnabled: coordinator.canAdvance,
            currentStep: coordinator.progressStepIndex,
            totalSteps: coordinator.totalProgressSteps,
            onContinue: { coordinator.advance() },
            onBack: { coordinator.goBack() }
        ) {
            VStack(spacing: 10) {
                ForEach(CoachPersona.allCases) { persona in
                    OnboardingOptionRow(
                        title: persona.displayName,
                        descriptor: persona.descriptor,
                        isSelected: coordinator.draft.coachPersona == persona
                    ) {
                        coordinator.draft.coachPersona = persona
                    }
                }
            }
        }
    }
}

#Preview {
    CoachPersonaStepView(coordinator: ChironOnboardingCoordinator(store: InMemoryUserProfileStore()))
}
