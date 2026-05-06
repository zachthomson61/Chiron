//
//  SetEndFeedback.swift
//  Chiron
//
//  Two-stage set-end feedback pipeline.
//
//  Design note — silence on a clean set is a feature, not a gap.
//  The legacy pipeline forced a "good thing + critique" pair on every set,
//  so a clean set still got told to fix something. That trained users to
//  distrust the signal: if a correction always appears, real corrections
//  blur into the noise. This pipeline separates the cheap-and-safe positive
//  note (Stage 1 — always produced) from the critique (Stage 2 — gated by
//  a second pass that asks "will this cue actually help on the *next* set,
//  right now?"). When the gate suppresses, `nextSetFocus` is nil and the
//  UI/voice should treat that as a rewarding, confident outcome — not a
//  missing slot.
//
//  Stage 2 runs in Swift on aggregated metrics already in memory. The LLM
//  is not consulted for the gate decision — it only phrases the final
//  output, persona-aware, after the structured plan is fixed.
//

import Foundation

// MARK: - Positive key

/// Aggregated positive signals tracked across the current set. The pose
/// manager increments these per frame; the Stage 1 pass picks the highest
/// count as the best-thing anchor.
enum PositiveKey: String, Codable, CaseIterable {
    case goodDepth
    case chestTall
    case kneesOverToes
}

// MARK: - Feedback tone / output

enum FeedbackTone: String, Codable {
    case clean       // no critique surfaced — positive-only
    case corrective  // critique surfaced alongside the best thing
}

/// Reasons Stage 2 may suppress a candidate critique. Kept in telemetry so
/// future evaluation can measure which reasons fired and how the next set
/// actually went — this is the seed data for the progressive user model.
enum SetEndSuppressionReason: String, Codable {
    /// The candidate issue appeared in too few reps to be a pattern.
    case thinEvidence
    /// The set was already strong overall and the evidence was borderline.
    case strongSetBorderline
    /// The candidate contradicts the best thing (e.g. praise depth + cue deeper).
    case contradictsBestThing
    /// Identical cue was given on the previous set and the user hasn't acted on it.
    case repeatedUnactedCue
    /// Issue is concentrated in the first or last rep only (setup/rack artifact).
    case singleRepArtifact
    /// Second-or-later set of the same exercise and the candidate is not
    /// safety-critical. Repeating form-only cues on every set trains tune-out.
    case nonSafetyCueOnRepeatSet
    /// Set just hit a personal record and the candidate isn't safety-critical.
    /// PRs are a reward moment; form-optimization cues during celebration erode
    /// the signal. Safety-critical cues (spine-under-load etc.) still surface.
    case personalRecordCelebration
}

/// The complete set-end feedback emitted to the UI and voice layers.
struct SetEndFeedback: Codable, Equatable {
    /// Short positive note — always present. ≤12 words.
    let bestThing: String
    /// Optional next-set focus cue. Nil means Stage 2 suppressed the critique
    /// and this set is clean; render accordingly (rewarding affirmation, not
    /// an empty "areas to improve" slot). ≤14 words when present.
    let nextSetFocus: String?
    let tone: FeedbackTone
    /// LLM-phrased or deterministic spoken line for the voice coach.
    let spokenText: String
    /// Short 2–4 word cue for on-screen display between sets. Nil when clean.
    let displayShortCue: String?
    /// Debug seed — never shown in UI. Why did Stage 2 suppress, if it did?
    let suppressionReason: SetEndSuppressionReason?
    /// The candidate issue considered (even if suppressed) — useful for
    /// measuring whether suppressed cues later pattern out on their own.
    let candidateIssue: IssueCode?
}

// MARK: - Aggregated metrics input

/// Snapshot of per-set aggregation emitted by the on-device pose manager
/// at set-end. Stage 2 operates on this plus the final FormAnalysis.
struct SetEndAggregatedMetrics {
    /// Raw per-frame issue occurrence counts accumulated during the set.
    let issueCounts: [IssueCode: Int]
    /// Raw per-frame positive-signal counts accumulated during the set.
    let positiveCounts: [PositiveKey: Int]
    /// Per-valid-rep metrics. Empty for non-bodyweight exercises or when
    /// no rep committed cleanly.
    let bodyweightRepHistory: [BodyweightRepMetrics]
    /// Running mean of FormAnalysis.overallScore over the set.
    /// Nil when no frames were scored (degenerate set).
    let overallScoreMean: Float?

