//
//  TempoCoaching.swift
//  Chiron
//
//  Intra-set tempo coaching — value types shared by the on-device tempo layer in
//  `OnDevicePoseManager`. This layer is a *generic consumer of rep-phase events*: each
//  exercise's existing rep detector maps its internal phases onto three role-based
//  transitions (eccentric start / stretch reached / concentric start) plus the existing
//  rep-count moment, and the types here turn those into per-rep tempo measurements and
//  earned cue decisions.
//
//  Phase 1: `RepTempo`. Phase 2: intensity tiers, `TempoCoachingConfig`, and the
//  channel-agnostic `TempoCueGate`. Phase 3 adds the audio helper. Kept in its own file so
//  the 4.7k-line pose manager stays focused, so none of this can be confused with the
//  existing `sum*Ms` aggregates that feed the set-end `FormAnalysis` / LLM layer, and so
//  the gate logic stays unit-testable without the pose pipeline.
//

import Foundation

// MARK: - Per-Rep Tempo (Phase 1)

/// One completed rep's measured tempo, in milliseconds.
///
/// Produced by the intra-set tempo layer at each rep's count moment and held in new
/// properties (`lastRepTempo` / `recentRepTempos`). This is deliberately **separate** from
/// `sumEccentricMs` / `sumPauseMs` / `sumConcentricMs` / `tempoRepSamples`, which the
/// existing depth-based `updateTempoTracking` writes for the LLM set-end layer — the two
/// must never share storage, to avoid double-counting.
///
/// Phase definitions (see the per-exercise mapping in `OnDevicePoseManager`):
/// - `eccentricMs`  — loaded lowering: `stretchReached − eccentricStart`.
/// - `pauseMs`      — dwell in the deepest loaded stretch: `concentricStart − stretchReached`.
/// - `concentricMs` — the lift out of the stretch (not gated for cues; recorded for completeness).
///
/// A value of `0` for any field means that phase could not be measured for the rep (e.g. the
/// first pull of a concentric-first lift has no preceding eccentric, and concentric-first
/// lifts reach their stretch exactly at the count moment, so their `pauseMs` is always 0 —
/// the bottom dwell happens *after* the count and is handled live by the Phase 3 pause
/// channel). Downstream gating treats an unmeasured (`0`) eccentric/pause as "not a miss",
/// never as an infinitely-fast rep.
struct RepTempo {
    let eccentricMs: Double
    let pauseMs: Double
    let concentricMs: Double
    /// Phase 3 live-pause channel: the lift left the deepest stretch before `minPauseMs`.
    /// Only ever set for concentric-first lifts (row), where the bottom dwell happens after
    /// the count and `pauseMs` above can't carry it — the pause channel back-fills this onto
    /// the just-finalized rep when the next pull begins early. Eccentric-first lifts express
    /// bounces through `pauseMs` directly. `var` because it is stamped post-append.
    var bounced: Bool = false
}

// MARK: - Coaching Intensity (Phase 2)

/// Low / Medium / High tier bucketed from the onboarding 1–5 coaching-intensity slider
/// (`ChironUserProfile.coachIntensity`, surfaced in the UI as `CoachIntensityLevel`:
/// Whisper/Gentle → low, Balanced → medium, Assertive/Relentless → high).
///
/// Intensity scales the whole tempo-feedback experience — deviation margins, the earned-cue
/// gate, back-off, cooldown, and which channels are active. The floor at every tier: cues
/// stay gated by both deviation and cooldown — never one cue per rep, never talking over a
/// form/safety cue (enforced at the Phase 3 speak site via `SpeechPriority.low` + the
/// shared cue de-dup).
enum CoachingIntensity {
    case low
    case medium
    case high

    /// Bucket the raw 1–5 slider value. Out-of-range values clamp like
    /// `CoachIntensityLevel.from(clamped:)` does.
    init(coachIntensity: Int) {
        switch coachIntensity {
        case ..<3:  self = .low
        case 3:     self = .medium
        default:    self = .high
        }
    }

    /// How far below `targetEccentricMs` a rep must land before it counts as off-target.
    /// Low only flags clearly-fast reps; High is tight.
    var eccentricMarginMs: Double {
        switch self {
        case .low:    return 600
        case .medium: return 400
        case .high:   return 250
        }
    }

    /// Fraction of `minPauseMs` below which the measured pause counts as a miss.
    /// Low ≈ "only if essentially no pause"; the 0.25 floor also absorbs the ~0.1–0.2 s
    /// systematic undercount from the stretch-stamp deadband.
    var pauseMissFraction: Double {
        switch self {
        case .low:    return 0.25
        case .medium: return 0.60
        case .high:   return 0.85
        }
    }

