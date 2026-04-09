//
//  SquatViewpointProfile.swift
//  Chiron
//
//  Rep detection profile and viewpoint classification for bodyweight squats.
//
//  Rep counting uses a knee-angle hysteresis state machine (UP/DOWN).
//  Viewpoint classification (camera height x view) is still used for
//  the extension-frame UI indicator and the profile name display,
//  but no longer affects rep detection thresholds.
//

import Foundation
import CoreGraphics

// MARK: - Viewpoint categories

enum CameraHeightCategory: String, Sendable {
    case floor
    case chest
    case head
    case unknown
}

enum CameraViewCategory: String, Sendable {
    case front
    case side
    case oblique
    case unknown
}

/// Nine recording buckets + unknown.
enum SquatViewpointBucket: String, CaseIterable, Sendable {
    case floor_front
    case floor_side
    case floor_oblique
    case chest_front
    case chest_side
    case chest_oblique
    case head_front
    case head_side
    case head_oblique
    case unknown

    var cameraHeight: CameraHeightCategory {
        switch self {
        case .floor_front, .floor_side, .floor_oblique: return .floor
        case .chest_front, .chest_side, .chest_oblique: return .chest
        case .head_front, .head_side, .head_oblique: return .head
        case .unknown: return .unknown
        }
    }

    var cameraView: CameraViewCategory {
        switch self {
        case .floor_front, .chest_front, .head_front: return .front
        case .floor_side, .chest_side, .head_side: return .side
        case .floor_oblique, .chest_oblique, .head_oblique: return .oblique
        case .unknown: return .unknown
        }
    }

    static func bucket(height: CameraHeightCategory, view: CameraViewCategory) -> SquatViewpointBucket {
        switch (height, view) {
        case (.floor, .front): return .floor_front
        case (.floor, .side): return .floor_side
        case (.floor, .oblique): return .floor_oblique
        case (.chest, .front): return .chest_front
        case (.chest, .side): return .chest_side
        case (.chest, .oblique): return .chest_oblique
        case (.head, .front): return .head_front
        case (.head, .side): return .head_side
        case (.head, .oblique): return .head_oblique
        default: return .unknown
        }
    }
}

// MARK: - Per-frame extension (Up / Down / Neither)

enum SquatExtensionFrameState: String, Sendable {
    case up
    case down
    case neither
}

// MARK: - Rep reject reasons (debug)

enum SquatRepRejectReason: String, Sendable {
    case none
    case minRepInterval
    case minCycleDuration
    case maxCycleDuration
    case badVisibility
}

// MARK: - Knee-angle rep phases (bodyweight)

enum BodyweightVerticalRepPhase: String, Sendable {
    case up
    case down
}

// MARK: - Rep detection profile

/// Knee-angle thresholds for rep counting + form analysis parameters.
struct SquatRepDetectionProfile: Sendable {
    // Knee angle thresholds (degrees). Standing ≈ 170°, parallel squat ≈ 80–100°.
    var downAngleThreshold: Float       // enter DOWN when smoothed angle ≤ this
    var upAngleThreshold: Float         // return to UP when smoothed angle ≥ this
    var kneeAngleEMAAlpha: Float        // EMA smoothing factor (0…1). Lower = smoother.

    // Rep timing
    var minRepInterval: TimeInterval
    var minRepCycleDuration: TimeInterval
    var maxRepCycleDuration: TimeInterval

    // Form analysis depth thresholds (driven by 3D hip depth, not knee angle)
    var repCountDepthThreshold: Float
    var repGoodDepthThreshold: Float
    var hipKneeDepthQualityToleranceNormalized: Float
    var repAccumulationStartDepth: Float

    // Per-frame extension state (hysteresis on hip depth 0…1) — UI only; does not gate rep count.
    var extensionUpEnterMaxDepth: Float
    var extensionUpExitDepth: Float
    var extensionDownEnterDepth: Float
    var extensionDownExitDepth: Float

