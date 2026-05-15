//
//  AccuracyFlagPayload.swift
//  Chiron
//
//  Payload schema for tester-reported set-tracking inaccuracies.
//
//  When the user marks a set as "rep count off", "coach feedback wrong",
//  or "both/other", the app captures the exact inputs the AI pipeline
//  saw — aggregated coach metrics, per-rep bodyweight history, smoothed
//  viewpoint bucket — and writes the bundle as JSON into the standard
//  telemetry pipeline (Pending → R2 via TelemetryUploader). This is the
//  ground-truth dataset for triaging "the coach said X but it was wrong".
//

import Foundation

/// What the tester is reporting went wrong with the set.
enum AccuracyFlagCategory: String, Codable {
    case repCountOff = "rep_count_off"
    case coachFeedbackWrong = "coach_feedback_wrong"
    case bothOrOther = "both_or_other"

    var displayTitle: String {
        switch self {
        case .repCountOff:        return "Rep Count Off"
        case .coachFeedbackWrong: return "Coach Feedback Wrong"
        case .bothOrOther:        return "Both / Other"
        }
    }

    var displayDescription: String {
        switch self {
        case .repCountOff:
            return "The rep count the app showed was wrong"
        case .coachFeedbackWrong:
            return "The spoken or written coaching cue was wrong"
        case .bothOrOther:
            return "Reps and feedback both off, or something else"
        }
    }
}

/// When the flag was raised — during the set in progress, or after the
/// last completed set finished phrasing.
enum AccuracyFlagPhase: String, Codable {
    case duringSet = "during_set"
    case afterSet  = "after_set"
}

// MARK: - Per-rep snapshot (bodyweight squats only)

/// Codable mirror of `BodyweightRepMetrics`. The source struct lives next
/// to the pose manager and is not Codable; this carries the same fields
/// across to the JSON payload.
struct AccuracyFlagRepMetricsJSON: Codable {
    let depthAtBottom: Float
    let backAngleMax: Float
    let kneeAlignmentWorstNearBottom: Float
    let shallowDepth: Bool
    let excessiveForwardLean: Bool
    let kneeValgus: Bool
    let hipKneeDepthQualityMet: Bool
    let reducedDepthConfidence: Bool
    let valid: Bool
    let timestamp: TimeInterval

    init(_ m: BodyweightRepMetrics) {
        self.depthAtBottom = m.depthAtBottom
        self.backAngleMax = m.backAngleMax
        self.kneeAlignmentWorstNearBottom = m.kneeAlignmentWorstNearBottom
        self.shallowDepth = m.shallowDepth
        self.excessiveForwardLean = m.excessiveForwardLean
        self.kneeValgus = m.kneeValgus
        self.hipKneeDepthQualityMet = m.hipKneeDepthQualityMet
        self.reducedDepthConfidence = m.reducedDepthConfidence
        self.valid = m.valid
        self.timestamp = m.timestamp
    }
}

// MARK: - Form analysis snapshot

struct AccuracyFlagFormAnalysisJSON: Codable {
    let depth: Float
    let backAngle: Float
    let kneeAlignment: Float
    let overallScore: Float
    let issues: [String]
    let summary: String
    let repCount: Int
    let avgEccentricMs: Float?
    let avgPauseMs: Float?
    let avgConcentricMs: Float?
    let avgBottomDepth: Float?
    let deepRepRatio: Float?

    init(_ a: FormAnalysis) {
        self.depth = a.depth
        self.backAngle = a.backAngle
        self.kneeAlignment = a.kneeAlignment
        self.overallScore = a.overallScore
        self.issues = a.issues.map { $0.rawValue }
        self.summary = a.summary
        self.repCount = a.repCount
        self.avgEccentricMs = a.avgEccentricMs
        self.avgPauseMs = a.avgPauseMs
        self.avgConcentricMs = a.avgConcentricMs
        self.avgBottomDepth = a.avgBottomDepth
        self.deepRepRatio = a.deepRepRatio
    }
}

// MARK: - Aggregated coach input

