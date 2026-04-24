//
//  CoachingContract.swift
//  Chiron
//
//  Single source of truth for coaching issue definitions, severity, cues,
//  priority rules, and the deterministic logic layer that produces a PhrasingPayload.
//
//  Mirrors docs/coaching_contract.json. Swift and Python must stay in sync.
//
//  Pipeline: pose → metrics → flags → ranked issues → PhrasingPayload → LLM phrasing
//

import Foundation

// MARK: - Issue Code

/// Stable machine-readable identifiers for form issues.
/// Use these everywhere in logic and APIs; map to display text only at UI boundaries.
enum IssueCode: String, Codable, CaseIterable, Hashable {
    case insufficientDepth      = "insufficient_depth"
    case forwardLean            = "forward_lean"
    case kneeValgus             = "knee_valgus"
    case kneeVarus              = "knee_varus"
    case gripTooWide            = "grip_too_wide"
    case elbowsFlaring          = "elbows_flaring"
    case incompleteRom          = "incomplete_rom"
    case eccentricTooFast       = "eccentric_too_fast"
    case concentricTooSlow      = "concentric_too_slow"
    case insufficientStretchPause = "insufficient_stretch_pause"
    // Barbell row specific issues
    case rowMomentumDrive       = "row_momentum_drive"
    case rowRoundedBack         = "row_rounded_back"
    case rowKneeInternalRotation = "row_knee_internal_rotation"
    case rowElbowFlare          = "row_elbow_flare"
    // Deadlift specific issues
    case deadliftRoundedBack    = "deadlift_rounded_back"
    case deadliftHipShootUp     = "deadlift_hip_shoot_up"
    case deadliftHyperextension = "deadlift_hyperextension"
    case deadliftBarDrift       = "deadlift_bar_drift"
    // Romanian deadlift specific issues
    case rdlRoundedBack         = "rdl_rounded_back"
    case rdlExcessiveKneeBend   = "rdl_excessive_knee_bend"
    case rdlShallowHinge        = "rdl_shallow_hinge"
    case rdlBarDrift            = "rdl_bar_drift"
}

// MARK: - Severity

enum IssueSeverity: String, Codable {
    case high, medium, low
}

// MARK: - Issue Definition (contract entry)

struct IssueDefinition {
    let code: IssueCode
    let displayName: String
    let severity: IssueSeverity
    let cue: String
    /// Truncated 2-4 word cue for on-screen display between sets.
    let shortCue: String
}

// MARK: - Feedback State

/// Represents confidence / data-quality gates. When non-nil (other than `.normal`),
/// the LLM should produce a safe generic line or be skipped entirely.
enum FeedbackState: String, Codable {
    case normal                  = "normal"
    case confidenceLow           = "confidence_low"
    case insufficientVisibility  = "insufficient_visibility"
    case tooFewReps              = "too_few_reps"
    case metricsInconclusive     = "metrics_inconclusive"
}

// MARK: - Phrasing Payload

/// The **only** structured input the LLM receives for coaching phrasing.
/// No raw metrics — only pre-determined issue codes, a positive note, and metadata.
struct PhrasingPayload: Codable {
    let primaryIssue: IssueCode?
    let secondaryIssue: IssueCode?
    let positiveNote: String?
    let repCount: Int
    let feedbackState: FeedbackState

    func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}

// MARK: - Tempo Targets

/// Goal-derived tempo reference points. These are **not** pass/fail thresholds.
/// On-device issue detection flags only clear deviations (e.g. avgEccentric well
/// below `minEccentricMs`); the LLM at set end weighs rep number and context to
/// decide whether the deviation warrants a spoken cue.
///
/// When a field is `nil` the corresponding tempo phase is not coached for this
/// goal (e.g. build muscle treats concentric as "as fast as possible" — no cue
/// ever fires on concentric speed).
struct TempoTargets: Codable, Equatable {
    /// Eccentric floor. Below `minEccentricMs * 0.5` → `.eccentricTooFast`.
    let minEccentricMs: Float?
    /// Concentric ceiling. Above `maxConcentricMs * 1.5` → `.concentricTooSlow`.
    let maxConcentricMs: Float?
    /// Stretch-pause floor (hold at the bottom). Below
    /// `minStretchPauseMs * 0.6` → `.insufficientStretchPause`.
    ///
    /// Intentionally surfaced as a periodic reminder rather than a per-set
    /// critique. The "quiet after set 1" rule (non-safety-critical cues go
    /// silent on sets 2+) handles the cadence; the lenient 0.6 multiplier
    /// keeps mildly-short pauses from tripping it at all.
    let minStretchPauseMs: Float?
}

