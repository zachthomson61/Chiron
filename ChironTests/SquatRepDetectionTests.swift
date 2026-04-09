import XCTest
@testable import Chiron

// MARK: - Standing Calibration Gate Tests

final class StandingCalibrationGateTests: XCTestCase {

    func testLocksAfterRequiredStableFrames() {
        var gate = StandingCalibrationGate(requiredFrames: 5, tolerance: 0.03)
        // Push 5 identical values
        for _ in 0..<4 {
            XCTAssertFalse(gate.push(1.0))
            XCTAssertNil(gate.lockedValue)
        }
        XCTAssertTrue(gate.push(1.0))
        XCTAssertEqual(gate.lockedValue, 1.0)
    }

    func testDoesNotLockOnSingleHighFrame() {
        var gate = StandingCalibrationGate(requiredFrames: 5, tolerance: 0.03)
        // 4 stable frames at 1.0
        for _ in 0..<4 { gate.push(1.0) }
        // Spike to 1.5 breaks the sequence
        gate.push(1.5)
        // 4 more at 1.0 — not enough yet
        for _ in 0..<4 { gate.push(1.0) }
        XCTAssertNil(gate.lockedValue, "Single noisy spike should reset the gate")
    }

    func testValuesWithinToleranceBandLock() {
        var gate = StandingCalibrationGate(requiredFrames: 5, tolerance: 0.03)
        // Values within 3% of 1.0
        gate.push(1.00)
        gate.push(1.01)
        gate.push(0.99)
        gate.push(1.005)
        let locked = gate.push(1.00)
        XCTAssertTrue(locked)
        // Should lock at the max within the band
        XCTAssertNotNil(gate.lockedValue)
        XCTAssertGreaterThanOrEqual(gate.lockedValue!, 1.0)
    }

    func testRecalibratesTallerStanding() {
        var gate = StandingCalibrationGate(requiredFrames: 3, tolerance: 0.03)
        // Lock at 1.0
        for _ in 0..<3 { gate.push(1.0) }
        XCTAssertEqual(gate.lockedValue, 1.0)

        // Now taller at 1.1 — should recalibrate
        for _ in 0..<3 { gate.push(1.1) }
        XCTAssertEqual(gate.lockedValue!, 1.1, accuracy: 0.02)
    }

    func testDoesNotDownCalibrate() {
        var gate = StandingCalibrationGate(requiredFrames: 3, tolerance: 0.03)
        // Lock at 1.0
        for _ in 0..<3 { gate.push(1.0) }
        XCTAssertEqual(gate.lockedValue, 1.0)

        // Shorter values should not overwrite
        for _ in 0..<5 { gate.push(0.8) }
        XCTAssertEqual(gate.lockedValue, 1.0, "Should not calibrate downward")
    }

    func testResetClearsEverything() {
        var gate = StandingCalibrationGate(requiredFrames: 3, tolerance: 0.03)
        for _ in 0..<3 { gate.push(1.0) }
        XCTAssertNotNil(gate.lockedValue)
        gate.reset()
        XCTAssertNil(gate.lockedValue)
    }
}

// MARK: - Viewpoint Classifier Tests

final class SquatViewpointClassifierTests: XCTestCase {

    // Helper: build an overlay dict for a standing person at various camera angles.
    // Y increases downward in overlay coords (0 = top of frame, 1 = bottom).
    // X range 0–1 (left to right).

