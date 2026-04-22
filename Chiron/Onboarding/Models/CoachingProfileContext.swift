//
//  CoachingProfileContext.swift
//  Chiron
//
//  Bridge between the persisted ChironUserProfile (produced by onboarding) and
//  the phrasing layer in OpenAICoachingManager. The context resolves, for a
//  given exercise + set index, which profile-derived directives should be
//  folded into the LLM prompt and the deterministic fallback.
//
//  Pipeline:
//      ChironUserProfile + exerciseType + setIndex
//          → CoachingProfileContext
//              → prompt directives (LLM)
//              → fallback prefix (deterministic)
//

import Foundation

// MARK: - FitnessGoal ↔ PrimaryGoal bridge

extension FitnessGoal {
    /// 1:1 mapping onto the home-screen primary goal. The two enums track each
    /// other — see `PrimaryGoal.swift` and `OnboardingEnums.swift`.
    var asPrimaryGoal: PrimaryGoal {
        switch self {
        case .loseFat:                      return .loseFat
        case .buildMuscle:                  return .buildMuscle
        case .getStronger:                  return .getStronger
        case .rehabPreventInjury:           return .rehabPreventInjury
        case .improveHealthLongevity:       return .improveHealthLongevity
        case .enhanceAthleticPerformance:   return .enhanceAthleticPerformance
        case .improveEndurance:             return .improveEndurance
        case .getToned:                     return .getToned
        }
    }
}

// MARK: - Injury / discomfort display + applicability

extension InjuryArea {
    /// The noun we prefer in coaching feedback — lowercase, plural where it
    /// reads more naturally ("shoulders" over "shoulder"). Used when the
    /// coaching manager needs to reference the area by name.
    var coachingNoun: String {
        switch self {
        case .knee:         return "knees"
        case .lowerBack:    return "lower back"
        case .shoulder:     return "shoulders"
        case .hip:          return "hips"
        case .ankle:        return "ankles"
        case .wrist:        return "wrists"
        case .elbow:        return "elbows"
        case .neck:         return "neck"
        case .other:        return "flagged area"
        }
    }

    /// True when this joint/area is loaded by the given exercise heavily enough
    /// that the coaching manager should mention it by name and be more lenient.
    /// `.other` always returns true — we don't know where it is, so err on the
    /// side of surfacing it.
    func appliesTo(_ exercise: TrackedExerciseType) -> Bool {
        switch self {
        case .other:
            return true
        case .knee:
            switch exercise {
            case .bodyweight, .barbell, .deadlift, .romanianDeadlift, .row:
                return true
            case .benchPress, .closeGripBenchPress:
                return false
            }
        case .lowerBack:
            // Every tracked lift loads the lumbar spine to some degree.
            return true
        case .shoulder:
            switch exercise {
            case .benchPress, .closeGripBenchPress, .row, .deadlift, .romanianDeadlift, .barbell:
                return true
            case .bodyweight:
                return false
            }
        case .hip:
            switch exercise {
            case .bodyweight, .barbell, .deadlift, .romanianDeadlift, .row:
                return true
            case .benchPress, .closeGripBenchPress:
                return false
            }
        case .ankle:
            switch exercise {
            case .bodyweight, .barbell, .deadlift, .romanianDeadlift, .row:
                return true
            case .benchPress, .closeGripBenchPress:
                return false
            }
        case .wrist:
            switch exercise {
            case .benchPress, .closeGripBenchPress, .row, .deadlift, .romanianDeadlift, .barbell:
                return true
            case .bodyweight:
                return false
            }
        case .elbow:
            switch exercise {
            case .benchPress, .closeGripBenchPress, .row:
                return true
            case .bodyweight, .barbell, .deadlift, .romanianDeadlift:
                return false
            }
        case .neck:
            // The barbell lifts load the cervical spine via bar/rack position;
            // bodyweight squats generally do not.
            switch exercise {
            case .bodyweight:
                return false
            case .barbell, .benchPress, .closeGripBenchPress, .row, .deadlift, .romanianDeadlift:
                return true
            }
        }
    }
}