    // Form analysis influence (0…1)
    var formWeightDepth: Float
    var formWeightKneeTracking: Float
    var formWeightForwardLean: Float
    var formIssueEvidenceMultiplier: Float
}

// MARK: - Profile table

enum SquatRepProfileTable {
    /// All viewpoints use the same default profile.
    static func profile(for bucket: SquatViewpointBucket) -> SquatRepDetectionProfile {
        return defaultProfile
    }

    private static let defaultProfile = SquatRepDetectionProfile(
        downAngleThreshold: 100,
        upAngleThreshold: 160,
        kneeAngleEMAAlpha: 0.25,
        minRepInterval: 0.35,
        minRepCycleDuration: 0.45,
        maxRepCycleDuration: 6.0,
        repCountDepthThreshold: 0.22,
        repGoodDepthThreshold: 0.38,
        hipKneeDepthQualityToleranceNormalized: 0.10,
        repAccumulationStartDepth: 0.16,
        extensionUpEnterMaxDepth: 0.14,
        extensionUpExitDepth: 0.18,
        extensionDownEnterDepth: 0.30,
        extensionDownExitDepth: 0.26,
        formWeightDepth: 1.0,
        formWeightKneeTracking: 0.85,
        formWeightForwardLean: 1.0,
        formIssueEvidenceMultiplier: 1.0
    )
}

// MARK: - Barbell Back Squat profile table

enum BarbellBackSquatRepProfileTable {
    /// Barbell back squat uses knee-angle hysteresis identical to bodyweight.
    /// The bar sits on the upper back/traps, so hip/knee/ankle angles are
    /// essentially the same — only hand position and load differ.
    static let defaultProfile = SquatRepDetectionProfile(
        downAngleThreshold: 100,       // same as bodyweight — parallel depth ≈ 80–100°
        upAngleThreshold: 155,         // slightly lower than bodyweight (160) — lifters may not
                                        // fully lock out under load before starting the next rep
        kneeAngleEMAAlpha: 0.25,       // same smoothing factor
        minRepInterval: 0.35,
        minRepCycleDuration: 0.6,      // slightly longer than bodyweight (0.45) — bar slows the movement
        maxRepCycleDuration: 8.0,      // longer max — heavy sets have slower reps and longer pauses
        repCountDepthThreshold: 0.22,
        repGoodDepthThreshold: 0.38,
        hipKneeDepthQualityToleranceNormalized: 0.10,
        repAccumulationStartDepth: 0.16,
        extensionUpEnterMaxDepth: 0.14,
        extensionUpExitDepth: 0.18,
        extensionDownEnterDepth: 0.30,
        extensionDownExitDepth: 0.26,
        formWeightDepth: 1.0,
        formWeightKneeTracking: 0.85,
        formWeightForwardLean: 1.0,
        formIssueEvidenceMultiplier: 1.0
    )
}

// MARK: - Deadlift rep detection profile

/// Hip-angle thresholds for deadlift rep counting.
/// The deadlift is a hip-hinge movement — the defining angle is shoulder→hip→knee.
///   - Standing tall (lockout): hip angle ≈ 170–180°
///   - Bottom of deadlift (hinged): hip angle ≈ 70–110°
struct DeadliftRepDetectionProfile: Sendable {
    // Hip angle thresholds (degrees).
    var downAngleThreshold: Float       // enter DOWN when smoothed angle ≤ this
    var upAngleThreshold: Float         // return to UP when smoothed angle ≥ this
    var hipAngleEMAAlpha: Float         // EMA smoothing factor (0…1). Lower = smoother.

    // Rep timing
    var minRepInterval: TimeInterval
    var minRepCycleDuration: TimeInterval
    var maxRepCycleDuration: TimeInterval

    // Knee bend guard (hip→knee→ankle). Only used for RDL.
    // In a proper RDL the knees stay soft but mostly straight.
    // If knee angle drops below this, the form warning fires (sliding toward conventional DL form).
    // nil = no knee guard (conventional deadlift doesn't restrict knee bend).
    var kneeBendLimitAngle: Float?
}