    static let empty = SetEndAggregatedMetrics(
        issueCounts: [:],
        positiveCounts: [:],
        bodyweightRepHistory: [],
        overallScoreMean: nil
    )

    var validReps: [BodyweightRepMetrics] {
        bodyweightRepHistory.filter(\.valid)
    }
}

// MARK: - Thresholds (tunable, named)

/// All Stage 2 thresholds live here so tuning is one-stop. Each value has
/// a documented rationale — change carefully.
enum SetEndFeedbackThreshold {
    /// Fraction of valid reps that must exhibit an issue before the gate
    /// treats it as a pattern. Below this, surface risks training the user
    /// to ignore real cues.
    static let evidenceFloorFraction: Float = 0.30

    /// Absolute minimum rep-occurrence count. Protects very short sets
    /// (3–5 reps) from triggering on a single flagged rep.
    static let evidenceMinAbsoluteCount: Int = 2

    /// Overall-score floor above which a set is considered "strong". A
    /// strong set with borderline evidence gets the clean-set treatment
    /// even if an issue squeaks past the evidence floor.
    static let cleanSetOverallScoreFloor: Float = 0.85

    /// Width of the "borderline" band above `evidenceFloorFraction`. If
    /// the issue-rate is within floor..floor+band and the set is strong,
    /// suppress.
    static let borderlineBandAbove: Float = 0.15

    /// Minimum total valid-rep count before single-rep-artifact detection
    /// is reliable. Below this, artifact logic is skipped (too few data
    /// points to tell pattern from edge).
    static let singleRepArtifactMinReps: Int = 4

    /// Set index (1-based) at which form-only critiques start being gated out.
    /// Set 1 is the one chance to deliver the cue; after that, stay silent
    /// unless the candidate is safety-critical.
    static let repeatSetSuppressFromIndex: Int = 2
}

// MARK: - Stage-1 + Stage-2 planner

/// Stage 1 identifies candidates (bestThing always, candidateCritique
/// conditionally). Stage 2 re-evaluates the candidate critique against the
/// full aggregated picture; if suppressed, the plan's tone becomes `.clean`.
enum SetEndFeedbackPlanner {

    struct Plan {
        let bestThing: String
        let candidateIssue: IssueCode?          // preserved for telemetry
        let surfacedIssue: IssueCode?           // nil when Stage 2 suppressed
        let suppressionReason: SetEndSuppressionReason?
        let tone: FeedbackTone

        /// Short on-screen cue (2–4 words) from the contract. Nil when clean.
        var displayShortCue: String? {
            guard let issue = surfacedIssue else { return nil }
            return CoachingContract.shortCue(for: issue)
        }

        /// Full next-set focus cue. Nil when clean.
        var nextSetFocus: String? {
            guard let issue = surfacedIssue else { return nil }
            return CoachingContract.cue(for: issue)
        }
    }

