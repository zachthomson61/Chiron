import XCTest
@testable import Chiron

/// Tests for the Stage 2 suppression gate.
///
/// Each test constructs a synthetic `BodyweightRepMetrics` array so the gate
/// runs on realistic inputs. We don't hit the LLM path here — we only verify
/// the deterministic Swift plan: for each suppression reason, we prove the
/// gate fires; and for the acceptance case (clean, strong set) we prove
/// `nextSetFocus` is nil.
final class SetEndFeedbackPlannerTests: XCTestCase {

    // MARK: - Helpers

    private func rep(
        _ timestamp: TimeInterval = 0,
        depthAtBottom: Float = 0.55,
        backAngleMax: Float = 20,
        kneeAlignmentWorstNearBottom: Float = 0.0,
        shallowDepth: Bool = false,
        excessiveForwardLean: Bool = false,
        kneeValgus: Bool = false,
        hipKneeDepthQualityMet: Bool = true,
        reducedDepthConfidence: Bool = false,
        valid: Bool = true
    ) -> BodyweightRepMetrics {
        BodyweightRepMetrics(
            depthAtBottom: depthAtBottom,
            backAngleMax: backAngleMax,
            kneeAlignmentWorstNearBottom: kneeAlignmentWorstNearBottom,
            shallowDepth: shallowDepth,
            excessiveForwardLean: excessiveForwardLean,
            kneeValgus: kneeValgus,
            hipKneeDepthQualityMet: hipKneeDepthQualityMet,
            reducedDepthConfidence: reducedDepthConfidence,
            valid: valid,
            timestamp: timestamp
        )
    }

    private func analysis(
        issues: [IssueCode] = [],
        overallScore: Float = 0.9,
        repCount: Int = 10,
        depth: Float = 0.55,
        backAngle: Float = 20,
        kneeAlignment: Float = 0.0
    ) -> FormAnalysis {
        FormAnalysis(
            depth: depth,
            backAngle: backAngle,
            kneeAlignment: kneeAlignment,
            overallScore: overallScore,
            issues: issues,
            summary: "test",
            repCount: repCount,
            avgEccentricMs: nil,
            avgPauseMs: nil,
            avgConcentricMs: nil,
            avgBottomDepth: nil,
            deepRepRatio: nil
        )
    }

    // MARK: - Acceptance case

    /// From the problem statement: every rep valid, mean overall ≥ 0.88, no
    /// issue in ≥30% of reps → nextSetFocus must be nil.
    func testAcceptance_cleanStrongSet_suppressesCritique() {
        // 10 reps, one lightly flagged for lean (10% of reps — below 30% floor).
        var reps = Array(repeating: rep(), count: 9)
        reps.append(rep(excessiveForwardLean: true))
        let metrics = SetEndAggregatedMetrics(
            issueCounts: [:],
            positiveCounts: [.goodDepth: 30, .chestTall: 25],
            bodyweightRepHistory: reps,
            overallScoreMean: 0.9
        )
        let plan = SetEndFeedbackPlanner.plan(
            formAnalysis: analysis(overallScore: 0.9, repCount: 10),
            aggregatedMetrics: metrics,
            exerciseType: .bodyweight,
            previousCueText: nil
        )
        XCTAssertNil(plan.nextSetFocus, "Clean strong set must not surface a next-set cue")
        XCTAssertEqual(plan.tone, .clean)
    }

    // MARK: - Thin evidence

    func testThinEvidence_singleFlaggedRepOutOfTen_suppresses() {
        // 10 reps, just 1 flagged → floor = max(2, ceil(0.3*10)=3). 1 < 3 ⇒ Stage 1 drops it.
        var reps = Array(repeating: rep(), count: 9)
        reps.append(rep(kneeValgus: true))
        let metrics = SetEndAggregatedMetrics(
            issueCounts: [:],
            positiveCounts: [:],
            bodyweightRepHistory: reps,
            overallScoreMean: 0.78
        )
        let plan = SetEndFeedbackPlanner.plan(
            formAnalysis: analysis(overallScore: 0.78, repCount: 10),
            aggregatedMetrics: metrics,
            exerciseType: .bodyweight,
            previousCueText: nil
        )
        XCTAssertNil(plan.nextSetFocus, "Below evidence floor must suppress")
        XCTAssertNil(plan.candidateIssue, "Stage 1 drops candidate before Stage 2")
        XCTAssertEqual(plan.tone, .clean)
    }

    // MARK: - Strong set + borderline

    func testStrongSet_borderlineEvidence_suppresses() {
        // 10 reps, 4 flagged (40% ⇒ passes 30% floor). Mean score 0.88 ⇒ strong.
        // 40% ≤ 30% + 15% borderline band = 45% ⇒ suppress.
        var reps: [BodyweightRepMetrics] = []
        for i in 0..<10 {
            reps.append(rep(excessiveForwardLean: i < 4))
        }
        let metrics = SetEndAggregatedMetrics(
            issueCounts: [:],
            positiveCounts: [.goodDepth: 30],
            bodyweightRepHistory: reps,
            overallScoreMean: 0.88
        )
        let plan = SetEndFeedbackPlanner.plan(
            formAnalysis: analysis(overallScore: 0.88, repCount: 10),
            aggregatedMetrics: metrics,
            exerciseType: .bodyweight,
            previousCueText: nil
        )
        XCTAssertEqual(plan.suppressionReason, .strongSetBorderline)
        XCTAssertNil(plan.nextSetFocus)
        XCTAssertEqual(plan.candidateIssue, .forwardLean,
                       "Candidate should still be recorded for telemetry")
    }