extension DiscomfortMovement {
    /// Maps a flagged movement pattern onto the exercises we track.
    func appliesTo(_ exercise: TrackedExerciseType) -> Bool {
        switch self {
        case .squatting:
            return exercise == .bodyweight || exercise == .barbell
        case .hinging:
            return exercise == .deadlift || exercise == .romanianDeadlift
        case .pressing:
            return exercise == .benchPress || exercise == .closeGripBenchPress
        case .pulling:
            return exercise == .row
        case .runningJumping, .twisting:
            // No MVP exercise tracks these patterns.
            return false
        }
    }
}

// MARK: - Thresholds

extension ChironUserProfile {
    /// Sentinel height threshold (cm). 6'3" = 190.5 cm — above this we ask the
    /// coach to expect longer levers and be more forgiving about depth / lean.
    static let tallHeightCm: Double = 190.5

    /// Sentinel weight threshold (kg). 250 lb = 113.4 kg.
    static let heavyWeightKg: Double = 113.4

    /// Rough "older lifter" cutoff. Drives the gentler-feedback directive.
    static let olderLifterAgeYears: Int = 55

    var isTallLifter: Bool { heightCm > Self.tallHeightCm }
    var isHeavyLifter: Bool { weightKg > Self.heavyWeightKg }
    var isOlderLifter: Bool { age >= Self.olderLifterAgeYears }
}

// MARK: - Safety frequency

/// How often safety feedback should be surfaced for an exercise that touches a
/// flagged injury or discomfort pattern.
enum SafetyFrequency {
    /// Every N sets — the "cadence" at which the coach should surface a
    /// safety-focused cue instead of (or alongside) a form cue.
    case every(Int)
    case never

    var cadence: Int? {
        if case .every(let n) = self { return n }
        return nil
    }

    /// Does a given 1-based set index fall on the cadence?
    func fires(onSetIndex setIndex: Int) -> Bool {
        guard let cadence, cadence > 0, setIndex >= 1 else { return false }
        return setIndex % cadence == 0 || setIndex == 1
    }
}

extension MovementLimitation {
    /// More severe limitation → more frequent safety callouts. The first set
    /// always fires so the user gets an opening safety cue when relevant.
    var safetyFrequency: SafetyFrequency {
        switch self {
        case .noLimitation:         return .every(4)
        case .mildDiscomfort:       return .every(3)
        case .moderateLimitation:   return .every(2)
        case .severe:               return .every(1)
        }
    }
}

// MARK: - Coaching Profile Context

/// Resolved, per-set coaching context derived from the user's onboarding
/// profile. Consumed by `OpenAICoachingManager` when phrasing a set's feedback.
struct CoachingProfileContext {

    let profile: ChironUserProfile
    let exerciseType: TrackedExerciseType
    /// 1-based index of the set just finished, within this exercise in the current session.
    let setIndex: Int

    /// Injury areas that apply to the current exercise. Primary is surfaced by
    /// name in the feedback string; the rest are summarized in the prompt.
    var relevantInjuries: [InjuryArea] {
        guard profile.hasInjuryConcerns else { return [] }
        return profile.injuryFlags
            .filter { $0.appliesTo(exerciseType) }
            // Stable order for prompt reproducibility.
            .sorted { $0.rawValue < $1.rawValue }
    }

    /// The single injury area the coach should mention by name, if any.
    var primaryInjury: InjuryArea? { relevantInjuries.first }

    /// True when the current exercise matches one of the user's flagged
    /// discomfort-movement patterns.
    var discomfortAppliesToExercise: Bool {
        guard profile.hasInjuryConcerns else { return false }
        return profile.discomfortMovements.contains { $0.appliesTo(exerciseType) }
    }