enum DeadliftRepPhase: String, Sendable {
    case up
    case down
}

enum DeadliftRepProfileTable {
    /// Conventional deadlift: deep hip hinge, bar starts on the floor.
    ///
    /// Thresholds from the reference deadlift_counter.py script:
    ///   DOWN_ANGLE_THRESH = 110  (hip angle when hinged at the bottom)
    ///   UP_ANGLE_THRESH   = 160  (hip angle at lockout)
    ///   EMA_ALPHA          = 0.25
    static let defaultProfile = DeadliftRepDetectionProfile(
        downAngleThreshold: 110,       // enter DOWN when hip angle ≤ 110°
        upAngleThreshold: 160,         // return to UP (rep counted) when hip angle ≥ 160°
        hipAngleEMAAlpha: 0.25,        // same smoothing as squat
        minRepInterval: 0.4,           // minimum time between counted reps
        minRepCycleDuration: 0.8,      // deadlifts are slower than squats — floor start adds time
        maxRepCycleDuration: 10.0,     // heavy singles can be very slow
        kneeBendLimitAngle: nil        // conventional DL allows full knee bend
    )

    /// Romanian deadlift (RDL): pure hip hinge, bar doesn't touch the floor.
    /// Straighter legs make the torso tip further forward → hip angle goes lower
    /// than you'd expect despite shorter bar ROM.
    ///
    /// Thresholds from the reference rdl_counter.py script:
    ///   DOWN_ANGLE_THRESH = 105  (hip angle at bottom of RDL)
    ///   UP_ANGLE_THRESH   = 160  (hip angle at lockout)
    ///   KNEE_BEND_LIMIT   = 145  (form guard — knees should stay mostly straight)
    ///   EMA_ALPHA          = 0.25
    static let romanianProfile = DeadliftRepDetectionProfile(
        downAngleThreshold: 105,       // straighter legs → deeper hip angle than conventional
        upAngleThreshold: 160,         // same lockout position
        hipAngleEMAAlpha: 0.25,
        minRepInterval: 0.35,
        minRepCycleDuration: 0.6,      // RDLs are slightly faster (no floor pause)
        maxRepCycleDuration: 8.0,
        kneeBendLimitAngle: 145        // form guard: warn if knee angle < 145° (too much bend)
    )
}

// MARK: - Barbell Row rep detection profile

/// Elbow-angle thresholds for barbell row rep counting.
/// The barbell row is an arm-pull movement with a fixed torso hinge:
///   - Arms extended (bottom): elbow angle ≈ 155–175°
///   - Arms pulled (top):      elbow angle ≈ 45–75°
/// State machine is inverted vs squats/deadlifts: starts DOWN, pulls to UP, rep on return to DOWN.
struct BarbellRowRepDetectionProfile: Sendable {
    // Elbow angle thresholds (shoulder→elbow→wrist).
    var downAngleThreshold: Float       // arms extended — enter DOWN when smoothed angle ≥ this
    var upAngleThreshold: Float         // arms pulled   — enter UP when smoothed angle ≤ this
    var elbowAngleEMAAlpha: Float       // EMA smoothing factor (0…1).

    // Rep timing
    var minRepInterval: TimeInterval
    var minRepCycleDuration: TimeInterval
    var maxRepCycleDuration: TimeInterval

    // Torso hinge guard (shoulder→hip→knee).
    // A proper barbell row requires a forward lean. Warn if the lifter stands up
    // too much during the pull (cheat row / momentum).
    var torsoHingeMaxAngle: Float       // warn if hip angle rises ABOVE this during pull
}

/// Barbell row phases: DOWN = arms extended (bar hanging), UP = arms pulled (bar at belly).
enum BarbellRowRepPhase: String, Sendable {
    case down
    case up
}

