//
//  OnboardingEnums.swift
//  Chiron
//
//  Enums owned by the onboarding flow and persisted as part of ChironUserProfile.
//  Raw values are stable strings so the profile survives schema evolution.
//

import Foundation

// MARK: - Fitness Goal

/// Onboarding-facing fitness goal. Cases mirror `PrimaryGoal` in Models/PrimaryGoal.swift
/// 1:1 so the two can be mapped cleanly — the home-screen primary-goal card and the
/// onboarding goal step stay in lockstep.
enum FitnessGoal: String, Codable, CaseIterable, Identifiable {
    // Declaration order = display order in the goal step (ForEach iterates
    // allCases). Raw values are the case names, so reordering here doesn't
    // break persisted profiles.
    case loseFat
    case buildMuscle
    case getStronger
    case rehabPreventInjury
    case improveHealthLongevity
    case enhanceAthleticPerformance
    case improveEndurance
    case getToned

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .loseFat:                      return "Lose fat"
        case .buildMuscle:                  return "Build muscle"
        case .getStronger:                  return "Get stronger"
        case .rehabPreventInjury:           return "Rehab or prevent injury"
        case .improveHealthLongevity:       return "Support health & longevity"
        case .enhanceAthleticPerformance:   return "Enhance athletic performance"
        case .improveEndurance:             return "Boost endurance"
        case .getToned:                     return "Get toned"
        }
    }

    /// SF Symbol name for the leading icon in each option row.
    var iconName: String {
        switch self {
        case .loseFat:                      return "flame.fill"
        case .buildMuscle:                  return "figure.strengthtraining.traditional"
        case .getStronger:                  return "bolt.fill"
        case .rehabPreventInjury:           return "cross.case.fill"
        case .improveHealthLongevity:       return "heart.fill"
        case .enhanceAthleticPerformance:   return "trophy.fill"
        case .improveEndurance:             return "figure.run"
        case .getToned:                     return "figure.strengthtraining.functional"
        }
    }
}

// MARK: - Experience Level

enum ExperienceLevel: String, Codable, CaseIterable, Identifiable {
    case newToLifting
    case someExperience
    case experienced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newToLifting:     return "New to lifting"
        case .someExperience:   return "Some experience"
        case .experienced:      return "Experienced"
        }
    }

    var detail: String {
        switch self {
        case .newToLifting:     return "I'm just getting started"
        case .someExperience:   return "I know the main lifts"
        case .experienced:      return "I train consistently"
        }
    }

    var iconName: String {
        switch self {
        case .newToLifting:     return "sparkles"
        case .someExperience:   return "dumbbell.fill"
        case .experienced:      return "flame.fill"
        }
    }
}

// MARK: - Gender Identity

/// Self-reported gender identity. Drives which anatomical figure is shown on the
/// injury-location page. Male, non-binary, and prefer-not-to-say all default to the
/// male anatomy figure; female uses the female figure.
enum GenderIdentity: String, Codable, CaseIterable, Identifiable {
    case male
    case female
    case nonBinary
    case preferNotToSay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .male:             return "Male"
        case .female:           return "Female"
        case .nonBinary:        return "Non-binary"
        case .preferNotToSay:   return "Prefer not to say"
        }
    }

    var iconName: String {
        switch self {
        case .male:             return "figure.stand"
        case .female:           return "figure.stand.dress"
        case .nonBinary:        return "figure.arms.open"
        case .preferNotToSay:   return "questionmark.circle"
        }
    }

    /// Which anatomical figure to show on the injury-location page for this identity.
    var anatomyAssetName: String {
        self == .female ? "AnatomyFemale" : "AnatomyMale"
    }
}

// MARK: - Unit System

enum UnitSystem: String, Codable, CaseIterable, Identifiable {
    case imperial
    case metric

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .imperial: return "Imperial"
        case .metric:   return "Metric"
        }
    }
}

// MARK: - Injury Area

/// Anatomical locations the user can flag during onboarding.
/// `.other` is a catch-all backed by a free-text description on the draft.
enum InjuryArea: String, Codable, CaseIterable, Identifiable, Hashable {
    case knee
    case lowerBack
    case shoulder
    case hip
    case ankle
    case wrist
    case elbow
    case neck
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .knee:         return "Knee"
        case .lowerBack:    return "Lower back"
        case .shoulder:     return "Shoulder"
        case .hip:          return "Hip"
        case .ankle:        return "Ankle"
        case .wrist:        return "Wrist"
        case .elbow:        return "Elbow"
        case .neck:         return "Neck"
        case .other:        return "Other"
        }
    }
}

// MARK: - Movement Limitation

/// How much the flagged issue interferes with training. Used by the coaching layer to
/// decide how aggressively to cue tempo, depth, and load recommendations.
enum MovementLimitation: String, Codable, CaseIterable, Identifiable {
    case noLimitation
    case mildDiscomfort
    case moderateLimitation
    case severe

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .noLimitation:         return "No limitation"
        case .mildDiscomfort:       return "Mild discomfort"
        case .moderateLimitation:   return "Moderate limitation"
        case .severe:               return "Severe"
        }
    }

    var detail: String {
        switch self {
        case .noLimitation:         return "Just awareness"
        case .mildDiscomfort:       return "Can train normally"
        case .moderateLimitation:   return "Some movements painful"
        case .severe:               return "Cannot perform certain movements"
        }
    }
}