    /// Build the plan. Pure Swift — no LLM involvement at this stage.
    ///
    /// - Parameter setIndex: 1-based set index for this exercise in the
    ///   current session. On set 2 and beyond, non-safety-critical cues are
    ///   suppressed — the user already got the form cue once, and repeating
    ///   it every set trains them to tune the coach out. Safety-critical cues
    ///   (spine-under-load etc.) still surface on every set.
    /// - Parameter isPersonalRecord: true when this set just beat the user's
    ///   prior best for the exercise. PR sets suppress non-safety-critical
    ///   critiques so the celebration isn't diluted; safety-critical cues
    ///   still surface (a dangerous rep at a PR weight is the most important
    ///   moment to speak up).
    /// - Parameter weightIncreasedFromPrior: true when the user just put more
    ///   weight on the bar than the previous set of the same exercise in this
    ///   session. Adding load is exactly when form starts to break down (the
    ///   torso creeps upright on rows, the back rounds on deadlifts, depth
    ///   shortens on squats), so the "stay quiet on repeat sets" rule is
    ///   reversed: form-only cues that would normally be suppressed get
    ///   surfaced. Safety-critical cues already surface unconditionally —
    ///   this only changes the gating on non-safety cues.
    static func plan(
        formAnalysis: FormAnalysis,
        aggregatedMetrics: SetEndAggregatedMetrics,
        exerciseType: TrackedExerciseType,
        previousCueText: String?,
        setIndex: Int = 1,
        isPersonalRecord: Bool = false,
        weightIncreasedFromPrior: Bool = false
    ) -> Plan {
        let bestThing = stage1BestThing(
            formAnalysis: formAnalysis,
            aggregatedMetrics: aggregatedMetrics,
            exerciseType: exerciseType
        )

        let candidate = stage1CandidateIssue(
            formAnalysis: formAnalysis,
            aggregatedMetrics: aggregatedMetrics
        )

        guard let candidate else {
            return Plan(
                bestThing: bestThing,
                candidateIssue: nil,
                surfacedIssue: nil,
                suppressionReason: nil,
                tone: .clean
            )
        }

        let suppression = stage2GateDecision(
            candidate: candidate,
            formAnalysis: formAnalysis,
            aggregatedMetrics: aggregatedMetrics,
            bestThing: bestThing,
            previousCueText: previousCueText,
            setIndex: setIndex,
            isPersonalRecord: isPersonalRecord,
            weightIncreasedFromPrior: weightIncreasedFromPrior
        )

        return Plan(
            bestThing: bestThing,
            candidateIssue: candidate,
            surfacedIssue: suppression == nil ? candidate : nil,
            suppressionReason: suppression,
            tone: suppression == nil ? .corrective : .clean
        )
    }

    // MARK: Stage 1 — best thing

    static func stage1BestThing(
        formAnalysis: FormAnalysis,
        aggregatedMetrics: SetEndAggregatedMetrics,
        exerciseType: TrackedExerciseType
    ) -> String {
        // Preference 1: most-frequent positive-count key.
        if let topPositive = aggregatedMetrics.positiveCounts
            .max(by: { $0.value < $1.value })?.key,
           (aggregatedMetrics.positiveCounts[topPositive] ?? 0) > 0 {
            return positivePhrase(for: topPositive)
        }

        // Preference 2: for bodyweight, fall back to rep-history ratios.
        let valid = aggregatedMetrics.validReps
        if !valid.isEmpty {
            let depthQualityRatio =
                Float(valid.filter(\.hipKneeDepthQualityMet).count) / Float(valid.count)
            let leanFreeRatio =
                Float(valid.filter { !$0.excessiveForwardLean }.count) / Float(valid.count)
            let valgusFreeRatio =
                Float(valid.filter { !$0.kneeValgus }.count) / Float(valid.count)

            // Highest-ratio wins; ties prefer depth > chest > knees.
            let candidates: [(PositiveKey, Float)] = [
                (.goodDepth, depthQualityRatio),
                (.chestTall, leanFreeRatio),
                (.kneesOverToes, valgusFreeRatio)
            ]
            if let best = candidates.max(by: { $0.1 < $1.1 }), best.1 >= 0.7 {
                return positivePhrase(for: best.0)
            }
        }

        // Preference 3: use the contract's detector over the final analysis.
        if let note = CoachingLogic.detectPositiveNote(
            analysis: formAnalysis, exerciseType: exerciseType
        ) {
            return note
        }

        // Last-resort generic praise — always safe.
        return "controlled tempo"
    }

    private static func positivePhrase(for key: PositiveKey) -> String {
        switch key {
        case .goodDepth:     return "good depth on that set"
        case .chestTall:     return "chest stayed nice and tall"
        case .kneesOverToes: return "knees tracked well over your toes"
        }
    }

    // MARK: Stage 1 — candidate critique