// MARK: - Coaching Contract (static registry)

/// Central registry mirroring `docs/coaching_contract.json`.
/// All threshold values, issue definitions, and priority ordering live here.
enum CoachingContract {

    // MARK: Issue Definitions

    static let definitions: [IssueCode: IssueDefinition] = [
        .insufficientDepth: IssueDefinition(
            code: .insufficientDepth,
            displayName: "Insufficient Depth",
            severity: .high,
            cue: "Sit deeper until hips reach knee level",
            shortCue: "Sit deeper"
        ),
        .forwardLean: IssueDefinition(
            code: .forwardLean,
            displayName: "Forward Lean",
            severity: .high,
            cue: "Keep your chest tall and proud",
            shortCue: "Chest up"
        ),
        .kneeValgus: IssueDefinition(
            code: .kneeValgus,
            displayName: "Knees Caving In",
            severity: .medium,
            cue: "Push your knees out over your toes",
            shortCue: "Knees out"
        ),
        .kneeVarus: IssueDefinition(
            code: .kneeVarus,
            displayName: "Knees Bowing Out",
            severity: .low,
            cue: "Keep your knees tracking straight ahead",
            shortCue: "Knees straight"
        ),
        .gripTooWide: IssueDefinition(
            code: .gripTooWide,
            displayName: "Grip Too Wide",
            severity: .medium,
            cue: "Bring your grip in closer to your ribs",
            shortCue: "Narrow your grip"
        ),
        .elbowsFlaring: IssueDefinition(
            code: .elbowsFlaring,
            displayName: "Elbows Flaring",
            severity: .high,
            cue: "Tuck those elbows to your sides",
            shortCue: "Tuck elbows in"
        ),
        .incompleteRom: IssueDefinition(
            code: .incompleteRom,
            displayName: "Incomplete ROM",
            severity: .medium,
            cue: "Lock out fully at the top and touch your chest at the bottom",
            shortCue: "Full range of motion"
        ),
        .eccentricTooFast: IssueDefinition(
            code: .eccentricTooFast,
            displayName: "Eccentric Too Fast",
            severity: .medium,
            cue: "Take more time lowering the bar",
            shortCue: "Slower on the way down"
        ),
        .concentricTooSlow: IssueDefinition(
            code: .concentricTooSlow,
            displayName: "Concentric Too Slow",
            severity: .low,
            cue: "Press up a little faster",
            shortCue: "Press up faster"
        ),
        .insufficientStretchPause: IssueDefinition(
            code: .insufficientStretchPause,
            displayName: "Insufficient Stretch Pause",
            severity: .low,
            cue: "Hold the stretch at the bottom for a full second",
            shortCue: "Pause at the bottom"
        ),
        // Barbell row
        .rowMomentumDrive: IssueDefinition(
            code: .rowMomentumDrive,
            displayName: "Using Momentum",
            severity: .high,
            cue: "Stay locked in that hinge and let your back do the pulling",
            shortCue: "Control the pull"
        ),
        .rowRoundedBack: IssueDefinition(
            code: .rowRoundedBack,
            displayName: "Rounded Back",
            severity: .high,
            cue: "Lift your chest and keep your spine flat",
            shortCue: "Flatten your back"
        ),
        .rowKneeInternalRotation: IssueDefinition(
            code: .rowKneeInternalRotation,
            displayName: "Knees Turning In",
            severity: .low,
            cue: "Point your toes and knees straight ahead",
            shortCue: "Knees straight"
        ),
        .rowElbowFlare: IssueDefinition(
            code: .rowElbowFlare,
            displayName: "Elbows Flaring Out",
            severity: .medium,
            cue: "Pull your elbows back toward your hips, not out to the sides",
            shortCue: "Elbows to hips"
        ),
        // Deadlift
        .deadliftRoundedBack: IssueDefinition(
            code: .deadliftRoundedBack,
            displayName: "Rounded Back",
            severity: .high,
            cue: "Keep your chest up and lock in that flat back",
            shortCue: "Flatten your back"
        ),
        .deadliftHipShootUp: IssueDefinition(
            code: .deadliftHipShootUp,
            displayName: "Hips Rising Too Fast",
            severity: .high,
            cue: "Push through your legs first so hips and shoulders rise together",
            shortCue: "Hips and shoulders together"
        ),
        .deadliftHyperextension: IssueDefinition(
            code: .deadliftHyperextension,
            displayName: "Leaning Back at Lockout",
            severity: .medium,
            cue: "Stand tall at the top without leaning back",
            shortCue: "Stand tall at lockout"
        ),
        .deadliftBarDrift: IssueDefinition(
            code: .deadliftBarDrift,
            displayName: "Bar Drifting Forward",
            severity: .medium,
            cue: "Keep the bar tight to your body the whole way up",
            shortCue: "Bar tight to body"
        ),
        // Romanian deadlift
        .rdlRoundedBack: IssueDefinition(
            code: .rdlRoundedBack,
            displayName: "Rounded Back",
            severity: .high,
            cue: "Keep your chest proud and spine flat as you hinge",
            shortCue: "Flatten your back"
        ),
        .rdlExcessiveKneeBend: IssueDefinition(
            code: .rdlExcessiveKneeBend,
            displayName: "Too Much Knee Bend",
            severity: .high,
            cue: "Keep your knees at a soft fixed bend — push your hips back instead",
            shortCue: "Softer knees"
        ),
        .rdlShallowHinge: IssueDefinition(
            code: .rdlShallowHinge,
            displayName: "Shallow Hinge",
            severity: .medium,
            cue: "Hinge deeper until you feel a stretch in your hamstrings",
            shortCue: "Hinge deeper"
        ),
        .rdlBarDrift: IssueDefinition(
            code: .rdlBarDrift,
            displayName: "Bar Drifting Away",
            severity: .medium,
            cue: "Keep the bar sliding along your thighs the whole way down",
            shortCue: "Bar against legs"
        ),
    ]