    /// Chest-height side view: person roughly centered, body parts spread vertically,
    /// left/right pairs close together (side view = narrow pair width).
    func testChestSideClassification() {
        let overlay: [String: CGPoint] = [
            "nose":          CGPoint(x: 0.5, y: 0.15),
            "leftShoulder":  CGPoint(x: 0.49, y: 0.28),
            "rightShoulder": CGPoint(x: 0.51, y: 0.28),
            "leftHip":       CGPoint(x: 0.49, y: 0.52),
            "rightHip":      CGPoint(x: 0.51, y: 0.52),
            "leftKnee":      CGPoint(x: 0.49, y: 0.70),
            "rightKnee":     CGPoint(x: 0.51, y: 0.70),
            "leftAnkle":     CGPoint(x: 0.49, y: 0.88),
            "rightAnkle":    CGPoint(x: 0.51, y: 0.88),
            "leftWrist":     CGPoint(x: 0.49, y: 0.45),
            "rightWrist":    CGPoint(x: 0.51, y: 0.45),
        ]
        let confidence: [String: Float] = [
            "leftKnee": 0.9, "rightKnee": 0.9,
        ]

        let (height, _) = SquatViewpointClassifier.classifyCameraHeight(overlay: overlay)
        let (view, _) = SquatViewpointClassifier.classifyCameraView(overlay: overlay, confidence: confidence)

        XCTAssertEqual(height, .chest, "Chest-height: balanced torso/leg ratio")
        XCTAssertEqual(view, .side, "Side view: narrow pair widths")
    }

    /// Floor-front view: ankles low in frame (small Y), pairs wide (front view).
    func testFloorFrontClassification() {
        let overlay: [String: CGPoint] = [
            "nose":          CGPoint(x: 0.5, y: 0.10),
            "leftShoulder":  CGPoint(x: 0.38, y: 0.22),
            "rightShoulder": CGPoint(x: 0.62, y: 0.22),
            "leftHip":       CGPoint(x: 0.40, y: 0.42),
            "rightHip":      CGPoint(x: 0.60, y: 0.42),
            "leftKnee":      CGPoint(x: 0.38, y: 0.55),
            "rightKnee":     CGPoint(x: 0.62, y: 0.55),
            "leftAnkle":     CGPoint(x: 0.36, y: 0.64),
            "rightAnkle":    CGPoint(x: 0.64, y: 0.64),
            "leftWrist":     CGPoint(x: 0.30, y: 0.35),
            "rightWrist":    CGPoint(x: 0.70, y: 0.35),
        ]
        let confidence: [String: Float] = [
            "leftKnee": 0.9, "rightKnee": 0.9,
        ]

        let (height, _) = SquatViewpointClassifier.classifyCameraHeight(overlay: overlay)
        let (view, _) = SquatViewpointClassifier.classifyCameraView(overlay: overlay, confidence: confidence)

        XCTAssertEqual(height, .floor, "Floor: ankles high in frame, short torso ratio")
        XCTAssertEqual(view, .front, "Front view: wide pair widths")
    }

    /// Head-side view: shoulders lower in frame (larger Y), narrow widths.
    func testHeadSideClassification() {
        let overlay: [String: CGPoint] = [
            "nose":          CGPoint(x: 0.5, y: 0.38),
            "leftShoulder":  CGPoint(x: 0.49, y: 0.48),
            "rightShoulder": CGPoint(x: 0.51, y: 0.48),
            "leftHip":       CGPoint(x: 0.49, y: 0.62),
            "rightHip":      CGPoint(x: 0.51, y: 0.62),
            "leftKnee":      CGPoint(x: 0.49, y: 0.78),
            "rightKnee":     CGPoint(x: 0.51, y: 0.78),
            "leftAnkle":     CGPoint(x: 0.49, y: 0.92),
            "rightAnkle":    CGPoint(x: 0.51, y: 0.92),
            "leftWrist":     CGPoint(x: 0.49, y: 0.55),
            "rightWrist":    CGPoint(x: 0.51, y: 0.55),
        ]
        let confidence: [String: Float] = [
            "leftKnee": 0.9, "rightKnee": 0.9,
        ]

        let (height, _) = SquatViewpointClassifier.classifyCameraHeight(overlay: overlay)
        let (view, _) = SquatViewpointClassifier.classifyCameraView(overlay: overlay, confidence: confidence)

        XCTAssertEqual(height, .head, "Head-height: shoulders low in frame, long torso ratio")
        XCTAssertEqual(view, .side, "Side view: narrow pair widths")
    }