    func testStrongSet_heavyEvidence_stillSurfaces() {
        // Even a strong set should surface a critique when evidence is dominant (6/10 = 60%).
        var reps: [BodyweightRepMetrics] = []
        for i in 0..<10 {
            reps.append(rep(excessiveForwardLean: i < 6))
        }
        let metrics = SetEndAggregatedMetrics(
            issueCounts: [:],
            positiveCounts: [:],
            bodyweightRepHistory: reps,
            overallScoreMean: 0.88
        )
        let plan = SetEndFeedbackPlanner.plan(
            formAnalysis: analysis(overallScore: 0.88, repCount: 10),
            aggregatedMetrics: metrics,
            exerciseType: .bodyweight,
            previousCueText: nil
        )
        XCTAssertEqual(plan.tone, .corrective)
        XCTAssertEqual(plan.surfacedIssue, .forwardLean)
    }

    // MARK: - Contradicts best thing

    func testContradictsBestThing_depthPraiseVsDeepCritique_suppresses() {
        // 8 reps, 5 flagged shallow — that's above floor, but best thing is about depth.
        // Don't tell the user "squat deeper" right after "good depth".
        var reps: [BodyweightRepMetrics] = []
        for i in 0..<8 {
            reps.append(rep(shallowDepth: i < 5, hipKneeDepthQualityMet: i >= 5))
        }
        let metrics = SetEndAggregatedMetrics(
            issueCounts: [:],
            positiveCounts: [.goodDepth: 50],  // depth wins bestThing
            bodyweightRepHistory: reps,
            overallScoreMean: 0.7
        )
        let plan = SetEndFeedbackPlanner.plan(
            formAnalysis: analysis(overallScore: 0.7, repCount: 8),
            aggregatedMetrics: metrics,
            exerciseType: .bodyweight,
            previousCueText: nil
        )
        XCTAssertEqual(plan.suppressionReason, .contradictsBestThing)
        XCTAssertNil(plan.nextSetFocus)
        XCTAssertTrue(plan.bestThing.lowercased().contains("depth"))
    }

    // MARK: - Repeated unacted cue

    func testRepeatedUnactedCue_sameCueAsLastSet_suppresses() {
        // 8 reps with 5 valgus-flagged — evidence is real.
        // Previous set already said "Push your knees out over your toes" and
        // the issue hasn't abated. Suppress this time (next surface can escalate).
        var reps: [BodyweightRepMetrics] = []
        for i in 0..<8 {
            reps.append(rep(kneeValgus: i < 5))
        }
        let metrics = SetEndAggregatedMetrics(
            issueCounts: [:],
            positiveCounts: [:],
            bodyweightRepHistory: reps,
            overallScoreMean: 0.7
        )
        let plan = SetEndFeedbackPlanner.plan(
            formAnalysis: analysis(overallScore: 0.7, repCount: 8),
            aggregatedMetrics: metrics,
            exerciseType: .bodyweight,
            previousCueText: CoachingContract.cue(for: .kneeValgus)
        )
        XCTAssertEqual(plan.suppressionReason, .repeatedUnactedCue)
        XCTAssertNil(plan.nextSetFocus)
    }

    // MARK: - Single-rep artifact

    func testSingleRepArtifact_flaggedOnlyOnFirstRep_suppresses() {
        // 6 reps, only the first is flagged for shallowDepth. Absolute count is 1
        // below the min floor (2), so Stage 1 drops it before Stage 2. Still
        // no cue is surfaced — which is the correct user-facing behavior.
        var reps: [BodyweightRepMetrics] = []
        for i in 0..<6 {
            reps.append(rep(shallowDepth: i == 0, hipKneeDepthQualityMet: i != 0))
        }
        let metrics = SetEndAggregatedMetrics(
            issueCounts: [:],
            positiveCounts: [:],
            bodyweightRepHistory: reps,
            overallScoreMean: 0.8
        )
        let plan = SetEndFeedbackPlanner.plan(
            formAnalysis: analysis(overallScore: 0.8, repCount: 6),
            aggregatedMetrics: metrics,
            exerciseType: .bodyweight,
            previousCueText: nil
        )
        XCTAssertNil(plan.nextSetFocus, "Single-rep artifact must not surface a cue")
    }