    /// Global priority ordering — first element is highest priority.
    static let priorityOrder: [IssueCode] = [
        .insufficientDepth,
        .forwardLean,
        .deadliftRoundedBack,
        .deadliftHipShootUp,
        .rdlRoundedBack,
        .rdlExcessiveKneeBend,
        .rowRoundedBack,
        .rowMomentumDrive,
        .elbowsFlaring,
        .kneeValgus,
        .deadliftHyperextension,
        .deadliftBarDrift,
        .rdlShallowHinge,
        .rdlBarDrift,
        .rowElbowFlare,
        .gripTooWide,
        .incompleteRom,
        .insufficientStretchPause,
        .eccentricTooFast,
        .kneeVarus,
        .rowKneeInternalRotation,
        .concentricTooSlow,
    ]

    // MARK: Thresholds (mirrors coaching_contract.json → metrics)

    enum Threshold {
        // Squat (hip-displacement / legLength scale)
        static let depthShallow: Float   = 0.30
        static let depthGood: Float      = 0.50
        static let forwardLean: Float    = 35.0   // degrees
        static let kneeValgus: Float     = -0.2
        static let kneeVarus: Float      = 0.2
        // Close-grip bench press
        static let gripTooWide: Float    = 0.6
        static let elbowsFlaring: Float  = 0.6
        static let incompleteRom: Float  = 0.6
        // Barbell row (score below this triggers the issue)
        static let rowMomentum: Float       = 0.55
        static let rowBackNeutral: Float    = 0.55
        static let rowKneeRotation: Float   = 0.55
        static let rowElbowFlare: Float     = 0.55
        // Barbell row hinge angle (degrees from horizontal)
        static let rowHingeTooUpright: Float = 55.0  // torso above this = momentum / standing up
        static let rowHingeIdealMin: Float   = 25.0  // ideal range 25-45°
        static let rowHingeIdealMax: Float   = 50.0
        // Barbell row elbow angle relative to torso midline (degrees)
        static let rowElbowFlareAngle: Float = 60.0
        // Deadlift (score below this triggers the issue)
        static let dlRoundedBack: Float       = 0.55
        static let dlHipShoot: Float          = 0.55
        static let dlHyperextension: Float    = 0.55
        static let dlBarDrift: Float          = 0.55
        // Deadlift spine angle: head-shoulder-hip (degrees) — below this = rounded
        static let dlSpineNeutralMin: Float   = 155.0
        static let dlSpineRoundedSevere: Float = 120.0
        // Deadlift lockout angle from vertical (degrees) — past this = hyperextending
        static let dlHyperextensionAngle: Float = 10.0
        // Deadlift hip-shoulder rise ratio — below this = hips shooting up
        static let dlHipShoulderRatioMin: Float = 0.6
        // Deadlift bar drift: wrist-to-hip horizontal offset / shoulder width — above this = bar drifting
        static let dlBarDriftRatio: Float      = 0.35
        // Romanian deadlift (score below this triggers the issue)
        static let rdlRoundedBack: Float       = 0.55
        static let rdlKneeBend: Float          = 0.55
        static let rdlShallowHinge: Float      = 0.55
        static let rdlBarDrift: Float          = 0.55
        // RDL spine angle: head-shoulder-hip (degrees) — same range as deadlift
        static let rdlSpineNeutralMin: Float   = 155.0
        static let rdlSpineRoundedSevere: Float = 120.0
        // RDL knee angle: ideal is 160-175° (slight soft bend). Below 140° = too much knee bend.
        static let rdlKneeAngleIdealMin: Float = 155.0
        static let rdlKneeAngleTooMuch: Float  = 135.0
        // RDL hinge depth: torso angle from vertical (degrees). Below this = not hinging deep enough.
        static let rdlHingeDepthMin: Float     = 50.0   // torso should pass 50° from vertical
        static let rdlHingeShallow: Float      = 35.0   // less than this = definitely shallow
        // RDL bar drift: wrist-to-thigh offset / shoulder width — above this = bar drifting
        static let rdlBarDriftRatio: Float     = 0.30
    }