    /// Oblique view: moderate pair widths.
    func testChestObliqueClassification() {
        let overlay: [String: CGPoint] = [
            "nose":          CGPoint(x: 0.5, y: 0.15),
            "leftShoulder":  CGPoint(x: 0.44, y: 0.28),
            "rightShoulder": CGPoint(x: 0.56, y: 0.28),
            "leftHip":       CGPoint(x: 0.45, y: 0.52),
            "rightHip":      CGPoint(x: 0.55, y: 0.52),
            "leftKnee":      CGPoint(x: 0.44, y: 0.70),
            "rightKnee":     CGPoint(x: 0.56, y: 0.70),
            "leftAnkle":     CGPoint(x: 0.43, y: 0.88),
            "rightAnkle":    CGPoint(x: 0.57, y: 0.88),
            "leftWrist":     CGPoint(x: 0.42, y: 0.45),
            "rightWrist":    CGPoint(x: 0.58, y: 0.45),
        ]
        let confidence: [String: Float] = [
            "leftKnee": 0.9, "rightKnee": 0.9,
        ]

        let (height, _) = SquatViewpointClassifier.classifyCameraHeight(overlay: overlay)
        let (view, _) = SquatViewpointClassifier.classifyCameraView(overlay: overlay, confidence: confidence)

        XCTAssertEqual(height, .chest)
        XCTAssertEqual(view, .oblique, "Oblique: moderate pair widths between front and side")
    }
}

// MARK: - Viewpoint Smoother Tests

final class SquatViewpointSmootherTests: XCTestCase {

    func testPromotesAfterConsistentFrames() {
        var smoother = SquatViewpointSmoother(bufferSize: 10, promoteCount: 7, initial: .chest_side)
        XCTAssertEqual(smoother.activeBucket, .chest_side)

        // Push 7 consistent floor_front frames
        for i in 0..<7 {
            let changed = smoother.push(candidate: .floor_front)
            if i < 6 {
                XCTAssertFalse(changed)
            } else {
                XCTAssertTrue(changed)
            }
        }
        XCTAssertEqual(smoother.activeBucket, .floor_front)
    }

    func testDoesNotPromoteWithMixedInput() {
        var smoother = SquatViewpointSmoother(bufferSize: 10, promoteCount: 7, initial: .chest_side)

        // Alternate between two buckets
        for i in 0..<20 {
            let bucket: SquatViewpointBucket = (i % 2 == 0) ? .floor_front : .floor_side
            smoother.push(candidate: bucket)
        }
        XCTAssertEqual(smoother.activeBucket, .chest_side, "Mixed input should not promote")
    }

    func testUnknownFallsBackToChestSide() {
        var smoother = SquatViewpointSmoother(bufferSize: 10, promoteCount: 7, initial: .floor_front)

        // Push 7 unknown — should resolve to chest_side
        for _ in 0..<7 {
            smoother.push(candidate: .unknown)
        }
        XCTAssertEqual(smoother.activeBucket, .chest_side)
    }

    func testResetRestoresBucket() {
        var smoother = SquatViewpointSmoother(bufferSize: 10, promoteCount: 7, initial: .chest_side)
        for _ in 0..<7 { smoother.push(candidate: .head_side) }
        XCTAssertEqual(smoother.activeBucket, .head_side)

        smoother.reset(keepBucket: .chest_front)
        XCTAssertEqual(smoother.activeBucket, .chest_front)
    }
}

// MARK: - Rep Profile Table Tests

final class SquatRepProfileTableTests: XCTestCase {

    func testAllBucketsReturnProfile() {
        for bucket in SquatViewpointBucket.allCases {
            let profile = SquatRepProfileTable.profile(for: bucket)
            XCTAssertGreaterThan(profile.repBottomExcursionNormalized, 0,
                                 "Profile for \(bucket.rawValue) should have positive bottom excursion")
            XCTAssertGreaterThan(profile.minRepCycleDuration, 0)
            XCTAssertGreaterThan(profile.maxRepCycleDuration, profile.minRepCycleDuration)
        }
    }

