//
//  GenderStepView.swift
//  Chiron
//
//  Step 4 — gender identity. Asked before age because the answer picks which
//  anatomical figure is shown on the injury-location page downstream.
//

import SwiftUI

struct GenderStepView: View {
    @Bindable var coordinator: ChironOnboardingCoordinator

    var body: some View {
        OnboardingScreenScaffold(
            title: "How do you identify?",
            subtitle: "This picks the body diagram we'll show later when asking about injuries. You can change it in settings.",
            ctaTitle: "Continue",
            ctaEnabled: coordinator.draft.gender != nil,
            currentStep: coordinator.progressStepIndex,
            totalSteps: coordinator.totalProgressSteps,
            onContinue: { coordinator.advance() },
            onBack: { coordinator.goBack() }
        ) {
            VStack(spacing: 10) {
                ForEach(GenderIdentity.allCases) { option in
                    OnboardingOptionRow(
                        title: option.displayName,
                        isSelected: coordinator.draft.gender == option
                    ) {
                        coordinator.draft.gender = option
                    }
                }
            }
        }
    }
}

#Preview {
    GenderStepView(coordinator: ChironOnboardingCoordinator(store: InMemoryUserProfileStore()))
}
