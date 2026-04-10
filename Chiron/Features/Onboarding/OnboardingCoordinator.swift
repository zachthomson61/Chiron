import Foundation
import SwiftUI
import UIKit
import Combine

// MARK: - Onboarding Profile Builder

/// Mutable builder that accumulates answers screen-by-screen, then produces
/// an immutable OnboardingProfile at completion.
struct OnboardingProfileBuilder: Codable {
    var primaryGoal: PrimaryGoal?
    var fitnessLiteracy: FitnessLiteracy = .beginner
    var coachingVerbosity: CoachingVerbosity = .plain
    var squatSelfAssessment: SquatExperience = .newToSquats
    var usesRack: Bool = false
    var preferredCameraPosition: CameraPosition? = nil
    var hasInjuryConcern: Bool = false
    var wantsTempoCoaching: Bool = false

    /// Whether the user indicated "I'm just starting" on screen 2.
    var isBeginner: Bool = false

    /// Whether the user selected a goal on screen 5 (so screen 6 can be skipped).
    var goalSelectedOnScreen5: Bool = false

    /// Whether camera permission was granted.
    var cameraGranted: Bool = false

    // Analytics-only fields (stored separately, not in OnboardingProfile)
    var analyticsDict: [String: String] = [:]

    /// Build the final immutable profile. Returns nil if primaryGoal is not set.
    func build() -> OnboardingProfile? {
        guard let goal = primaryGoal else { return nil }
        let tempo: Bool
        switch goal {
        case .getStronger, .buildMuscle, .enhanceAthleticPerformance:
            tempo = true
        default:
            tempo = wantsTempoCoaching
        }
        return OnboardingProfile(
            primaryGoal: goal,
            fitnessLiteracy: fitnessLiteracy,
            coachingVerbosity: coachingVerbosity,
            squatSelfAssessment: squatSelfAssessment,
            usesRack: usesRack,
            preferredCameraPosition: preferredCameraPosition,
            hasInjuryConcern: hasInjuryConcern,
            wantsTempoCoaching: tempo
        )
    }
}

// MARK: - Screen Definition

enum OnboardingScreenId: String, CaseIterable, Codable {
    case screen_01, screen_02, screen_03, screen_04
    case screen_05, screen_06, screen_07, screen_08
    case screen_09, screen_10, screen_11, screen_12
    case screen_13, screen_14, screen_15, screen_16
}

// MARK: - Coordinator

@MainActor
final class OnboardingCoordinator: ObservableObject {

    // MARK: Published state

    @Published var currentScreenIndex: Int = 0
    @Published var profile: OnboardingProfileBuilder = OnboardingProfileBuilder()
    @Published var shownAffirmations: Set<String> = []
    @Published var planRevealProgress: CGFloat = 0.0
    @Published var planFields: [PlanField] = PlanField.defaultFields()
    @Published var isTransitioningForward: Bool = true
    @Published var showAffirmation: Bool = false
    @Published var affirmationText: String = ""

    // MARK: Screen sequence

    /// The full ordered screen sequence. Conditional screens are included;
    /// shouldShow(screen:) handles skip logic.
    private let allScreens: [OnboardingScreenId] = OnboardingScreenId.allCases

    /// The resolved screen list after applying skip logic.
    var visibleScreens: [OnboardingScreenId] {
        allScreens.filter { shouldShow(screen: $0) }
    }

    var currentScreen: OnboardingScreenId {
        let screens = visibleScreens
        guard currentScreenIndex >= 0, currentScreenIndex < screens.count else {
            return .screen_01
        }
        return screens[currentScreenIndex]
    }

    var progress: CGFloat {
        let screens = visibleScreens
        guard screens.count > 1 else { return 0 }
        return CGFloat(currentScreenIndex) / CGFloat(screens.count - 1)
    }

    var canGoBack: Bool {
        currentScreenIndex > 0
    }

    var isPlanCardVisible: Bool {
        let screenIndex = allScreens.firstIndex(of: currentScreen) ?? 0
        return screenIndex >= 3 // Visible from screen_04 onward
    }

    // MARK: Navigation history (for back)

    private var history: [Int] = []

    // MARK: Persistence keys

    private let profileKey = "chiron.onboarding.profile"
    private let completionKey = "has_completed_onboarding"
    private let finalProfileKey = "onboarding_profile_v1"
    private let verbosityKey = "chiron.coaching.verbosity"
    private let genderKey = "user_gender"
    private let analyticsPrefix = "onboarding_analytics_"

    // MARK: Init

    init() {
        restoreIfNeeded()
    }

    // MARK: Skip logic