    func testFloorProfilesHaveLowerExcursion() {
        let chestSide = SquatRepProfileTable.profile(for: .chest_side)
        let floorFront = SquatRepProfileTable.profile(for: .floor_front)
        let floorSide = SquatRepProfileTable.profile(for: .floor_side)
        let floorOblique = SquatRepProfileTable.profile(for: .floor_oblique)

        // Floor cameras look up → shoulder vertical is compressed → need lower thresholds
        XCTAssertLessThan(floorFront.repBottomExcursionNormalized,
                          chestSide.repBottomExcursionNormalized,
                          "Floor front should have lower bottom excursion than chest side")
        XCTAssertLessThan(floorSide.repBottomExcursionNormalized,
                          chestSide.repBottomExcursionNormalized)
        XCTAssertLessThan(floorOblique.repBottomExcursionNormalized,
                          chestSide.repBottomExcursionNormalized)
    }

    func testUnknownUsesChestSideBaseline() {
        let unknown = SquatRepProfileTable.profile(for: .unknown)
        let chestSide = SquatRepProfileTable.profile(for: .chest_side)
        XCTAssertEqual(unknown.repBottomExcursionNormalized, chestSide.repBottomExcursionNormalized)
        XCTAssertEqual(unknown.shoulderEMAAlpha, chestSide.shoulderEMAAlpha)
    }
}

// MARK: - Extension Frame Classifier Tests

final class SquatExtensionFrameClassifierTests: XCTestCase {

    func testTransitionsUpDownNeither() {
        let profile = SquatRepProfileTable.profile(for: .chest_side)

        // Start at neither, go shallow → up
        var state = SquatExtensionFrameClassifier.nextState(previous: .neither, hipDepth: 0.05, profile: profile)
        XCTAssertEqual(state, .up)

        // Stay up while still shallow
        state = SquatExtensionFrameClassifier.nextState(previous: .up, hipDepth: 0.10, profile: profile)
        XCTAssertEqual(state, .up)

        // Go deep → down
        state = SquatExtensionFrameClassifier.nextState(previous: .up, hipDepth: 0.35, profile: profile)
        XCTAssertEqual(state, .down)

        // Stay down
        state = SquatExtensionFrameClassifier.nextState(previous: .down, hipDepth: 0.32, profile: profile)
        XCTAssertEqual(state, .down)

        // Return shallow → up
        state = SquatExtensionFrameClassifier.nextState(previous: .down, hipDepth: 0.05, profile: profile)
        XCTAssertEqual(state, .up)
    }

    func testHysteresisPreventsBouncing() {
        let profile = SquatRepProfileTable.profile(for: .chest_side)
        // In the middle band: should stay as neither
        let state = SquatExtensionFrameClassifier.nextState(previous: .neither, hipDepth: 0.20, profile: profile)
        XCTAssertEqual(state, .neither, "Mid-range depth should stay in neither")
    }
}

// MARK: - Barbell Back Squat Rep Profile Tests

final class BarbellBackSquatRepProfileTests: XCTestCase {

    func testDefaultProfileHasValidKneeAngleThresholds() {
        let profile = BarbellBackSquatRepProfileTable.defaultProfile
        // DOWN threshold must be less than UP threshold (hysteresis gap)
        XCTAssertLessThan(profile.downAngleThreshold, profile.upAngleThreshold,
                          "DOWN angle must be below UP angle for hysteresis")
        // Reasonable range: deep squat ≈ 60–100°, standing ≈ 155–170°
        XCTAssertGreaterThanOrEqual(profile.downAngleThreshold, 60)
        XCTAssertLessThanOrEqual(profile.downAngleThreshold, 120)
        XCTAssertGreaterThanOrEqual(profile.upAngleThreshold, 140)
        XCTAssertLessThanOrEqual(profile.upAngleThreshold, 175)
    }