    /// Returns the most-frequent issue from either the rep history (for
    /// bodyweight) or `issueCounts` (otherwise), subject to the evidence
    /// floor. Returns nil when no issue clears the floor — Stage 2 is
    /// then skipped entirely and the set is clean by construction.
    static func stage1CandidateIssue(
        formAnalysis: FormAnalysis,
        aggregatedMetrics: SetEndAggregatedMetrics
    ) -> IssueCode? {
        // Per-rep counts when available — these are semantically cleaner
        // than per-frame issueCounts for "how often is this a pattern".
        let valid = aggregatedMetrics.validReps
        if !valid.isEmpty {
            let perIssue: [(IssueCode, Int)] = [
                (.insufficientDepth, valid.filter(\.shallowDepth).count),
                (.forwardLean,       valid.filter(\.excessiveForwardLean).count),
                (.kneeValgus,        valid.filter(\.kneeValgus).count)
            ]
            if let top = perIssue.max(by: { $0.1 < $1.1 }), top.1 > 0 {
                if meetsFloor(count: top.1, totalReps: valid.count) {
                    return top.0
                }
                return nil
            }
            return nil
        }

        // Non-bodyweight fallback: use raw issueCounts. Without per-rep
        // data we treat the count relative to analysis.repCount.
        if let top = aggregatedMetrics.issueCounts.max(by: { $0.value < $1.value }),
           top.value > 0 {
            let reps = max(formAnalysis.repCount, 1)
            if meetsFloor(count: top.value, totalReps: reps) {
                return top.key
            }
            return nil
        }

        // Final fallback — the final analysis listed issues but per-set
        // aggregation is empty. This is rare; honor the analysis.
        return formAnalysis.issues.first
    }

    private static func meetsFloor(count: Int, totalReps: Int) -> Bool {
        guard totalReps > 0 else { return false }
        let fractionFloor = Int(
            ceil(Double(SetEndFeedbackThreshold.evidenceFloorFraction) * Double(totalReps))
        )
        let floor = max(SetEndFeedbackThreshold.evidenceMinAbsoluteCount, fractionFloor)
        return count >= floor
    }

    // MARK: Stage 2 — is this cue actually helpful right now?

    static func stage2GateDecision(
        candidate: IssueCode,
        formAnalysis: FormAnalysis,
        aggregatedMetrics: SetEndAggregatedMetrics,
        bestThing: String,
        previousCueText: String?,
        setIndex: Int,
        isPersonalRecord: Bool = false,
        weightIncreasedFromPrior: Bool = false
    ) -> SetEndSuppressionReason? {
        // 0a) PR celebration: a set that just beat the user's prior best gets
        // celebration-only feedback. Form-optimization cues during a PR blunt
        // the reward signal — the user earned the moment. Safety-critical
        // issues (spine-under-load, collapsed hinge) still surface: a risky
        // rep at a new-PR weight is precisely when the coach needs to speak.
        if isPersonalRecord,
           !CoachingContract.isSafetyCritical(candidate) {
            return .personalRecordCelebration
        }

        // 0b) Second-and-later set of this exercise: only safety-critical cues
        // surface. The user already had set 1 to hear form cues; hammering
        // them on every subsequent set is overcoaching and erodes trust in
        // the signal. Safety cues (spine-under-load etc.) always pass.
        //
        // EXCEPTION — weight just went up from the prior set. Adding load is
        // exactly when form deteriorates (torso creeps upright on rows, back
        // rounds on deadlifts, depth shortens on squats), so the "quiet on
        // repeat sets" trade reverses: a form-only cue at heavier weight is
        // actionable, not noise. Surface it.
        if setIndex >= SetEndFeedbackThreshold.repeatSetSuppressFromIndex,
           !CoachingContract.isSafetyCritical(candidate),
           !weightIncreasedFromPrior {
            return .nonSafetyCueOnRepeatSet
        }

        let valid = aggregatedMetrics.validReps
        let relatedRepCount = relatedRepOccurrences(
            candidate: candidate,
            validReps: valid,
            issueCounts: aggregatedMetrics.issueCounts
        )
        let totalReps = valid.isEmpty
            ? max(formAnalysis.repCount, 1)
            : valid.count
        let evidenceRatio = Float(relatedRepCount) / Float(totalReps)

        // 1) Thin evidence — the floor is already applied in stage 1, but
        // double-check here: if somehow the candidate survives stage 1 with
        // under the min absolute count, suppress.
        if relatedRepCount < SetEndFeedbackThreshold.evidenceMinAbsoluteCount {
            return .thinEvidence
        }

        // 2) Strong set + borderline — a set with mean score ≥ floor and
        // evidence just above the floor deserves clean feedback.
        let mean = aggregatedMetrics.overallScoreMean ?? formAnalysis.overallScore
        let borderlineCeiling =
            SetEndFeedbackThreshold.evidenceFloorFraction
            + SetEndFeedbackThreshold.borderlineBandAbove
        if mean >= SetEndFeedbackThreshold.cleanSetOverallScoreFloor,
           evidenceRatio <= borderlineCeiling {
            return .strongSetBorderline
        }

        // 3) Contradicts best thing — don't praise depth and then say deeper.
        if bestThingContradicts(candidate: candidate, bestThing: bestThing) {
            return .contradictsBestThing
        }

        // 4) Repeated unacted cue — same cue as prior set, and issue rate
        // didn't fall below the floor (we're here, so the rate is above it).
        // Without prior-set metrics to compare, we treat a repeat as unacted
        // and suppress; the LLM prompt can escalate next time by rephrasing.
        if let prev = previousCueText, !prev.isEmpty {
            let candidateCue = CoachingContract.cue(for: candidate)
            if prev.caseInsensitiveCompare(candidateCue) == .orderedSame {
                return .repeatedUnactedCue
            }
        }

        // 5) Single-rep artifact — issue concentrated on first/last rep.
        if valid.count >= SetEndFeedbackThreshold.singleRepArtifactMinReps,
           relatedRepCount >= 1,
           isConcentratedOnEndpoints(candidate: candidate, validReps: valid) {
            return .singleRepArtifact
        }

        return nil
    }