// MARK: - Discomfort Movements

/// Movement patterns that cause discomfort. Multi-select.
enum DiscomfortMovement: String, Codable, CaseIterable, Identifiable, Hashable {
    case squatting
    case hinging
    case pressing
    case pulling
    case runningJumping
    case twisting

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .squatting:        return "Squatting"
        case .hinging:          return "Hinging (deadlifts)"
        case .pressing:         return "Pressing (bench/overhead)"
        case .pulling:          return "Pulling"
        case .runningJumping:   return "Running/jumping"
        case .twisting:         return "Twisting/rotation"
        }
    }

    var iconName: String {
        switch self {
        // `figure.cross.training` reads as a loaded squat stance.
        case .squatting:        return "figure.cross.training"
        // Barbell-on-back figure moved here — matches hinging / deadlift.
        case .hinging:          return "figure.strengthtraining.traditional"
        // Horizontal dumbbell reads as a bench press bar.
        case .pressing:         return "dumbbell.horizontal.fill"
        case .pulling:          return "figure.rower"
        case .runningJumping:   return "figure.run"
        case .twisting:         return "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - Coach Persona

enum CoachPersona: String, Codable, CaseIterable, Identifiable {
    case drillSergeant
    case technician
    case hypeFriend
    case quietPro

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .drillSergeant:    return "The Drill Sergeant"
        case .technician:       return "The Technician"
        case .hypeFriend:       return "The Hype Friend"
        case .quietPro:         return "The Quiet Pro"
        }
    }

    var descriptor: String {
        switch self {
        case .drillSergeant:    return "Blunt. Direct. Holds nothing back."
        case .technician:       return "Precise, technical cues. Focused on form."
        case .hypeFriend:       return "Encouraging, energetic, celebrates every rep."
        case .quietPro:         return "Minimal talk. Only speaks when something matters."
        }
    }
}

// MARK: - Coach Intensity

/// Named rungs along the 1-5 coaching-intensity slider.
/// The raw value is the rung number; `label` and `exampleCue` power the live-morphing slider UI.
enum CoachIntensityLevel: Int, CaseIterable, Identifiable {
    case whisper = 1
    case gentle = 2
    case balanced = 3
    case assertive = 4
    case relentless = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .whisper:      return "Whisper"
        case .gentle:       return "Gentle"
        case .balanced:     return "Balanced"
        case .assertive:    return "Assertive"
        case .relentless:   return "Relentless"
        }
    }

    /// Sample cue text shown on the intensity slider. Copy escalates with the rung.
    var exampleCue: String {
        switch self {
        case .whisper:      return "A little deeper next rep."
        case .gentle:       return "Nice work — try to sink an inch lower."
        case .balanced:     return "Depth's shallow. Drop your hips lower."
        case .assertive:    return "Go deeper. Hit parallel on the next one."
        case .relentless:   return "DRIVE THROUGH THE FLOOR. Again."
        }
    }

    /// Resolve from a clamped Int in 1...5. Falls back to `.balanced`.
    static func from(clamped value: Int) -> CoachIntensityLevel {
        CoachIntensityLevel(rawValue: min(max(value, 1), 5)) ?? .balanced
    }
}

// MARK: - TrackedExerciseType Codable Shim

/// `TrackedExerciseType` lives in OnDevicePoseManager.swift and is an unannotated
/// `enum` (no raw values, no Codable conformance). The onboarding layer needs to
/// serialize it as part of the profile, so we add Codable conformance here via a
/// stable string key. New cases added to the source enum must also be added here
/// — the exhaustive switch will flag any drift at compile time.
extension TrackedExerciseType: Codable, Hashable, CaseIterable {
    public static var allCases: [TrackedExerciseType] {
        [.bodyweight, .barbell, .benchPress, .closeGripBenchPress, .row, .deadlift, .romanianDeadlift]
    }

    /// Stable string identifier used for Codable + display.
    var storageKey: String {
        switch self {
        case .bodyweight:           return "bodyweight_squat"
        case .barbell:              return "barbell_back_squat"
        case .benchPress:           return "barbell_bench_press"
        case .closeGripBenchPress:  return "close_grip_bench_press"
        case .row:                  return "barbell_row"
        case .deadlift:             return "deadlift"
        case .romanianDeadlift:     return "romanian_deadlift"
        }
    }

    /// Human-readable name used in the "ready" summary card.
    var displayName: String {
        switch self {
        case .bodyweight:           return "Bodyweight Squat"
        case .barbell:              return "Barbell Back Squat"
        case .benchPress:           return "Barbell Bench Press"
        case .closeGripBenchPress:  return "Close-Grip Bench Press"
        case .row:                  return "Barbell Row"
        case .deadlift:             return "Deadlift"
        case .romanianDeadlift:     return "Romanian Deadlift"
        }
    }

    /// The six MVP exercises exposed during onboarding. `closeGripBenchPress` is
    /// a variation of bench press and is excluded to keep the default lift list clean.
    static var onboardingDefaults: Set<TrackedExerciseType> {
        [.bodyweight, .barbell, .benchPress, .row, .deadlift, .romanianDeadlift]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let key = try container.decode(String.self)
        guard let match = TrackedExerciseType.allCases.first(where: { $0.storageKey == key }) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown TrackedExerciseType storage key: \(key)"
            )
        }
        self = match
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageKey)
    }
}