    func testDefaultProfileHasValidTimingGates() {
        let profile = BarbellBackSquatRepProfileTable.defaultProfile
        XCTAssertGreaterThan(profile.minRepInterval, 0)
        XCTAssertGreaterThan(profile.minRepCycleDuration, 0)
        XCTAssertGreaterThan(profile.maxRepCycleDuration, profile.minRepCycleDuration,
                             "Max cycle must exceed min cycle")
    }

    func testBarbellAllowsSlowerRepsThanBodyweight() {
        let barbell = BarbellBackSquatRepProfileTable.defaultProfile
        let bodyweight = SquatRepProfileTable.profile(for: .chest_side)
        XCTAssertGreaterThanOrEqual(barbell.maxRepCycleDuration, bodyweight.maxRepCycleDuration,
                                    "Barbell should allow at least as long a rep as bodyweight (heavier load = slower)")
        XCTAssertGreaterThanOrEqual(barbell.minRepCycleDuration, bodyweight.minRepCycleDuration,
                                    "Barbell min cycle should be >= bodyweight (bar slows movement)")
    }

    func testBarbellUpThresholdSlightlyLowerThanBodyweight() {
        let barbell = BarbellBackSquatRepProfileTable.defaultProfile
        let bodyweight = SquatRepProfileTable.profile(for: .chest_side)
        // Barbell lifters may not fully lock out under load
        XCTAssertLessThanOrEqual(barbell.upAngleThreshold, bodyweight.upAngleThreshold,
                                  "Barbell UP threshold should be <= bodyweight (incomplete lockout under load)")
    }

    func testBarbellDownThresholdMatchesBodyweight() {
        let barbell = BarbellBackSquatRepProfileTable.defaultProfile
        let bodyweight = SquatRepProfileTable.profile(for: .chest_side)
        // Both movements hit the same depth — parallel or below
        XCTAssertEqual(barbell.downAngleThreshold, bodyweight.downAngleThreshold,
                       "DOWN threshold should match — same squat depth target")
    }

    func testBarbellEMAAlphaMatchesBodyweight() {
        let barbell = BarbellBackSquatRepProfileTable.defaultProfile
        let bodyweight = SquatRepProfileTable.profile(for: .chest_side)
        XCTAssertEqual(barbell.kneeAngleEMAAlpha, bodyweight.kneeAngleEMAAlpha,
                       "EMA smoothing should match — same pose estimation noise")
    }

    func testHysteresisGapIsLargeEnough() {
        let profile = BarbellBackSquatRepProfileTable.defaultProfile
        let gap = profile.upAngleThreshold - profile.downAngleThreshold
        // Need at least 40° gap to prevent double-counting from oscillations
        XCTAssertGreaterThanOrEqual(gap, 40,
                                    "Hysteresis gap must be wide enough to prevent phantom reps")
    }
}

// MARK: - Viewpoint Bucket Helper Tests

// MARK: - Deadlift Rep Profile Tests

final class DeadliftRepProfileTests: XCTestCase {

    // MARK: - Default (Conventional) Profile

    func testDefaultProfileHasValidHipAngleThresholds() {
        let profile = DeadliftRepProfileTable.defaultProfile
        // DOWN threshold must be less than UP threshold (hysteresis gap)
        XCTAssertLessThan(profile.downAngleThreshold, profile.upAngleThreshold,
                          "DOWN angle must be below UP angle for hysteresis")
        // Reasonable range: bottom of deadlift ≈ 70–110°, lockout ≈ 160–180°
        XCTAssertGreaterThanOrEqual(profile.downAngleThreshold, 70)
        XCTAssertLessThanOrEqual(profile.downAngleThreshold, 130)
        XCTAssertGreaterThanOrEqual(profile.upAngleThreshold, 150)
        XCTAssertLessThanOrEqual(profile.upAngleThreshold, 180)
    }