    private static func relatedRepOccurrences(
        candidate: IssueCode,
        validReps: [BodyweightRepMetrics],
        issueCounts: [IssueCode: Int]
    ) -> Int {
        if !validReps.isEmpty {
            switch candidate {
            case .insufficientDepth: return validReps.filter(\.shallowDepth).count
            case .forwardLean:       return validReps.filter(\.excessiveForwardLean).count
            case .kneeValgus:        return validReps.filter(\.kneeValgus).count
            default: break
            }
        }
        return issueCounts[candidate] ?? 0
    }

    private static func bestThingContradicts(candidate: IssueCode, bestThing: String) -> Bool {
        let lc = bestThing.lowercased()
        let mentionsDepth = lc.contains("depth")
        let mentionsChest = lc.contains("chest") || lc.contains("tall") || lc.contains("proud")
        let mentionsKnees = lc.contains("knees") || lc.contains("tracked")
        let mentionsBack  = lc.contains("back") || lc.contains("spine") || lc.contains("flat")
        let mentionsHinge = lc.contains("hinge")

        switch candidate {
        case .insufficientDepth, .rdlShallowHinge:
            return mentionsDepth || mentionsHinge
        case .forwardLean:
            return mentionsChest
        case .kneeValgus, .kneeVarus, .rowKneeInternalRotation, .rdlExcessiveKneeBend:
            return mentionsKnees
        case .deadliftRoundedBack, .rowRoundedBack, .rdlRoundedBack:
            return mentionsBack
        default:
            return false
        }
    }

    private static func isConcentratedOnEndpoints(
        candidate: IssueCode,
        validReps: [BodyweightRepMetrics]
    ) -> Bool {
        guard validReps.count >= SetEndFeedbackThreshold.singleRepArtifactMinReps else {
            return false
        }
        let flagged: (BodyweightRepMetrics) -> Bool = {
            switch candidate {
            case .insufficientDepth: return { $0.shallowDepth }
            case .forwardLean:       return { $0.excessiveForwardLean }
            case .kneeValgus:        return { $0.kneeValgus }
            default:                 return { _ in false }
            }
        }()
        let flaggedIndices = validReps.enumerated()
            .compactMap { flagged($0.element) ? $0.offset : nil }
        guard !flaggedIndices.isEmpty else { return false }
        let lastIdx = validReps.count - 1
        let allOnEnds = flaggedIndices.allSatisfy { $0 == 0 || $0 == lastIdx }
        return allOnEnds
    }
}