    /// Earned-cue gate: `deviating` of the last `window` reps must miss the same way.
    /// `window` never exceeds 4 — `recentRepTempos` is capped to match.
    var triggerReps: (deviating: Int, window: Int) {
        switch self {
        case .low:    return (deviating: 3, window: 4)
        case .medium: return (deviating: 2, window: 3)
        case .high:   return (deviating: 2, window: 2)
        }
    }

    /// Consecutive on-target reps after which tempo cues go quiet (Low backs off fast,
    /// High stays vigilant).
    var quietAfterGoodReps: Int {
        switch self {
        case .low:    return 1
        case .medium: return 2
        case .high:   return 3
        }
    }

    /// Minimum spacing between spoken tempo cues (enforced at the Phase 3 speak site).
    var verbalCooldown: TimeInterval {
        switch self {
        case .low:    return 12
        case .medium: return 8
        case .high:   return 5
        }
    }

    /// Low intensity is tone/HUD only — no spoken tempo cues.
    var verbalEnabled: Bool {
        switch self {
        case .low:            return false
        case .medium, .high:  return true
        }
    }
}

// MARK: - Cue Decision (Phase 2)

/// The tempo deviation a cue addresses. Cases are deliberately few — tempo coaching only
/// ever nudges the two hypertrophy levers (controlled eccentric, loaded-stretch pause).
enum TempoCueKind {
    case eccentricTooFast
    case noPause
}

/// Channel-agnostic cue decision returned by `TempoCueGate.evaluate`. The verbal channel
/// speaks `phrase` (subject to `verbalEnabled` + cooldown + de-dup at the speak site);
/// non-verbal channels key off `kind`.
struct TempoCueDecision {
    let kind: TempoCueKind
    let phrase: String
}

/// Persona-flavored phrase map. Persona affects *only* the phrasing string — no logic
/// branches on it. All phrases are literal one-liners (no similes; see `stripSimiles`).
func tempoCuePhrase(for kind: TempoCueKind, persona: CoachPersona) -> String {
    switch kind {
    case .eccentricTooFast:
        switch persona {
        case .drillSergeant: return "Control it down."
        case .technician:    return "Slower on the way down."
        case .hypeFriend:    return "Smooth and slow on the way down."
        case .quietPro:      return "Slower down."
        }
    case .noPause:
        switch persona {
        case .drillSergeant: return "Hold the bottom."
        case .technician:    return "Pause at the bottom."
        case .hypeFriend:    return "Hold that stretch at the bottom."
        case .quietPro:      return "Pause at the bottom."
        }
    }
}

// MARK: - Tempo Coaching Config (Phase 2)

/// Per-set, per-exercise configuration for the intra-set tempo layer, built from the
/// onboarding profile (`UserProfileStore`) at set start. One config drives both cue
/// channels (post-rep verbal + bottom-stretch pause tone).
struct TempoCoachingConfig {
    /// True only when the user's onboarding goal is hypertrophy (`FitnessGoal.buildMuscle`)
    /// and the exercise is one of the five tempo-coached lifts. Everything is silent otherwise.
    var enabled: Bool
    var intensity: CoachingIntensity
    /// Phrasing only — never branch logic on it.
    var persona: CoachPersona
    /// Eccentric reference, floored at 2000 ms (hypertrophy default 2000–3000). Held at the
    /// floor rather than the LLM layer's 2500 ms reference so intensity margins measure from
    /// the "controlled eccentric ≥ 2 s" definition, not from the aspirational midpoint.
    var targetEccentricMs: Double
    /// Loaded-stretch pause reference. Per-exercise: RDL is capped at 600 ms because the RDL
    /// detector's bottom-dwell gate (`rdlMaxBottomDwell` = 0.8 s) rejects longer still holds
    /// as bar pickups — coaching users past it would train them into uncounted reps.
    var minPauseMs: Double
    var eccentricMarginMs: Double
    var pauseMissFraction: Double
    var triggerReps: (deviating: Int, window: Int)
    var quietAfterGoodReps: Int
    var verbalCooldown: TimeInterval
    var verbalEnabled: Bool
    /// Bottom-stretch pause tone channel. Off for conventional deadlift by default — the
    /// floor reset is an unload, not a loaded stretch.
    var pauseToneEnabled: Bool
    /// Compensates the detectors' threshold truncation of the measured eccentric. The
    /// concentric-first detectors count the rep at a mid-lower threshold (deadlift: hip
    /// angle 115°, row: elbow 150°), so their measured eccentric is ~65–70% of the true
    /// lower (sim-verified); eccentric cutoffs scale by this so controlled lowers aren't
    /// flagged as fast.
    var eccentricMeasurementScale: Double
    /// True for eccentric-first lifts, where the bottom pause completes before the rep
    /// counts and `RepTempo.pauseMs` is real. Concentric-first lifts always report 0 there
    /// (the dwell happens after the count); their pause coaching runs live in the Phase 3
    /// tone channel instead, so the gate must not read their `pauseMs`.
    var pauseMeasurableAtRepCount: Bool