    func testDefaultProfileHasValidTimingGates() {
        let profile = DeadliftRepProfileTable.defaultProfile
        XCTAssertGreaterThan(profile.minRepInterval, 0)
        XCTAssertGreaterThan(profile.minRepCycleDuration, 0)
        XCTAssertGreaterThan(profile.maxRepCycleDuration, profile.minRepCycleDuration,
                             "Max cycle must exceed min cycle")
    }

    func testDefaultProfileHasLargeEnoughHysteresisGap() {
        let profile = DeadliftRepProfileTable.defaultProfile
        let gap = profile.upAngleThreshold - profile.downAngleThreshold
        // Need at least 40° gap to prevent double-counting
        XCTAssertGreaterThanOrEqual(gap, 40,
                                    "Hysteresis gap must be wide enough to prevent phantom reps")
    }

    func testDefaultProfileMatchesReferenceScript() {
        // Verifies the profile matches the deadlift_counter.py reference values:
        // DOWN_ANGLE_THRESH = 110, UP_ANGLE_THRESH = 160, EMA_ALPHA = 0.25
        let profile = DeadliftRepProfileTable.defaultProfile
        XCTAssertEqual(profile.downAngleThreshold, 110,
                       "Should match reference script DOWN_ANGLE_THRESH")
        XCTAssertEqual(profile.upAngleThreshold, 160,
                       "Should match reference script UP_ANGLE_THRESH")
        XCTAssertEqual(profile.hipAngleEMAAlpha, 0.25,
                       "Should match reference script EMA_ALPHA")
    }

    func testConventionalHasNoKneeGuard() {
        let profile = DeadliftRepProfileTable.defaultProfile
        XCTAssertNil(profile.kneeBendLimitAngle,
                     "Conventional deadlift allows full knee bend — no guard")
    }

    // MARK: - Romanian Profile

    func testRomanianProfileMatchesReferenceScript() {
        // Verifies the profile matches the rdl_counter.py reference values:
        // DOWN_ANGLE_THRESH = 105, UP_ANGLE_THRESH = 160, KNEE_BEND_LIMIT = 145, EMA_ALPHA = 0.25
        let profile = DeadliftRepProfileTable.romanianProfile
        XCTAssertEqual(profile.downAngleThreshold, 105,
                       "Should match reference script DOWN_ANGLE_THRESH")
        XCTAssertEqual(profile.upAngleThreshold, 160,
                       "Should match reference script UP_ANGLE_THRESH")
        XCTAssertEqual(profile.hipAngleEMAAlpha, 0.25,
                       "Should match reference script EMA_ALPHA")
    }

    func testRomanianProfileHasLowerDownThresholdThanConventional() {
        let conventional = DeadliftRepProfileTable.defaultProfile
        let romanian = DeadliftRepProfileTable.romanianProfile
        // Straighter legs in RDL → torso tips further → hip angle goes lower
        XCTAssertLessThan(romanian.downAngleThreshold, conventional.downAngleThreshold,
                          "Romanian DOWN threshold should be lower (straighter legs = deeper hip hinge angle)")
    }

    func testRomanianProfileMatchesLockout() {
        let conventional = DeadliftRepProfileTable.defaultProfile
        let romanian = DeadliftRepProfileTable.romanianProfile
        // Both end at the same lockout position
        XCTAssertEqual(romanian.upAngleThreshold, conventional.upAngleThreshold,
                       "Lockout position should be the same for both variants")
    }

    func testRomanianProfileHasValidHysteresisGap() {
        let profile = DeadliftRepProfileTable.romanianProfile
        let gap = profile.upAngleThreshold - profile.downAngleThreshold
        XCTAssertGreaterThanOrEqual(gap, 40,
                                    "RDL hysteresis gap must prevent phantom reps")
    }

    // MARK: - RDL Knee Bend Guard

    func testRomanianHasKneeBendGuard() {
        let profile = DeadliftRepProfileTable.romanianProfile
        XCTAssertNotNil(profile.kneeBendLimitAngle,
                        "RDL must have a knee-bend guard to enforce straight-leg form")
    }