    /// Whether safety feedback should be injected this set. Requires both
    /// (a) relevant injury or discomfort, and (b) the movement-limitation
    /// cadence to fire for this `setIndex`.
    var injectSafetyThisSet: Bool {
        guard !relevantInjuries.isEmpty || discomfortAppliesToExercise else { return false }
        let limit = profile.movementLimitation ?? .noLimitation
        return limit.safetyFrequency.fires(onSetIndex: setIndex)
    }

    // MARK: Experience / gender / age / size directives

    var experienceDirective: String {
        switch profile.experienceLevel {
        case .newToLifting:
            return "Athlete is NEW to lifting. Explain cues in plain language. Avoid jargon. Frame corrections as learning, not failure. Default to one simple cue rather than two."
        case .someExperience:
            return "Athlete has some experience. Keep cues direct and concrete. Mild technical language is OK."
        case .experienced:
            return "Athlete is experienced. Be precise and efficient; skip explanations they already know. Short technical cues are welcome."
        }
    }

    var genderDirective: String? {
        switch profile.gender {
        case .female:
            // Adjust for anatomical differences that routinely change movement
            // patterns: wider Q-angle tends to track the knees inward on
            // squats and lunges, and glute-dominant hinges often benefit from
            // different cueing than hip-drive-first hinges common in male
            // lifters. Keep the rule short — the LLM will localize it.
            return "Athlete is female. Account for a wider Q-angle (knees may track slightly different on squats/hinges) and glute-dominant mechanics. Do not assume male-default leverages."
        case .male, .nonBinary, .preferNotToSay:
            return nil
        }
    }

    var ageDirective: String? {
        guard profile.isOlderLifter else { return nil }
        return "Athlete is \(profile.age). Lead with what went well. Be warm, patient, and forgiving — never scolding. Suggest smaller adjustments rather than aggressive corrections."
    }

    var anthropometryDirective: String? {
        var notes: [String] = []
        if profile.isTallLifter {
            notes.append("tall (longer levers — hip/ankle depth and torso position are harder to achieve)")
        }
        if profile.isHeavyLifter {
            notes.append("heavier-bodied (range of motion and balance can be more work)")
        }
        guard !notes.isEmpty else { return nil }
        return "Athlete is \(notes.joined(separator: " and ")). Be forgiving about depth/lean thresholds; acknowledge that mobility may simply look different. Avoid implying they are doing it wrong when their anatomy is the driver."
    }

    // MARK: Injury / safety directives

    var injuryDirective: String? {
        guard profile.hasInjuryConcerns else { return nil }
        guard !relevantInjuries.isEmpty else { return nil }

        let names = relevantInjuries.map { $0.coachingNoun }.joined(separator: ", ")
        let otherDetail: String = {
            guard relevantInjuries.contains(.other),
                  !profile.injuryOtherDescription.trimmingCharacters(in: .whitespaces).isEmpty
            else { return "" }
            return " (other: \"\(profile.injuryOtherDescription)\")"
        }()

        let severity = profile.movementLimitation ?? .noLimitation
        let severityClause: String = {
            switch severity {
            case .noLimitation:         return "The limitation is mostly awareness."
            case .mildDiscomfort:       return "There is mild discomfort — be gentle."
            case .moderateLimitation:   return "Moderate limitation — lean strongly toward safety over strict form."
            case .severe:               return "Severe limitation — PRIORITIZE safety, explicitly permit pausing the set if it hurts, and avoid any push-harder language."
            }
        }()

        return "Athlete has flagged discomfort/injury in: \(names)\(otherDetail). \(severityClause)"
    }

