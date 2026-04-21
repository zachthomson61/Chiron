//
//  ChironUserProfile.swift
//  Chiron
//
//  Seed state for the progressive user model. The onboarding flow produces one of
//  these and persists it via UserProfileStore. Downstream systems — the coaching
//  layer, training log, and future multi-agent coach — read from it.
//
//  Named `ChironUserProfile` rather than `UserProfile` because `Models/UserProfile.swift`
//  already owns that identifier for the current display-layer profile card. See
//  Onboarding/README.md for the migration plan.
//

import Foundation

/// Seed state for Chiron's progressive user model.
///
/// Every field is writable so the coaching layer can refine the profile session-over-session.
/// Bumps to `schemaVersion` signal that persisted payloads may need migration.
struct ChironUserProfile: Codable, Equatable {

    /// Current schema revision. Bump whenever a non-additive change lands.
    static let currentSchemaVersion: Int = 1

    var topGoal: FitnessGoal
    var experienceLevel: ExperienceLevel
    var gender: GenderIdentity
    var birthYear: Int
    var heightCm: Double
    var weightKg: Double

    /// Display-only — metric values above are the source of truth.
    var preferredUnits: UnitSystem

    var trackedExercises: Set<TrackedExerciseType>

    /// `true` if the user reported any injury or joint concern during onboarding.
    /// When `false`, the four injury fields below should be empty/nil — the gate
    /// answer is authoritative.
    var hasInjuryConcerns: Bool
    var injuryFlags: Set<InjuryArea>
    /// Free-text description when `injuryFlags` contains `.other`. Empty otherwise.
    var injuryOtherDescription: String
    var movementLimitation: MovementLimitation?
    var discomfortMovements: Set<DiscomfortMovement>

    var coachPersona: CoachPersona

    /// 1...5. Clamp at write sites; don't trust callers.
    var coachIntensity: Int

    var createdAt: Date
    var schemaVersion: Int

    init(
        topGoal: FitnessGoal,
        experienceLevel: ExperienceLevel,
        gender: GenderIdentity,
        birthYear: Int,
        heightCm: Double,
        weightKg: Double,
        preferredUnits: UnitSystem,
        trackedExercises: Set<TrackedExerciseType>,
        hasInjuryConcerns: Bool,
        injuryFlags: Set<InjuryArea>,
        injuryOtherDescription: String,
        movementLimitation: MovementLimitation?,
        discomfortMovements: Set<DiscomfortMovement>,
        coachPersona: CoachPersona,
        coachIntensity: Int,
        createdAt: Date = Date(),
        schemaVersion: Int = ChironUserProfile.currentSchemaVersion
    ) {
        self.topGoal = topGoal
        self.experienceLevel = experienceLevel
        self.gender = gender
        self.birthYear = birthYear
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.preferredUnits = preferredUnits
        self.trackedExercises = trackedExercises
        self.hasInjuryConcerns = hasInjuryConcerns
        self.injuryFlags = injuryFlags
        self.injuryOtherDescription = injuryOtherDescription
        self.movementLimitation = movementLimitation
        self.discomfortMovements = discomfortMovements
        self.coachPersona = coachPersona
        self.coachIntensity = min(max(coachIntensity, 1), 5)
        self.createdAt = createdAt
        self.schemaVersion = schemaVersion
    }
}

// MARK: - Derived Helpers

extension ChironUserProfile {

    /// Age derived from `birthYear` against the current calendar year.
    var age: Int {
        let currentYear = Calendar.current.component(.year, from: Date())
        return max(0, currentYear - birthYear)
    }

    var coachIntensityLevel: CoachIntensityLevel {
        CoachIntensityLevel.from(clamped: coachIntensity)
    }
}

// MARK: - Draft

/// Partial profile under construction during onboarding.
/// Each field is optional; `finalize()` returns a concrete `ChironUserProfile` when all
/// required fields are present.
struct ChironUserProfileDraft: Equatable {
    var topGoal: FitnessGoal?
    var experienceLevel: ExperienceLevel?
    var gender: GenderIdentity?
    var birthYear: Int?
    var heightCm: Double?
    var weightKg: Double?
    var preferredUnits: UnitSystem = .imperial
    var trackedExercises: Set<TrackedExerciseType> = TrackedExerciseType.onboardingDefaults

    // Injury gate + branch data
    var hasInjuryConcerns: Bool?
    var injuryFlags: Set<InjuryArea> = []
    var injuryOtherDescription: String = ""
    var movementLimitation: MovementLimitation?
    var discomfortMovements: Set<DiscomfortMovement> = []

    var coachPersona: CoachPersona?
    var coachIntensity: Int = 3

    func finalize() -> ChironUserProfile? {
        guard
            let topGoal,
            let experienceLevel,
            let gender,
            let birthYear,
            let heightCm,
            let weightKg,
            let hasInjuryConcerns,
            let coachPersona
        else { return nil }

        return ChironUserProfile(
            topGoal: topGoal,
            experienceLevel: experienceLevel,
            gender: gender,
            birthYear: birthYear,
            heightCm: heightCm,
            weightKg: weightKg,
            preferredUnits: preferredUnits,
            trackedExercises: trackedExercises,
            hasInjuryConcerns: hasInjuryConcerns,
            injuryFlags: hasInjuryConcerns ? injuryFlags : [],
            injuryOtherDescription: hasInjuryConcerns ? injuryOtherDescription : "",
            movementLimitation: hasInjuryConcerns ? movementLimitation : nil,
            discomfortMovements: hasInjuryConcerns ? discomfortMovements : [],
            coachPersona: coachPersona,
            coachIntensity: coachIntensity
        )
    }
}