enum BarbellRowRepProfileTable {
    /// Standard barbell row (Pendlay / bent-over row).
    ///
    /// Thresholds from the reference barbell_row_counter.py script:
    ///   DOWN_ANGLE_THRESH  = 145  (arms extended — bar hanging)
    ///   UP_ANGLE_THRESH    = 80   (arms pulled — bar at belly)
    ///   TORSO_HINGE_MAX    = 130  (torso too upright = cheat row)
    ///   EMA_ALPHA           = 0.25
    static let defaultProfile = BarbellRowRepDetectionProfile(
        downAngleThreshold: 145,       // arms extended: elbow ≈ 155–175°, enter DOWN at ≥ 145°
        upAngleThreshold: 80,          // arms pulled: elbow ≈ 45–75°, enter UP at ≤ 80°
        elbowAngleEMAAlpha: 0.25,
        minRepInterval: 0.3,           // rows can be fast
        minRepCycleDuration: 0.4,      // quick pull-lower cycle
        maxRepCycleDuration: 6.0,      // heavy rows with pauses at top
        torsoHingeMaxAngle: 130        // warn if hip angle > 130° (standing too upright)
    )
}

// MARK: - Extension frame state (hysteresis)

enum SquatExtensionFrameClassifier {
    static func nextState(
        previous: SquatExtensionFrameState,
        hipDepth: Float,
        profile: SquatRepDetectionProfile
    ) -> SquatExtensionFrameState {
        let uEnter = profile.extensionUpEnterMaxDepth
        let uExit = profile.extensionUpExitDepth
        let dEnter = profile.extensionDownEnterDepth
        let dExit = profile.extensionDownExitDepth

        switch previous {
        case .up:
            if hipDepth >= dEnter { return .down }
            if hipDepth > uExit { return .neither }
            return .up
        case .down:
            if hipDepth <= uEnter { return .up }
            if hipDepth < dExit { return .neither }
            return .down
        case .neither:
            if hipDepth <= uEnter { return .up }
            if hipDepth >= dEnter { return .down }
            return .neither
        }
    }
}

// MARK: - Viewpoint classifiers (2D overlay)
//
// Still used for UI display (currentSquatProfileName) and extension-frame state,
// even though rep detection thresholds are now angle-based and viewpoint-independent.

struct SquatViewpointClassifier {

    struct HeightScores: Sendable {
        var floor: Float = 0
        var chest: Float = 0
        var head: Float = 0
    }

    struct ViewScores: Sendable {
        var front: Float = 0
        var side: Float = 0
        var oblique: Float = 0
    }

    private static let minWinMargin: Float = 0.06
    private static let minWinScore: Float = 0.22

    static func classifyCameraHeight(overlay: [String: CGPoint]) -> (CameraHeightCategory, HeightScores) {
        var s = HeightScores()
        guard
            let nose = overlay["nose"],
            let ls = overlay["leftShoulder"], let rs = overlay["rightShoulder"],
            let lh = overlay["leftHip"], let rh = overlay["rightHip"],
            let lk = overlay["leftKnee"], let rk = overlay["rightKnee"],
            let la = overlay["leftAnkle"], let ra = overlay["rightAnkle"]
        else {
            return (.unknown, s)
        }

        let shoulderY = (ls.y + rs.y) / 2
        let hipY = (lh.y + rh.y) / 2
        let kneeY = (lk.y + rk.y) / 2
        let ankleY = (la.y + ra.y) / 2

        if ankleY < 0.72 { s.floor += 0.25 }
        if kneeY < hipY + 0.02, ankleY < kneeY + 0.05 { s.floor += 0.2 }
        let torsoSpan = abs(shoulderY - hipY)
        let legSpan = abs(hipY - ankleY)
        if legSpan > 0.001 {
            let ratio = torsoSpan / legSpan
            if ratio < 0.52 { s.floor += 0.35 }
            else if ratio > 0.78 { s.head += 0.3 }
            else { s.chest += 0.35 }
        } else {
            s.chest += 0.2
        }

        if ankleY < 0.68 { s.floor += 0.15 }
        if shoulderY > 0.45 { s.head += 0.15 }
        if nose.y > 0.4 { s.head += 0.1 }

        let cat = pickHeightWinner(floor: s.floor, chest: s.chest, head: s.head)
        return (cat, s)
    }