    /// The sentence that should be included *this set* as the safety cue. Only
    /// set when `injectSafetyThisSet` is true.
    var safetyDirective: String? {
        guard injectSafetyThisSet else { return nil }
        let noun = primaryInjury?.coachingNoun ?? "any flagged area"
        let severity = profile.movementLimitation ?? .noLimitation

        switch severity {
        case .noLimitation:
            return "SAFETY CUE: mention the \(noun) once in a brief awareness line ('keep an eye on those \(noun)'). Stay encouraging."
        case .mildDiscomfort:
            return "SAFETY CUE: check in on the \(noun) by name. Keep it light — one short reassurance plus one gentle form cue."
        case .moderateLimitation:
            return "SAFETY CUE: name the \(noun) explicitly. Be forgiving about form — depth or range shortfalls are acceptable. If it hurts, back off."
        case .severe:
            return "SAFETY CUE: name the \(noun) explicitly. Be very lenient on form. Explicitly tell the athlete it is OK to stop or shorten the range if the \(noun) hurts. No 'push harder' language."
        }
    }

    // MARK: Tone (persona + intensity)

    var personaDirective: String {
        switch profile.coachPersona {
        case .drillSergeant:    return "Tone: drill sergeant. Blunt, direct, no filler. Never cruel — firm, not mean."
        case .technician:       return "Tone: technician. Precise, diagnostic, focused on mechanics."
        case .hypeFriend:       return "Tone: hype friend. Warm, energetic, celebrate the win before the correction."
        case .quietPro:         return "Tone: quiet pro. Minimal words. Only say what is necessary."
        }
    }

    var intensityDirective: String {
        let level = profile.coachIntensityLevel
        switch level {
        case .whisper:      return "Intensity: whisper. Very soft — understate every correction."
        case .gentle:       return "Intensity: gentle. Encouraging, low-pressure."
        case .balanced:     return "Intensity: balanced. Standard coaching pressure."
        case .assertive:    return "Intensity: assertive. Firm and direct."
        case .relentless:   return "Intensity: relentless. Push hard — but never at the expense of a safety directive if one is present."
        }
    }

    // MARK: Goal

    /// Reminds the model what the user is training for. Lets it slant praise
    /// toward the outcome they care about (e.g., "that depth is going to pay
    /// off for muscle growth").
    var goalDirective: String {
        "Primary goal: \(profile.topGoal.displayName.lowercased())."
    }

    // MARK: Assembled prompt block

    /// Newline-separated directive block the coaching manager folds into the
    /// LLM prompt. Returns `nil` when the profile contributes nothing
    /// actionable (older API compatibility path).
    var promptBlock: String? {
        var lines: [String] = []
        lines.append(goalDirective)
        lines.append(experienceDirective)
        if let genderDirective { lines.append(genderDirective) }
        if let ageDirective { lines.append(ageDirective) }
        if let anthropometryDirective { lines.append(anthropometryDirective) }
        if let injuryDirective { lines.append(injuryDirective) }
        if let safetyDirective { lines.append(safetyDirective) }
        lines.append(personaDirective)
        lines.append(intensityDirective)
        return lines.isEmpty ? nil : lines.joined(separator: "\n- ").prepending("- ")
    }

    // MARK: Deterministic fallback

    /// Short clause the deterministic fallback can prepend when the LLM path
    /// fails, so users still get the "by name" safety acknowledgement.
    var fallbackSafetyClause: String? {
        guard injectSafetyThisSet, let primary = primaryInjury else { return nil }
        let severity = profile.movementLimitation ?? .noLimitation
        switch severity {
        case .noLimitation, .mildDiscomfort:
            return "Keep an eye on those \(primary.coachingNoun)"
        case .moderateLimitation:
            return "Go easy on the \(primary.coachingNoun) — form first, depth second"
        case .severe:
            return "If the \(primary.coachingNoun) hurt, stop the set — no shame in backing off"
        }
    }
}

// MARK: - String helper

private extension String {
    /// Prefixes `prefix` onto the string — `"- "` + lines makes a bullet list.
    func prepending(_ prefix: String) -> String { prefix + self }
}