    /// Inert config — used before the first build and for non-coached goals/exercises.
    static let disabled = TempoCoachingConfig(
        enabled: false,
        intensity: .medium,
        persona: .technician,
        targetEccentricMs: 2000,
        minPauseMs: 1000,
        eccentricMarginMs: 400,
        pauseMissFraction: 0.60,
        triggerReps: (deviating: 2, window: 3),
        quietAfterGoodReps: 2,
        verbalCooldown: 8,
        verbalEnabled: false,
        pauseToneEnabled: false,
        eccentricMeasurementScale: 1.0,
        pauseMeasurableAtRepCount: false
    )

    /// Whether the persisted onboarding goal *suggests* tempo coaching should default on
    /// (hypertrophy). This is the DEFAULT for the user-facing toggle, not the gate itself —
    /// the toggle (`userEnabled` in `build`) is authoritative, so a user whose goal store says
    /// otherwise can still turn coaching on. `nil` profile → no suggestion.
    static func goalSuggestsCoaching(profile: ChironUserProfile?) -> Bool {
        profile?.topGoal == .buildMuscle
    }

    /// Builds the active config for one set.
    /// - `userEnabled`: the live master toggle. When false, the config is fully disabled
    ///   regardless of goal; when true, coaching runs on any coached lift. This replaces the
    ///   old goal-only gate so the feature is user-controllable (and so a stale onboarding
    ///   goal store can't silently suppress it). `nil` profile still → disabled (no persona /
    ///   intensity to drive cues).
    static func build(
        profile: ChironUserProfile?,
        exercise: TrackedExerciseType,
        userEnabled: Bool
    ) -> TempoCoachingConfig {
        guard let profile else { return .disabled }

        let intensity = CoachingIntensity(coachIntensity: profile.coachIntensity)

        // Per-exercise tuning (mapping table): pause tone, pause target, eccentric scale,
        // and whether RepTempo.pauseMs is meaningful at the count moment.
        let pauseToneEnabled: Bool
        let minPauseMs: Double
        let eccentricScale: Double
        let pauseMeasurable: Bool
        let coachedExercise: Bool
        switch exercise {
        case .bodyweight, .barbell:
            pauseToneEnabled = true;  minPauseMs = 1000; eccentricScale = 1.0
            pauseMeasurable = true;   coachedExercise = true
        case .romanianDeadlift:
            // Capped below the detector's 0.8 s bottom-dwell reject gate — see minPauseMs doc.
            pauseToneEnabled = true;  minPauseMs = 600;  eccentricScale = 1.0
            pauseMeasurable = true;   coachedExercise = true
        case .row:
            // Pause valid (bottom hang) but the signal is noisier under torso/bar occlusion —
            // conservative target; pause coaching is live-channel only (concentric-first).
            pauseToneEnabled = true;  minPauseMs = 800;  eccentricScale = 0.7
            pauseMeasurable = false;  coachedExercise = true
        case .deadlift:
            // Tone off by default: the floor reset is an unload, not a loaded stretch.
            pauseToneEnabled = false; minPauseMs = 800;  eccentricScale = 0.7
            pauseMeasurable = false;  coachedExercise = true
        case .benchPress, .closeGripBenchPress:
            pauseToneEnabled = false; minPauseMs = 1000; eccentricScale = 1.0
            pauseMeasurable = false;  coachedExercise = false
        }

        return TempoCoachingConfig(
            enabled: userEnabled && coachedExercise,
            intensity: intensity,
            persona: profile.coachPersona,
            targetEccentricMs: 2000,  // the spec floor; any future per-goal base must be max(2000, base)
            minPauseMs: minPauseMs,
            eccentricMarginMs: intensity.eccentricMarginMs,
            pauseMissFraction: intensity.pauseMissFraction,
            triggerReps: intensity.triggerReps,
            quietAfterGoodReps: intensity.quietAfterGoodReps,
            verbalCooldown: intensity.verbalCooldown,
            verbalEnabled: intensity.verbalEnabled,
            pauseToneEnabled: pauseToneEnabled,
            eccentricMeasurementScale: eccentricScale,
            pauseMeasurableAtRepCount: pauseMeasurable
        )
    }
}