    static func classifyCameraView(overlay: [String: CGPoint], confidence: [String: Float]) -> (CameraViewCategory, ViewScores) {
        var s = ViewScores()
        guard
            let ls = overlay["leftShoulder"], let rs = overlay["rightShoulder"],
            let lh = overlay["leftHip"], let rh = overlay["rightHip"],
            let lw = overlay["leftWrist"], let rw = overlay["rightWrist"],
            let la = overlay["leftAnkle"], let ra = overlay["rightAnkle"]
        else {
            return (.unknown, s)
        }

        let shoulderW = abs(rs.x - ls.x)
        let hipW = abs(rh.x - lh.x)
        let wristW = abs(rw.x - lw.x)
        let ankleW = abs(ra.x - la.x)

        let avgPairW = (shoulderW + hipW + wristW + ankleW) / 4

        if avgPairW > 0.14 { s.front += 0.35 }
        if avgPairW < 0.06 { s.side += 0.4 }
        if avgPairW >= 0.06, avgPairW <= 0.14 { s.oblique += 0.35 }

        if shoulderW > 0.12, hipW > 0.08 { s.front += 0.2 }
        if shoulderW < 0.05, hipW < 0.05 { s.side += 0.25 }

        let lc = confidence["leftKnee"] ?? 1
        let rc = confidence["rightKnee"] ?? 1
        if abs(lc - rc) > 0.25 { s.side += 0.12 }

        let cat = pickViewWinner(front: s.front, oblique: s.oblique, side: s.side)
        return (cat, s)
    }

    private static func pickHeightWinner(floor f: Float, chest c: Float, head h: Float) -> CameraHeightCategory {
        let pairs: [(CameraHeightCategory, Float)] = [(.floor, f), (.chest, c), (.head, h)]
        let sorted = pairs.sorted { $0.1 > $1.1 }
        let best = sorted[0].1
        let second = sorted[1].1
        guard best >= minWinScore, (best - second) >= minWinMargin else { return .unknown }
        return sorted[0].0
    }

    private static func pickViewWinner(front: Float, oblique: Float, side: Float) -> CameraViewCategory {
        let pairs: [(CameraViewCategory, Float)] = [(.front, front), (.oblique, oblique), (.side, side)]
        let sorted = pairs.sorted { $0.1 > $1.1 }
        let best = sorted[0].1
        let second = sorted[1].1
        guard best >= minWinScore, (best - second) >= minWinMargin else { return .unknown }
        return sorted[0].0
    }
}

// MARK: - Viewpoint promotion (temporal)

struct SquatViewpointSmoother {
    private var buffer: [SquatViewpointBucket] = []
    private let bufferSize: Int
    private let promoteCount: Int
    private(set) var activeBucket: SquatViewpointBucket

    init(bufferSize: Int = 10, promoteCount: Int = 7, initial: SquatViewpointBucket = .chest_side) {
        self.bufferSize = bufferSize
        self.promoteCount = promoteCount
        self.activeBucket = initial
    }

    @discardableResult
    mutating func push(candidate raw: SquatViewpointBucket) -> Bool {
        let candidate = raw == .unknown ? SquatViewpointBucket.chest_side : raw
        buffer.append(candidate)
        if buffer.count > bufferSize { buffer.removeFirst() }

        guard buffer.count >= promoteCount else { return false }

        let tail = Array(buffer.suffix(promoteCount))
        let first = tail[0]
        let allSame = tail.allSatisfy { $0 == first }
        if allSame, first != activeBucket {
            activeBucket = first
            return true
        }
        return false
    }

    mutating func reset(keepBucket: SquatViewpointBucket = .chest_side) {
        buffer.removeAll()
        activeBucket = keepBucket
    }
}
