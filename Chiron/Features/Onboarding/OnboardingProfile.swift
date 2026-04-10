import Foundation

// MARK: - Coaching Verbosity

/// Gates cue language complexity in LLM system prompts and fallback strings.
/// .technical  -> uses anatomical terms ("knee valgus", "eccentric phase")
/// .plain      -> uses everyday language ("knees caving in", "lowering too fast")
/// .minimal    -> fewest words, experienced lifters who just want the cue
///
/// Downstream: injected into OpenAICoachingManager system prompt and
/// CoachingContract.cue(for:) display-text selection.
enum CoachingVerbosity: String, Codable, CaseIterable {
    case plain
    case technical
    case minimal
}

/// Derived from the literacy calibration screen.
/// NOT self-reported experience years -- calibrated via knowledge question.
enum FitnessLiteracy: String, Codable, CaseIterable {
    case beginner
    case intermediate
    case advanced
}

/// Self-assessed squat experience. Maps directly to initial
/// SquatRepDetectionProfile sensitivity values.
enum SquatExperience: String, Codable, CaseIterable {
    case newToSquats
    case someExperience
    case confident
}

/// Camera position preference for bench press exercises.
/// Maps 1:1 to BenchPressViewType on OnDevicePoseManager.
enum CameraPosition: String, Codable, CaseIterable {
    case rack
    case floor
    case tripod
}

// MARK: - OnboardingProfile

/// Collected during onboarding. Every field traces to a concrete behavior
/// change in OnDevicePoseManager, CoachingContract, or OpenAICoachingManager.
/// Persisted via Codable (UserDefaults). NOT the same as UserProfile.
struct OnboardingProfile: Codable {

    // -- Core identity (reuses existing enum) --

    /// User's primary fitness goal.
    let primaryGoal: PrimaryGoal

    // -- Fitness literacy & coaching language --

    let fitnessLiteracy: FitnessLiteracy

    /// Explicit coaching language preference (defaulted from fitnessLiteracy,
    /// user can override in settings later).
    var coachingVerbosity: CoachingVerbosity

    // -- Squat configuration --

    let squatSelfAssessment: SquatExperience

    // -- Equipment & camera --

    let usesRack: Bool

    let preferredCameraPosition: CameraPosition?

    // -- Injury / conservative mode --

    let hasInjuryConcern: Bool

    // -- Tempo coaching gate --

    var wantsTempoCoaching: Bool

    // -- Computed helpers --

    /// Returns the initial TrackedExerciseType to set on OnDevicePoseManager.
    var defaultTrackedExerciseType: TrackedExerciseType {
        switch primaryGoal {
        case .getStronger, .buildMuscle, .enhanceAthleticPerformance:
            return usesRack ? .barbell : .bodyweight
        case .loseFat, .getToned, .improveEndurance:
            return .bodyweight
        case .improveHealthLongevity, .rehabPreventInjury:
            return .bodyweight
        }
    }

    /// Builds the initial SquatRepDetectionProfile tuned to this user.
    func buildSquatProfile() -> SquatRepDetectionProfile {
        var profile = SquatRepProfileTable.profile(for: .chest_side)

        switch squatSelfAssessment {
        case .newToSquats:
            profile.downAngleThreshold = 110
            profile.repCountDepthThreshold = 0.18
            profile.repGoodDepthThreshold = 0.30
        case .someExperience:
            break
        case .confident:
            profile.downAngleThreshold = 95
            profile.repCountDepthThreshold = 0.26
            profile.repGoodDepthThreshold = 0.42
        }

        switch primaryGoal {
        case .getStronger, .buildMuscle:
            profile.formWeightDepth = 1.0
            profile.formWeightForwardLean = 0.85
        case .rehabPreventInjury:
            profile.formWeightKneeTracking = 1.0
            profile.formWeightDepth = 0.7
        case .loseFat, .getToned, .improveEndurance:
            profile.formWeightDepth = 0.85
            profile.formWeightForwardLean = 1.0
        default:
            break
        }

        if hasInjuryConcern {
            profile.formWeightKneeTracking = 1.0
            profile.repGoodDepthThreshold = min(profile.repGoodDepthThreshold, 0.30)
        }

        return profile
    }

    /// Returns the BenchPressViewType to set on OnDevicePoseManager.
    var resolvedBenchPressViewType: BenchPressViewType {
        if let pos = preferredCameraPosition {
            switch pos {
            case .rack:   return .rack
            case .floor:  return .floor
            case .tripod: return .tripod
            }
        }
        return usesRack ? .rack : .tripod
    }

    /// IssueCode items that should be suppressed from PhrasingPayload entirely.
    var suppressedIssueCodes: Set<IssueCode> {
        var suppressed = Set<IssueCode>()
        if !wantsTempoCoaching {
            suppressed.insert(.eccentricTooFast)
            suppressed.insert(.concentricTooSlow)
        }
        return suppressed
    }

    /// IssueCode items that should be promoted to primary regardless of
    /// default CoachingContract.priorityOrder.
    var priorityWatchIssueCodes: Set<IssueCode> {
        var watch = Set<IssueCode>()
        if hasInjuryConcern {
            watch.insert(.kneeValgus)
            watch.insert(.insufficientDepth)
        }
        if primaryGoal == .rehabPreventInjury {
            watch.insert(.kneeValgus)
            watch.insert(.kneeVarus)
            watch.insert(.forwardLean)
        }
        return watch
    }
}
