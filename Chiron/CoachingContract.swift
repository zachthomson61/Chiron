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
    case insufficientDepth  = "insufficient_depth"
    case forwardLean        = "forward_lean"
    case kneeValgus         = "knee_valgus"
    case kneeVarus          = "knee_varus"
    case gripTooWide        = "grip_too_wide"
    case elbowsFlaring      = "elbows_flaring"
    case incompleteRom      = "incomplete_rom"
    case eccentricTooFast   = "eccentric_too_fast"
    case concentricTooSlow  = "concentric_too_slow"
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
            cue: "Sit deeper until hips reach knee level"
        ),
        .forwardLean: IssueDefinition(
            code: .forwardLean,
            displayName: "Forward Lean",
            severity: .high,
            cue: "Keep your chest tall and proud"
        ),
        .kneeValgus: IssueDefinition(
            code: .kneeValgus,
            displayName: "Knees Caving In",
            severity: .medium,
            cue: "Push your knees out over your toes"
        ),
        .kneeVarus: IssueDefinition(
            code: .kneeVarus,
            displayName: "Knees Bowing Out",
            severity: .low,
            cue: "Keep your knees tracking straight ahead"
        ),
        .gripTooWide: IssueDefinition(
            code: .gripTooWide,
            displayName: "Grip Too Wide",
            severity: .medium,
            cue: "Bring your grip in closer to your ribs"
        ),
        .elbowsFlaring: IssueDefinition(
            code: .elbowsFlaring,
            displayName: "Elbows Flaring",
            severity: .high,
            cue: "Tuck those elbows to your sides"
        ),
        .incompleteRom: IssueDefinition(
            code: .incompleteRom,
            displayName: "Incomplete ROM",
            severity: .medium,
            cue: "Lock out fully at the top and touch your chest at the bottom"
        ),
        .eccentricTooFast: IssueDefinition(
            code: .eccentricTooFast,
            displayName: "Eccentric Too Fast",
            severity: .medium,
            cue: "Take more time lowering the bar"
        ),
        .concentricTooSlow: IssueDefinition(
            code: .concentricTooSlow,
            displayName: "Concentric Too Slow",
            severity: .low,
            cue: "Press up a little faster"
        ),
    ]

    /// Global priority ordering — first element is highest priority.
    static let priorityOrder: [IssueCode] = [
        .insufficientDepth,
        .forwardLean,
        .elbowsFlaring,
        .kneeValgus,
        .gripTooWide,
        .incompleteRom,
        .eccentricTooFast,
        .kneeVarus,
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
        static let eccentricTooFast: Float = 0.6
        static let concentricTooSlow: Float = 0.6
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
        }
        return "controlled tempo"
    }
}
