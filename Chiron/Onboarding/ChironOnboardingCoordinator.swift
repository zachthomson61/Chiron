//
//  ChironOnboardingCoordinator.swift
//  Chiron
//
//  Owns the step index and the in-progress profile draft. Step views take the
//  coordinator via @Bindable; no step ever reaches into another step's state.
//

import SwiftUI
import Observation

/// Ordered set of screens in the onboarding flow. The raw value is also the
/// progress-bar segment index, so adding a step is one enum case away.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case goal
    case experience
    case gender
    case age
    case heightWeight
    case injuries                  // binary yes/no gate
    case injuryLocation            // branch: body diagram, shown only if "Yes"
    case movementLimitation        // branch: severity slider, shown only if "Yes"
    case discomfortMovements       // branch: multi-select, shown only if "Yes"
    case coachInterstitial
    case coachPersona
    case coachIntensity
    case calculating
    case reveal
    case notificationPrimer
    case ready

    var id: Int { rawValue }

    /// Steps that participate in the top progress bar. The welcome screen has no
    /// progress indicator (Cal AI pattern), but every question + reveal counts.
    static var progressSteps: [OnboardingStep] {
        OnboardingStep.allCases.filter { $0 != .welcome }
    }

    /// True if this step belongs to the injury follow-up branch and should be
    /// skipped when the user answered "No" on the gate.
    var isInjuryBranchStep: Bool {
        switch self {
        case .injuryLocation, .movementLimitation, .discomfortMovements:
            return true
        default:
            return false
        }
    }
}

// MARK: - Coordinator

/// Direction of the most recent step change. The root view uses this to decide
/// which edge the next screen slides in from, so back-navigation animates the
/// opposite direction of forward-navigation.
enum NavigationDirection {
    case forward, backward
}

@Observable
final class ChironOnboardingCoordinator {

    // MARK: Public State

    /// Active step. Drives the routed view.
    var step: OnboardingStep = .welcome

    /// Direction of the most recent navigation. Read by the root view when
    /// selecting the transition. Forward is the default because the first
    /// appearance of the welcome screen reads as a forward entry.
    var lastDirection: NavigationDirection = .forward

    /// Profile under construction. Step views bind directly into this draft.
    var draft = ChironUserProfileDraft()

    /// Called once, when the user finishes the flow and the finalized profile has been persisted.
    var onFinish: (ChironUserProfile) -> Void = { _ in }

    // MARK: Dependencies

    private let store: UserProfileStore

    init(store: UserProfileStore = UserDefaultsUserProfileStore()) {
        self.store = store
    }

    // MARK: Progress Bar

    /// 1-based segment index for the top progress bar.
    var progressStepIndex: Int {
        guard step != .welcome else { return 0 }
        return (OnboardingStep.progressSteps.firstIndex(of: step) ?? 0) + 1
    }

    var totalProgressSteps: Int { OnboardingStep.progressSteps.count }

    var showsTopBar: Bool {
        switch step {
        case .welcome, .calculating, .coachInterstitial:
            return false
        default:
            return true
        }
    }

    var canGoBack: Bool {
        step != .calculating && step != .ready
    }

    // MARK: Navigation

    func advance() {
        guard let next = nextStep(after: step) else {
            finish()
            return
        }
        lastDirection = .forward
        withAnimation(OnboardingTheme.selectionSpring) {
            step = next
        }
    }

    func goBack() {
        guard let previous = previousStep(before: step) else { return }
        lastDirection = .backward
        withAnimation(OnboardingTheme.selectionSpring) {
            step = previous
        }
    }

    /// Returns the next step that should be shown, honoring the injury branch skip.
    /// When the user answered "No" on the injury gate, the three follow-up steps are
    /// skipped both forwards and backwards.
    private func nextStep(after current: OnboardingStep) -> OnboardingStep? {
        var candidate = OnboardingStep(rawValue: current.rawValue + 1)
        while let step = candidate, shouldSkip(step) {
            candidate = OnboardingStep(rawValue: step.rawValue + 1)
        }
        return candidate
    }

    private func previousStep(before current: OnboardingStep) -> OnboardingStep? {
        guard current.rawValue > 0 else { return nil }
        var candidate = OnboardingStep(rawValue: current.rawValue - 1)
        while let step = candidate, shouldSkip(step) {
            guard step.rawValue > 0 else { return nil }
            candidate = OnboardingStep(rawValue: step.rawValue - 1)
        }
        return candidate
    }

    /// Whether a given step should be skipped based on the current draft state.
    private func shouldSkip(_ step: OnboardingStep) -> Bool {
        if step.isInjuryBranchStep {
            // If the user answered "No" (or hasn't answered yet and somehow advanced),
            // skip the entire branch.
            return draft.hasInjuryConcerns != true
        }
        return false
    }

    /// Jump to a specific step. Used by the calculating-loader auto-advance and DEBUG skip.
    /// Direction is inferred from the step indices so the transition still matches.
    func jump(to step: OnboardingStep) {
        lastDirection = step.rawValue >= self.step.rawValue ? .forward : .backward
        withAnimation(OnboardingTheme.selectionSpring) {
            self.step = step
        }
    }

    // MARK: Completion

    func finish() {
        guard let profile = draft.finalize() else { return }
        try? store.save(profile)
        onFinish(profile)
    }

    // MARK: Per-step validation

    /// Whether the CTA on the current step should be tappable. Each step is
    /// responsible for its own requirements; this keeps that logic in one place.
    var canAdvance: Bool {
        switch step {
        case .welcome:                  return true
        case .goal:                     return draft.topGoal != nil
        case .experience:               return draft.experienceLevel != nil
        case .gender:                   return draft.gender != nil
        case .age:                      return draft.birthYear != nil
        case .heightWeight:             return draft.heightCm != nil && draft.weightKg != nil
        case .injuries:                 return draft.hasInjuryConcerns != nil
        case .injuryLocation:
            guard !draft.injuryFlags.isEmpty else { return false }
            if draft.injuryFlags.contains(.other) {
                return !draft.injuryOtherDescription
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true
        case .movementLimitation:       return draft.movementLimitation != nil
        case .discomfortMovements:      return !draft.discomfortMovements.isEmpty
        case .coachInterstitial:        return true
        case .coachPersona:             return draft.coachPersona != nil
        case .coachIntensity:           return true
        case .calculating:              return false
        case .reveal:                   return true
        case .notificationPrimer:       return true
        case .ready:                    return true
        }
    }

    // MARK: DEBUG helpers

    #if DEBUG
    /// Fills the draft with plausible defaults and skips to the reveal. DEBUG only.
    func debugSkipToEnd() {
        draft.topGoal = draft.topGoal ?? .getStronger
        draft.experienceLevel = draft.experienceLevel ?? .someExperience
        draft.gender = draft.gender ?? .preferNotToSay
        draft.birthYear = draft.birthYear ?? 1995
        draft.heightCm = draft.heightCm ?? 178
        draft.weightKg = draft.weightKg ?? 80
        draft.hasInjuryConcerns = draft.hasInjuryConcerns ?? false
        draft.coachPersona = draft.coachPersona ?? .technician
        jump(to: .reveal)
    }
    #endif
}