    // MARK: Positive-note detection thresholds

    enum PositiveThreshold {
        static let goodDepth: Float        = 0.50
        static let chestTall: Float        = 25.0  // back angle ≤ this
        static let kneesTracking: Float    = 0.1   // |kneeAlignment| ≤ this
    }

    // MARK: Suppression rules

    static let maxIssuesInPayload = 2
    static let suppressSecondaryWhenPrimaryIsHigh = true
    static let praiseOnlyWhenNoIssues = true

    // MARK: Display helpers

    static func displayName(for code: IssueCode) -> String {
        definitions[code]?.displayName ?? code.rawValue
    }

    static func cue(for code: IssueCode) -> String {
        definitions[code]?.cue ?? ""
    }

    static func severity(for code: IssueCode) -> IssueSeverity {
        definitions[code]?.severity ?? .low
    }

    static func shortCue(for code: IssueCode) -> String {
        definitions[code]?.shortCue ?? ""
    }

    // MARK: Safety classification

    /// Whether this issue is safety-critical — i.e. failing to correct it
    /// materially raises injury risk (spine under load, collapsed hinge, etc.)
    /// rather than merely degrading form quality or ROM.
    ///
    /// This drives the "quiet after set 1" rule: on the second-and-later set of
    /// an exercise in a session, only safety-critical critiques surface. Form
    /// optimizations (depth, tempo, bar path) stay silent after the first cue —
    /// repeating them on every set trains the user to tune the coach out.
    static func isSafetyCritical(_ code: IssueCode) -> Bool {
        switch code {
        // Spine-under-load issues — disc / facet injury risk.
        case .deadliftRoundedBack,
             .rdlRoundedBack,
             .rowRoundedBack,
             .deadliftHipShootUp,
             .deadliftHyperextension:
            return true
        // Loaded-squat forward lean — lumbar shear under the bar.
        case .forwardLean:
            return true
        // Collapsed hinge converts an RDL into a bad squat — hamstring/back risk.
        case .rdlExcessiveKneeBend:
            return true
        // Form / optimization issues — important, but not injury-imminent.
        case .insufficientDepth,
             .kneeValgus,
             .kneeVarus,
             .gripTooWide,
             .elbowsFlaring,
             .incompleteRom,
             .eccentricTooFast,
             .concentricTooSlow,
             .insufficientStretchPause,
             .rowMomentumDrive,
             .rowKneeInternalRotation,
             .rowElbowFlare,
             .deadliftBarDrift,
             .rdlShallowHinge,
             .rdlBarDrift:
            return false
        }
    }
}

// MARK: - Deterministic Logic Layer

/// Flags → Ranked Issues → PhrasingPayload.
/// This is the single entry point that decides *what* to say; the LLM only decides *how* to say it.
enum CoachingLogic {

    // MARK: Build payload from FormAnalysis

    /// Converts a `FormAnalysis` into a `PhrasingPayload` that can be handed to the LLM.
    /// All decision-making (which issue is primary, suppression, praise-only) happens here.
    static func buildPayload(from analysis: FormAnalysis, exerciseType: TrackedExerciseType) -> PhrasingPayload {

        // Gate: confidence / data quality
        let feedbackState = determineFeedbackState(analysis: analysis)
        guard feedbackState == .normal else {
            return PhrasingPayload(
                primaryIssue: nil,
                secondaryIssue: nil,
                positiveNote: nil,
                repCount: analysis.repCount,
                feedbackState: feedbackState
            )
        }

        // Rank detected issues by contract priority
        let ranked = rankIssues(analysis.issues)

        // Apply suppression: if primary is high-severity, drop secondary
        let primary = ranked.first
        var secondary: IssueCode? = ranked.count > 1 ? ranked[1] : nil
        if let p = primary,
           CoachingContract.suppressSecondaryWhenPrimaryIsHigh,
           CoachingContract.severity(for: p) == .high {
            secondary = nil
        }

        // Determine positive note
        let positiveNote = detectPositiveNote(analysis: analysis, exerciseType: exerciseType)

        return PhrasingPayload(
            primaryIssue: primary,
            secondaryIssue: secondary,
            positiveNote: positiveNote,
            repCount: analysis.repCount,
            feedbackState: .normal
        )
    }