/// The aggregated set payload that went to OpenAICoachingManager — exactly
/// what the coach saw when it produced its line. If the coach said "you're
/// leaning forward" and the tester says it was wrong, this is the field
/// that lets you see what `backAngleMax` actually was.
struct AccuracyFlagAggregatedMetricsJSON: Codable {
    let issueCounts: [String: Int]
    let positiveCounts: [String: Int]
    let bodyweightRepHistory: [AccuracyFlagRepMetricsJSON]
    let overallScoreMean: Float?

    init(_ m: SetEndAggregatedMetrics) {
        self.issueCounts = Dictionary(uniqueKeysWithValues: m.issueCounts.map { ($0.key.rawValue, $0.value) })
        self.positiveCounts = Dictionary(uniqueKeysWithValues: m.positiveCounts.map { ($0.key.rawValue, $0.value) })
        self.bodyweightRepHistory = m.bodyweightRepHistory.map(AccuracyFlagRepMetricsJSON.init)
        self.overallScoreMean = m.overallScoreMean
    }
}

// MARK: - Coach output snapshot

/// The line the coach actually surfaced — spoken text, on-screen cue, the
/// suppression reason if Stage 2 muted the critique. Pair this with the
/// aggregated metrics above to see why the model said what it said.
struct AccuracyFlagCoachOutputJSON: Codable {
    let bestThing: String
    let nextSetFocus: String?
    let tone: String
    let spokenText: String
    let displayShortCue: String?
    let suppressionReason: String?
    let candidateIssue: String?

    init(_ f: SetEndFeedback) {
        self.bestThing = f.bestThing
        self.nextSetFocus = f.nextSetFocus
        self.tone = f.tone.rawValue
        self.spokenText = f.spokenText
        self.displayShortCue = f.displayShortCue
        self.suppressionReason = f.suppressionReason?.rawValue
        self.candidateIssue = f.candidateIssue?.rawValue
    }
}

// MARK: - Top-level payload

struct AccuracyFlagPayload: Codable {
    static let schemaVersion: Int = 1

    // Schema + identity
    let schemaVersion: Int
    let flagId: String
    let firebaseUserId: String
    let anonymousUUID: String

    // What the user reported
    let category: AccuracyFlagCategory
    let capturedDuring: AccuracyFlagPhase

    // When + which set
    let flaggedAtIso: String
    let setStartIso: String?
    let setEndIso: String?
    let setId: String
    let setIndexInSession: Int?

    // Exercise context (obvious — included for completeness)
    let exerciseType: String
    let exerciseName: String?
    let viewpointBucket: String
    let viewpointProfileName: String

    // What the app showed for rep count and what coaching produced
    let displayedRepCount: Int
    let coachAggregatedMetrics: AccuracyFlagAggregatedMetricsJSON?
    let coachFormAnalysis: AccuracyFlagFormAnalysisJSON?
    let coachOutput: AccuracyFlagCoachOutputJSON?
    let currentWeightLbs: Double?

    // App + device for triage
    let appVersion: String
    let appBuild: String
    let deviceModel: String
    let iosVersion: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case flagId = "flag_id"
        case firebaseUserId = "firebase_user_id"
        case anonymousUUID = "anonymous_uuid"
        case category
        case capturedDuring = "captured_during"
        case flaggedAtIso = "flagged_at_iso"
        case setStartIso = "set_start_iso"
        case setEndIso = "set_end_iso"
        case setId = "set_id"
        case setIndexInSession = "set_index_in_session"
        case exerciseType = "exercise_type"
        case exerciseName = "exercise_name"
        case viewpointBucket = "viewpoint_bucket"
        case viewpointProfileName = "viewpoint_profile_name"
        case displayedRepCount = "displayed_rep_count"
        case coachAggregatedMetrics = "coach_aggregated_metrics"
        case coachFormAnalysis = "coach_form_analysis"
        case coachOutput = "coach_output"
        case currentWeightLbs = "current_weight_lbs"
        case appVersion = "app_version"
        case appBuild = "app_build"
        case deviceModel = "device_model"
        case iosVersion = "ios_version"
    }
}
