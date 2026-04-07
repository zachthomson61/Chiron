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