    // MARK: Feedback state gate

    static func determineFeedbackState(analysis: FormAnalysis) -> FeedbackState {
        if analysis.repCount <= 0 { return .tooFewReps }
        if analysis.overallScore < 0.08 { return .insufficientVisibility }
        if analysis.summary.isEmpty { return .metricsInconclusive }
        return .normal
    }

    // MARK: Issue ranking

    /// Sorts detected issues by the contract's global priority order, returns top N.
    static func rankIssues(_ issues: [IssueCode]) -> [IssueCode] {
        let priorityMap = Dictionary(
            uniqueKeysWithValues: CoachingContract.priorityOrder.enumerated().map { ($1, $0) }
        )
        let sorted = issues.sorted { (priorityMap[$0] ?? 999) < (priorityMap[$1] ?? 999) }
        return Array(sorted.prefix(CoachingContract.maxIssuesInPayload))
    }

    // MARK: Positive note detection

    static func detectPositiveNote(analysis: FormAnalysis, exerciseType: TrackedExerciseType) -> String? {
        switch exerciseType {
        case .bodyweight, .barbell:
            if analysis.depth >= CoachingContract.PositiveThreshold.goodDepth {
                return "good depth on that set"
            }
            if abs(analysis.backAngle) <= CoachingContract.PositiveThreshold.chestTall {
                return "chest stayed nice and tall"
            }
            if abs(analysis.kneeAlignment) <= CoachingContract.PositiveThreshold.kneesTracking {
                return "knees tracked well over your toes"
            }

        case .closeGripBenchPress, .benchPress:
            if analysis.issues.isEmpty {
                return "solid lockout at the top"
            }
            if let ecc = analysis.avgEccentricMs, ecc >= 800 {
                return "tempo stayed controlled"
            }

        case .row:
            // Back neutrality: back angle in the ideal hinge range (25-50°)
            if analysis.backAngle >= CoachingContract.Threshold.rowHingeIdealMin
                && analysis.backAngle <= CoachingContract.Threshold.rowHingeIdealMax
                && !analysis.issues.contains(.rowRoundedBack) {
                return "back stayed nice and flat"
            }
            // Stable hip position (no momentum issue)
            if !analysis.issues.contains(.rowMomentumDrive)
                && !analysis.issues.contains(.rowRoundedBack) {
                return "solid hip position throughout"
            }
            // Tight elbows (no elbow flare)
            if !analysis.issues.contains(.rowElbowFlare) {
                return "elbows stayed tight to your sides"
            }
            // No issues at all
            if analysis.issues.isEmpty {
                return "really clean rows"
            }

        case .deadlift:
            // Flat back throughout the pull
            if !analysis.issues.contains(.deadliftRoundedBack)
                && !analysis.issues.contains(.deadliftHipShootUp) {
                return "back stayed flat the whole way up"
            }
            // Hips and shoulders moved together
            if !analysis.issues.contains(.deadliftHipShootUp) {
                return "hips and shoulders moved together nicely"
            }
            // Clean lockout
            if !analysis.issues.contains(.deadliftHyperextension) {
                return "strong lockout position"
            }
            // Bar path
            if !analysis.issues.contains(.deadliftBarDrift) {
                return "bar stayed tight to your body"
            }
            // No issues at all
            if analysis.issues.isEmpty {
                return "really clean pulls"
            }

        case .romanianDeadlift:
            // Flat back with good hinge
            if !analysis.issues.contains(.rdlRoundedBack)
                && !analysis.issues.contains(.rdlExcessiveKneeBend) {
                return "smooth hip hinge with a flat back"
            }
            // Knees stayed soft
            if !analysis.issues.contains(.rdlExcessiveKneeBend) {
                return "knees stayed nice and soft without bending"
            }
            // Good depth
            if !analysis.issues.contains(.rdlShallowHinge) {
                return "good depth on that hinge"
            }
            // Bar path
            if !analysis.issues.contains(.rdlBarDrift) {
                return "bar stayed right against your legs"
            }
            // No issues at all
            if analysis.issues.isEmpty {
                return "textbook Romanian deadlifts"
            }
        }
        return "controlled tempo"
    }
}