    private func shouldShow(screen: OnboardingScreenId) -> Bool {
        switch screen {
        case .screen_06:
            // Skip if goal was selected on screen 5
            return !profile.goalSelectedOnScreen5
        case .screen_09:
            // Skip for beginners
            return !profile.isBeginner
        case .screen_10:
            // Skip for beginners
            return !profile.isBeginner
        default:
            return true
        }
    }

    // MARK: Navigation

    func completeScreen(_ screenId: String, answer: String? = nil) {
        // Save to analytics if needed
        if let answer = answer {
            profile.analyticsDict[screenId] = answer
        }

        // Update plan reveal progress
        updatePlanRevealProgress(for: currentScreen)

        // Auto-save partial profile
        savePartialProfile()

        // Advance to next screen
        history.append(currentScreenIndex)
        isTransitioningForward = true

        let screens = visibleScreens
        if currentScreenIndex < screens.count - 1 {
            currentScreenIndex += 1
        }
    }

    func goBack() {
        guard let previous = history.popLast() else { return }
        isTransitioningForward = false
        currentScreenIndex = previous
    }

    // MARK: Screen-specific profile writes

    func setExperienceGate(isBeginner: Bool) {
        profile.isBeginner = isBeginner
        if isBeginner {
            profile.squatSelfAssessment = .newToSquats
            profile.fitnessLiteracy = .beginner
            profile.coachingVerbosity = .plain
        }
    }

    func setPrimaryGoal(_ goal: PrimaryGoal, fromScreen5: Bool) {
        profile.primaryGoal = goal
        if fromScreen5 {
            profile.goalSelectedOnScreen5 = true
        }
        // Default wantsTempoCoaching from goal
        switch goal {
        case .getStronger, .buildMuscle, .enhanceAthleticPerformance:
            profile.wantsTempoCoaching = true
        default:
            profile.wantsTempoCoaching = false
        }
        // Reveal Goal field
        revealPlanField(id: "primary_goal", value: goal.displayName)
    }

    func setTrainingEnvironment(_ environment: String) {
        let usesRack: Bool
        switch environment {
        case "Full gym":
            usesRack = true
        case "Home gym":
            usesRack = true
        case "Bodyweight only":
            usesRack = false
        case "Mix of both":
            usesRack = true
        default:
            usesRack = false
        }
        profile.usesRack = usesRack
        if usesRack {
            profile.preferredCameraPosition = .rack
        }
        revealPlanField(id: "environment", value: environment)
    }

    func setLiteracyCalibration(answerId: String) {
        switch answerId {
        case "quarter_squat", "half_squat":
            profile.fitnessLiteracy = .beginner
            profile.coachingVerbosity = .plain
        case "parallel_squat", "atg_squat":
            profile.fitnessLiteracy = .intermediate
            profile.coachingVerbosity = .plain
        default:
            profile.fitnessLiteracy = .beginner
            profile.coachingVerbosity = .plain
        }
        let style: String
        switch profile.fitnessLiteracy {
        case .beginner: style = "Supportive"
        case .intermediate: style = "Detailed"
        case .advanced: style = "Technical"
        }
        revealPlanField(id: "coaching_style", value: style)
    }

    func setSquatExperience(_ experience: SquatExperience) {
        profile.squatSelfAssessment = experience
        let focus: String
        switch experience {
        case .newToSquats: focus = "Learning form"
        case .someExperience: focus = "Refining depth"
        case .confident: focus = "Optimizing performance"
        }
        revealPlanField(id: "focus", value: focus)
    }

    func setInjuryConcern(_ hasConcern: Bool) {
        profile.hasInjuryConcern = hasConcern
        revealPlanField(id: "safety_mode", value: hasConcern ? "Joint-safe mode" : "Standard")
    }

    func setCameraGranted(_ granted: Bool) {
        profile.cameraGranted = granted
        if granted {
            revealPlanField(id: "ai_coach", value: "Active")
            planRevealProgress = 1.0
        } else {
            updatePlanFieldValue(id: "ai_coach", value: "Off")
        }
    }

    func setTrainingDuration(_ duration: String) {
        revealPlanField(id: "experience", value: duration)
    }

    // MARK: Beginner auto-fill for plan card

    func autoFillBeginnerFields() {
        // After screen_08 for beginners, auto-fill the fields that would
        // have been revealed by screens 9 and 10
        revealPlanField(id: "coaching_style", value: "Supportive")
        revealPlanField(id: "focus", value: "Learning form")
    }

    // MARK: Plan field management

    private func revealPlanField(id: String, value: String) {
        if let index = planFields.firstIndex(where: { $0.id == id }) {
            planFields[index].value = value
            planFields[index].isRevealed = true
        }
    }