    func testSingleRepArtifact_flaggedOnEndpointsOnly_suppresses() {
        // 6 reps, first and last flagged. 2 ≥ max(2, ceil(0.3·6)=2) ⇒ Stage 1
        // passes. Stage 2 must then recognize the endpoint concentration
        // (setup / rack artifact) and suppress.
        var reps: [BodyweightRepMetrics] = []
        for i in 0..<6 {
            let atEnd = (i == 0 || i == 5)
            reps.append(rep(kneeValgus: atEnd))
        }
        let metrics = SetEndAggregatedMetrics(
            issueCounts: [:],
            positiveCounts: [:],
            bodyweightRepHistory: reps,
            overallScoreMean: 0.7
        )
        let plan = SetEndFeedbackPlanner.plan(
            formAnalysis: analysis(overallScore: 0.7, repCount: 6),
            aggregatedMetrics: metrics,
            exerciseType: .bodyweight,
            previousCueText: nil
        )
        XCTAssertEqual(plan.suppressionReason, .singleRepArtifact)
        XCTAssertNil(plan.nextSetFocus)
    }

    // MARK: - Repeat-set non-safety gate

    /// The primary anti-overcoaching rule: on set 2 and beyond, form-only
    /// critiques (depth, knee tracking, tempo) must not surface. Only
    /// safety-critical issues should pass.
    func testRepeatSet_nonSafetyCritique_suppresses() {
        // 10 reps, 6 flagged kneeValgus — would normally surface on set 1,
        // but kneeValgus is form/optimization, not safety-critical.
        var reps: [BodyweightRepMetrics] = []
        for i in 0..<10 {
            reps.append(rep(kneeValgus: i < 6))
        }
        let metrics = SetEndAggregatedMetrics(
            issueCounts: [:],
            positiveCounts: [:],
            bodyweightRepHistory: reps,
            overallScoreMean: 0.7
        )
        let plan = SetEndFeedbackPlanner.plan(
            formAnalysis: analysis(overallScore: 0.7, repCount: 10),
            aggregatedMetrics: metrics,
            exerciseType: .bodyweight,
            previousCueText: nil,
            setIndex: 2
        )
        XCTAssertEqual(plan.suppressionReason, .nonSafetyCueOnRepeatSet)
        XCTAssertNil(plan.nextSetFocus)
        XCTAssertEqual(plan.tone, .clean)
    }

    /// Safety-critical cues must still pass on set 2+ — rounded back under
    /// load is an injury-imminent signal we never silence.
    func testRepeatSet_safetyCueStillSurfaces() {
        // 6 frames of rounded-back evidence on a deadlift; no per-rep
        // history (non-bodyweight exercise path).
        let metrics = SetEndAggregatedMetrics(
            issueCounts: [.deadliftRoundedBack: 6],
            positiveCounts: [:],
            bodyweightRepHistory: [],
            overallScoreMean: 0.6
        )
        let plan = SetEndFeedbackPlanner.plan(
            formAnalysis: analysis(
                issues: [.deadliftRoundedBack],
                overallScore: 0.6,
                repCount: 8
            ),
            aggregatedMetrics: metrics,
            exerciseType: .deadlift,
            previousCueText: nil,
            setIndex: 3
        )
        XCTAssertEqual(plan.tone, .corrective)
        XCTAssertEqual(plan.surfacedIssue, .deadliftRoundedBack)
        XCTAssertNil(plan.suppressionReason)
    }

    /// First set still honors the full two-stage gate — non-safety cues
    /// CAN surface here. This guards against over-tightening the repeat-set
    /// rule into a blanket suppression.
    func testFirstSet_nonSafetyCue_canStillSurface() {
        var reps: [BodyweightRepMetrics] = []
        for i in 0..<10 {
            reps.append(rep(kneeValgus: i < 6))
        }
        let metrics = SetEndAggregatedMetrics(
            issueCounts: [:],
            positiveCounts: [:],
            bodyweightRepHistory: reps,
            overallScoreMean: 0.7
        )
        let plan = SetEndFeedbackPlanner.plan(
            formAnalysis: analysis(overallScore: 0.7, repCount: 10),
            aggregatedMetrics: metrics,
            exerciseType: .bodyweight,
            previousCueText: nil,
            setIndex: 1
        )
        XCTAssertEqual(plan.tone, .corrective)
        XCTAssertEqual(plan.surfacedIssue, .kneeValgus)
    }

    // MARK: - BestThing always present

    func testBestThing_alwaysProduced_evenOnUglySet() {
        // Every rep flagged for something.
        let reps = Array(repeating: rep(
            shallowDepth: true,
            excessiveForwardLean: true,
            kneeValgus: true,
            hipKneeDepthQualityMet: false
        ), count: 5)
        let metrics = SetEndAggregatedMetrics(
            issueCounts: [:],
            positiveCounts: [:],
            bodyweightRepHistory: reps,
            overallScoreMean: 0.2
        )
        let plan = SetEndFeedbackPlanner.plan(
            formAnalysis: analysis(overallScore: 0.2, repCount: 5),
            aggregatedMetrics: metrics,
            exerciseType: .bodyweight,
            previousCueText: nil
        )
        XCTAssertFalse(plan.bestThing.isEmpty, "bestThing must always be populated")
    }
}