    func testKneeBendLimitIsReasonable() {
        let limit = DeadliftRepProfileTable.romanianProfile.kneeBendLimitAngle!
        // In a proper RDL, knees stay mostly straight (≈150–170°).
        // Limit should warn when knee angle drops too low (too much bend).
        XCTAssertGreaterThanOrEqual(limit, 130,
                                    "Knee guard too lenient — would allow full squat depth")
        XCTAssertLessThanOrEqual(limit, 160,
                                  "Knee guard too strict — would warn on normal soft-knee position")
        // Reference script uses 145°
        XCTAssertEqual(limit, 145, "Should match reference script KNEE_BEND_LIMIT")
    }

    // MARK: - Deadlift vs Squat: Different Movement Pattern

    func testDeadliftUsesHipAngleNotKneeAngle() {
        // Deadlift tracks hip angle (shoulder→hip→knee): 170° standing, 70-110° hinged
        // Squat tracks knee angle (hip→knee→ankle): 170° standing, 60-100° at depth
        // The DOWN thresholds should be different because they measure different joints
        let deadlift = DeadliftRepProfileTable.defaultProfile
        let squat = SquatRepProfileTable.profile(for: .chest_side)

        // Deadlift DOWN threshold is typically higher than squat (hip doesn't close as much)
        XCTAssertGreaterThanOrEqual(deadlift.downAngleThreshold, squat.downAngleThreshold,
                                    "Deadlift hip angle at bottom should be >= squat knee angle at depth")
    }

    func testDeadliftAllowsSlowerRepsThanSquat() {
        let deadlift = DeadliftRepProfileTable.defaultProfile
        let squat = SquatRepProfileTable.profile(for: .chest_side)
        // Deadlifts are generally slower than squats (floor start, heavier loads)
        XCTAssertGreaterThanOrEqual(deadlift.minRepCycleDuration, squat.minRepCycleDuration)
        XCTAssertGreaterThanOrEqual(deadlift.maxRepCycleDuration, squat.maxRepCycleDuration)
    }
}

// MARK: - Barbell Row Rep Profile Tests

final class BarbellRowRepProfileTests: XCTestCase {

    func testDefaultProfileMatchesReferenceScript() {
        // Verifies the profile matches the barbell_row_counter.py reference values:
        // DOWN_ANGLE_THRESH = 145, UP_ANGLE_THRESH = 80, TORSO_HINGE_MAX = 130, EMA_ALPHA = 0.25
        let profile = BarbellRowRepProfileTable.defaultProfile
        XCTAssertEqual(profile.downAngleThreshold, 145,
                       "Should match reference script DOWN_ANGLE_THRESH")
        XCTAssertEqual(profile.upAngleThreshold, 80,
                       "Should match reference script UP_ANGLE_THRESH")
        XCTAssertEqual(profile.elbowAngleEMAAlpha, 0.25,
                       "Should match reference script EMA_ALPHA")
        XCTAssertEqual(profile.torsoHingeMaxAngle, 130,
                       "Should match reference script TORSO_HINGE_MAX")
    }

    func testInvertedStateMachine() {
        let profile = BarbellRowRepProfileTable.defaultProfile
        // Barbell row is inverted vs squats/deadlifts:
        // DOWN threshold (arms extended) > UP threshold (arms pulled)
        XCTAssertGreaterThan(profile.downAngleThreshold, profile.upAngleThreshold,
                             "DOWN (arms extended) must be above UP (arms pulled) — inverted hysteresis")
    }

    func testHysteresisGapIsLargeEnough() {
        let profile = BarbellRowRepProfileTable.defaultProfile
        let gap = profile.downAngleThreshold - profile.upAngleThreshold
        // Need at least 50° gap — elbow angle covers a large range
        XCTAssertGreaterThanOrEqual(gap, 50,
                                    "Hysteresis gap must prevent phantom reps from arm jitter")
    }

