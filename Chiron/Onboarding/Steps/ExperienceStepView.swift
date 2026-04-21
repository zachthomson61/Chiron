//
//  ExperienceStepView.swift
//  Chiron
//
//  Step 3 — experience level. Gates coaching aggression downstream.
//

import SwiftUI

struct ExperienceStepView: View {
    @Bindable var coordinator: ChironOnboardingCoordinator

    var body: some View {
        OnboardingScreenScaffold(
            title: "How much lifting experience do you have?",
            subtitle: "This tunes how direct your coach is — more guidance for early days, less hand-holding later.",
            ctaTitle: "Continue",
            ctaEnabled: coordinator.canAdvance,
            currentStep: coordinator.progressStepIndex,
            totalSteps: coordinator.totalProgressSteps,
            onContinue: { coordinator.advance() },
            onBack: { coordinator.goBack() }
        ) {
            VStack(spacing: 10) {
                ForEach(ExperienceLevel.allCases) { level in
                    OnboardingOptionRow(
                        title: level.displayName,
                        icon: level.iconName,
                        descriptor: level.detail,
                        isSelected: coordinator.draft.experienceLevel == level
                    ) {
                        coordinator.draft.experienceLevel = level
                    }
                }
            }
        }
    }
}

#Preview {
    ExperienceStepView(coordinator: ChironOnboardingCoordinator(store: InMemoryUserProfileStore()))
}