    private func updatePlanFieldValue(id: String, value: String) {
        if let index = planFields.firstIndex(where: { $0.id == id }) {
            planFields[index].value = value
            planFields[index].isRevealed = true
        }
    }

    private func updatePlanRevealProgress(for screen: OnboardingScreenId) {
        switch screen {
        case .screen_04: planRevealProgress = 0.10
        case .screen_05: planRevealProgress = 0.20
        case .screen_06: planRevealProgress = 0.20
        case .screen_07: planRevealProgress = 0.35
        case .screen_08:
            planRevealProgress = 0.45
            if profile.isBeginner {
                // Auto-fill fields for beginners since they skip 9-10
                autoFillBeginnerFields()
                planRevealProgress = 0.60
            }
        case .screen_09: planRevealProgress = 0.55
        case .screen_10: planRevealProgress = 0.60
        case .screen_11: planRevealProgress = 0.65
        case .screen_12: planRevealProgress = 0.70
        case .screen_13: planRevealProgress = 0.80
        case .screen_14: planRevealProgress = 0.90
        case .screen_15: planRevealProgress = profile.cameraGranted ? 1.0 : 0.90
        case .screen_16: planRevealProgress = 1.0
        default: break
        }
    }

    // MARK: Affirmation

    func showAffirmationToast(_ text: String, forScreen screenId: String) {
        guard !shownAffirmations.contains(screenId) else { return }
        shownAffirmations.insert(screenId)
        affirmationText = text
        showAffirmation = true
        UIAccessibility.post(notification: .announcement, argument: text)

        // Auto-dismiss after 400ms total
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.showAffirmation = false
        }
    }

    // MARK: Completion

    func completeOnboarding() {
        guard let finalProfile = profile.build() else { return }

        // 1. Write full profile to UserDefaults
        if let data = try? JSONEncoder().encode(finalProfile) {
            UserDefaults.standard.set(data, forKey: finalProfileKey)
        }

        // 2. Set tracked exercise type on OnDevicePoseManager
        OnDevicePoseManager.shared.trackedExerciseType = finalProfile.defaultTrackedExerciseType

        // 3. Set bench press view type
        OnDevicePoseManager.shared.benchPressViewType = finalProfile.resolvedBenchPressViewType

        // 4. Write coaching verbosity
        UserDefaults.standard.set(
            finalProfile.coachingVerbosity.rawValue,
            forKey: verbosityKey
        )

        // 5. Reset rep counting state
        OnDevicePoseManager.shared.resetRepCountingState()

        // 6. Write primary goal via UserPreferencesManager
        UserPreferencesManager.shared.primaryGoal = finalProfile.primaryGoal

        // 7. Write analytics dictionary
        for (key, value) in profile.analyticsDict {
            UserDefaults.standard.set(value, forKey: analyticsPrefix + key)
        }

        // 8. Clean up partial save
        UserDefaults.standard.removeObject(forKey: profileKey)

        // 9. Mark onboarding complete (triggers ContentView gate)
        UserDefaults.standard.set(true, forKey: completionKey)
    }

    // MARK: Persistence

    private func savePartialProfile() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: profileKey)
        }
    }

    private func restoreIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: profileKey),
              let saved = try? JSONDecoder().decode(OnboardingProfileBuilder.self, from: data) else {
            return
        }
        self.profile = saved
        // Restore screen index based on saved state
        // Find the furthest screen that has data
        let screens = visibleScreens
        var restoredIndex = 0
        if saved.primaryGoal != nil { restoredIndex = max(restoredIndex, indexFor(.screen_05, in: screens)) }
        if saved.analyticsDict["screen_07"] != nil { restoredIndex = max(restoredIndex, indexFor(.screen_07, in: screens)) }
        if saved.analyticsDict["screen_08"] != nil { restoredIndex = max(restoredIndex, indexFor(.screen_08, in: screens)) }
        self.currentScreenIndex = restoredIndex

        // Restore plan fields
        restorePlanFields()
    }

    private func indexFor(_ screen: OnboardingScreenId, in screens: [OnboardingScreenId]) -> Int {
        screens.firstIndex(of: screen) ?? 0
    }

    private func restorePlanFields() {
        if let goal = profile.primaryGoal {
            revealPlanField(id: "primary_goal", value: goal.displayName)
        }
        if profile.analyticsDict["screen_07"] != nil {
            revealPlanField(id: "experience", value: profile.analyticsDict["screen_07"] ?? "")
        }
        if profile.analyticsDict["screen_08"] != nil {
            revealPlanField(id: "environment", value: profile.analyticsDict["screen_08"] ?? "")
        }
    }
}