// MARK: - Earned-Cue Gate (Phase 2)

/// Channel-agnostic decision function, reused by both cue channels. Pure — no pose-pipeline
/// state — so the gating rules are unit-testable in isolation.
enum TempoCueGate {

    /// Evaluates the most recent rep window against the config's earned-cue gate.
    ///
    /// `recent` is the last-N rep tempos **ending with the just-counted rep** (the manager
    /// passes `recentRepTempos`, capped at 4 — the Low-intensity window). Returns a decision
    /// only when:
    /// - the config is enabled, and
    /// - the freshest *assessable* rep itself misses (never scold a rep the user just fixed):
    ///   the latest rep for the eccentric check and for measurable pauses; the second-to-last
    ///   for concentric-first bounce info, which back-fills one pull behind, and
    /// - `triggerReps.deviating` of the last `triggerReps.window` reps miss the same way, and
    /// - the last `quietAfterGoodReps` reps are not all on-target.
    ///
    /// Unmeasured phases (`eccentricMs == 0`, `pauseMs == 0`) are never misses — a genuine
    /// bounce still measures a real >0 pause, and a first pull / dive-rep measures exactly 0.
    /// Cooldown and de-dup are enforced at the speak site, not here — the tone/HUD channels
    /// share this decision but have their own pacing.
    static func evaluate(recent: [RepTempo], config: TempoCoachingConfig) -> TempoCueDecision? {
        guard config.enabled, let latest = recent.last else { return nil }

        func eccentricMiss(_ t: RepTempo) -> Bool {
            guard t.eccentricMs > 0 else { return false }  // unmeasured — never a miss
            let cutoff = (config.targetEccentricMs - config.eccentricMarginMs) * config.eccentricMeasurementScale
            return t.eccentricMs < cutoff
        }
        func pauseMiss(_ t: RepTempo) -> Bool {
            guard config.pauseToneEnabled else { return false }
            // Live-channel bounce (concentric-first): the hang after the count ended before
            // the pause target. Binary and conservative — a bounce only marks when the hold
            // clearly never happened, which matches the Low-tier "essentially no pause" bar.
            if t.bounced { return true }
            guard config.pauseMeasurableAtRepCount else { return false }
            guard t.pauseMs > 0 else { return false }      // unmeasured — never a miss
            return t.pauseMs < config.minPauseMs * config.pauseMissFraction
        }
        func onTarget(_ t: RepTempo) -> Bool { !eccentricMiss(t) && !pauseMiss(t) }

        // Back-off: once the last `quietAfterGoodReps` reps are on-target, stay quiet even
        // if older misses still sit in the trigger window.
        let quietWindow = recent.suffix(config.quietAfterGoodReps)
        if quietWindow.count >= config.quietAfterGoodReps, quietWindow.allSatisfy(onTarget) {
            return nil
        }

        let window = recent.suffix(config.triggerReps.window)
        let eccentricMisses = window.filter(eccentricMiss).count
        let pauseMisses = window.filter(pauseMiss).count

        // Pause-channel "latest": for concentric-first lifts the just-appended rep's bounce
        // state is unknowable at its own count moment (the back-fill happens when the *next*
        // pull tops), so requiring the latest element to miss would make `.noPause`
        // unreachable there. The freshest pause-assessed rep is the second-to-last instead.
        // Eccentric-first lifts carry a real `pauseMs` at count time and use the latest rep.
        let latestPauseAssessed = config.pauseMeasurableAtRepCount ? latest : recent.dropLast().last

        // Eccentric first when both trigger — the controlled eccentric is the primary
        // hypertrophy lever, and slowing the descent usually restores the pause too.
        if eccentricMiss(latest), eccentricMisses >= config.triggerReps.deviating {
            return TempoCueDecision(
                kind: .eccentricTooFast,
                phrase: tempoCuePhrase(for: .eccentricTooFast, persona: config.persona)
            )
        }
        if let assessed = latestPauseAssessed, pauseMiss(assessed),
           pauseMisses >= config.triggerReps.deviating {
            return TempoCueDecision(
                kind: .noPause,
                phrase: tempoCuePhrase(for: .noPause, persona: config.persona)
            )
        }
        return nil
    }
}