    func testValidTimingGates() {
        let profile = BarbellRowRepProfileTable.defaultProfile
        XCTAssertGreaterThan(profile.minRepInterval, 0)
        XCTAssertGreaterThan(profile.minRepCycleDuration, 0)
        XCTAssertGreaterThan(profile.maxRepCycleDuration, profile.minRepCycleDuration)
    }

    func testElbowAngleRangesAreReasonable() {
        let profile = BarbellRowRepProfileTable.defaultProfile
        // Arms extended (bottom): elbow ≈ 155–175°
        XCTAssertGreaterThanOrEqual(profile.downAngleThreshold, 130,
                                    "DOWN threshold too low — would trigger before arms are extended")
        XCTAssertLessThanOrEqual(profile.downAngleThreshold, 165,
                                  "DOWN threshold too high — would never trigger")
        // Arms pulled (top): elbow ≈ 45–75°
        XCTAssertGreaterThanOrEqual(profile.upAngleThreshold, 50,
                                    "UP threshold too low — would require impossible arm position")
        XCTAssertLessThanOrEqual(profile.upAngleThreshold, 100,
                                  "UP threshold too high — would trigger before bar reaches belly")
    }

    func testTorsoGuardIsReasonable() {
        let profile = BarbellRowRepProfileTable.defaultProfile
        // Proper barbell row torso angle (hip angle) ≈ 45–90°
        // Standing upright ≈ 170°
        // Guard should warn somewhere in between
        XCTAssertGreaterThanOrEqual(profile.torsoHingeMaxAngle, 100,
                                    "Guard too strict — would warn on acceptable row position")
        XCTAssertLessThanOrEqual(profile.torsoHingeMaxAngle, 150,
                                  "Guard too lenient — wouldn't catch cheating")
    }

    func testDifferentMovementPatternFromSquatAndDeadlift() {
        let row = BarbellRowRepProfileTable.defaultProfile
        let squat = SquatRepProfileTable.profile(for: .chest_side)
        let deadlift = DeadliftRepProfileTable.defaultProfile

        // Barbell row tracks elbow (45–175°), squat tracks knee (60–170°), deadlift tracks hip (70–170°)
        // Row UP threshold should be lower than squat/deadlift DOWN thresholds
        // (elbow closes more than knee/hip at max ROM)
        XCTAssertLessThan(row.upAngleThreshold, squat.downAngleThreshold,
                          "Row elbow-pull angle should be lower than squat bottom knee angle")
        XCTAssertLessThan(row.upAngleThreshold, deadlift.downAngleThreshold,
                          "Row elbow-pull angle should be lower than deadlift bottom hip angle")
    }
}

// MARK: - Viewpoint Bucket Helper Tests

final class SquatViewpointBucketTests: XCTestCase {

    func testBucketFromHeightAndView() {
        XCTAssertEqual(SquatViewpointBucket.bucket(height: .floor, view: .front), .floor_front)
        XCTAssertEqual(SquatViewpointBucket.bucket(height: .chest, view: .side), .chest_side)
        XCTAssertEqual(SquatViewpointBucket.bucket(height: .head, view: .oblique), .head_oblique)
        XCTAssertEqual(SquatViewpointBucket.bucket(height: .unknown, view: .front), .unknown)
        XCTAssertEqual(SquatViewpointBucket.bucket(height: .floor, view: .unknown), .unknown)
    }

    func testBucketCameraHeightProperty() {
        XCTAssertEqual(SquatViewpointBucket.floor_front.cameraHeight, .floor)
        XCTAssertEqual(SquatViewpointBucket.chest_oblique.cameraHeight, .chest)
        XCTAssertEqual(SquatViewpointBucket.head_side.cameraHeight, .head)
    }

    func testBucketCameraViewProperty() {
        XCTAssertEqual(SquatViewpointBucket.floor_front.cameraView, .front)
        XCTAssertEqual(SquatViewpointBucket.chest_side.cameraView, .side)
        XCTAssertEqual(SquatViewpointBucket.head_oblique.cameraView, .oblique)
    }
}
