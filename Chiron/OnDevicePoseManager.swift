//
//  OnDevicePoseManager.swift
//  Chiron
//
//  On-device pose pipeline: MediaPipe Pose Landmarker (live stream) → MediaPipePoseAdapter
//  → Skeleton3D + overlay landmarks → form analysis, rep counting, and UI updates.
//

import Foundation
import AVFoundation
import CoreML
import UIKit
import MediaPipeTasksVision

// MARK: - Pose Landmark Structure
struct PoseLandmark {
    let type: PoseLandmarkType
    let x: Float
    let y: Float
    let confidence: Float
    
    init(type: PoseLandmarkType, point: CGPoint, confidence: Float) {
        self.type = type
        self.x = Float(point.x)
        self.y = Float(point.y)
        self.confidence = confidence
    }
    
    enum PoseLandmarkType {
        case leftShoulder, rightShoulder
        case leftHip, rightHip
        case leftKnee, rightKnee
        case leftAnkle, rightAnkle
        case leftElbow, rightElbow
        case leftWrist, rightWrist
        case nose, leftEye, rightEye
        case leftEar, rightEar
    }
}

// MARK: - Form Analysis Results
struct FormAnalysis {
    let depth: Float // 0.0 = shallow, 1.0 = deep
    let backAngle: Float // degrees (0-180)
    let kneeAlignment: Float // -1.0 = knees caving in, 0.0 = aligned, 1.0 = knees bowing out
    let overallScore: Float // 0.0-1.0
    let issues: [IssueCode]
    let summary: String
    let repCount: Int // Current rep count
    // Average tempo metrics for current set (milliseconds)
    let avgEccentricMs: Float?  // Time going down
    let avgPauseMs: Float?      // Time at bottom
    let avgConcentricMs: Float? // Time coming up
    // ROM metrics for current set
    let avgBottomDepth: Float?
    let deepRepRatio: Float?
}

// MARK: - Bodyweight Squat Rep-Level Metrics (phase-relevant, for set aggregation)

/// Per-rep metrics for bodyweight squats. Used for set-level aggregation; invalid reps are discarded.
struct BodyweightRepMetrics {
    let depthAtBottom: Float
    let backAngleMax: Float
    let kneeAlignmentWorstNearBottom: Float
    let shallowDepth: Bool
    let excessiveForwardLean: Bool
    let kneeValgus: Bool
    /// True if hip–knee relationship met parallel-depth quality (secondary; does not gate counting).
    let hipKneeDepthQualityMet: Bool
    /// True if 3D depth was below primary threshold but above secondary floor.
    /// Indicates camera-angle compression rather than actually shallow squat.
    let reducedDepthConfidence: Bool
    let valid: Bool
    let timestamp: TimeInterval
}

/// Bodyweight-only: gates frame accumulation for per-rep metrics (independent of squat rep counter phase names).
enum RepPhase {
    case idle
    case accumulating
}

/// Barbell/benchPress squat rep phases: hip-depth hysteresis. Bodyweight squats use `BodyweightVerticalRepPhase` (shoulder Y) instead.
enum SquatRepPhase {
    case idleAtTop
    case descending
    case bottomReached
    case ascending
}

/// Snapshot of hip-vs-knee vertical relationship (secondary quality tag only).
struct SquatRepFrame {
    let avgHipY: Float
    let avgKneeY: Float
    let legLength: Float
    let normalizedHipKneeDelta: Float   // (avgHipY - avgKneeY) / legLength; ≤0 means hips at or below knees
}

/// Current-frame metrics used as fallback when no valid rep history exists.
struct FrameMetrics {
    let depth: Float
    let backAngle: Float
    let kneeAlignment: Float
}

// MARK: - Workout State Management
enum WorkoutState {
    case waiting        // Waiting for user to start exercising
    case exercising     // Actively performing reps in a set
    case resting        // Rest period between sets
    case finished       // Workout completed
}

// MARK: - Tracked Exercise Type

/// Exercise type identifier for pose detection and form analysis.
/// Maps the user-selected exercise into a pose-analysis category.
enum TrackedExerciseType {
    case bodyweight           // Bodyweight squat exercises
    case barbell              // Barbell back squat exercises
    case benchPress           // Regular bench press
    case closeGripBenchPress  // Close-grip bench press exercises
    case row                  // Barbell row exercises
    case deadlift             // Conventional deadlift exercises
    case romanianDeadlift     // Romanian deadlift exercises

    /// True for exercises that involve a held barbell — used to gate bar overlay drawing.
    var usesBarbell: Bool {
        switch self {
        case .barbell, .benchPress, .closeGripBenchPress, .row, .deadlift, .romanianDeadlift:
            return true
        case .bodyweight:
            return false
        }
    }
}

// MARK: - Inactivity Detection
class InactivityDetector {
    private var lastRepTime: Date?
    private var lastValidPoseTime: Date?
    private let inactivityThreshold: TimeInterval = 4.0
    private let poseThreshold: TimeInterval = 5.0
    
    func checkInactivity() -> Bool {
        let now = Date()
        
        // Check if no reps detected for inactivity threshold
        if let lastRep = lastRepTime {
            if now.timeIntervalSince(lastRep) > inactivityThreshold {
                return true
            }
        }
        
        // Check if no valid pose detected for pose threshold
        if let lastPose = lastValidPoseTime {
            if now.timeIntervalSince(lastPose) > poseThreshold {
                return true
            }
        }
        
        return false
    }
    
    func resetTimer() {
        lastRepTime = Date()
        lastValidPoseTime = Date()
    }
    
    func updateLastActivity() {
        lastValidPoseTime = Date()
    }
    
    func updateLastRep() {
        lastRepTime = Date()
    }
    
    func getTimeSinceLastRep() -> TimeInterval {
        guard let lastRep = lastRepTime else { return 0 }
        return Date().timeIntervalSince(lastRep)
    }
    
    func getTimeSinceLastPose() -> TimeInterval {
        guard let lastPose = lastValidPoseTime else { return 0 }
        return Date().timeIntervalSince(lastPose)
    }
}

// MARK: - On-Device Pose Manager
class OnDevicePoseManager: NSObject, ObservableObject {
    // `nonisolated(unsafe)` because the singleton reference itself is
    // immutable after init and safe to grab from any thread (telemetry's
    // analysis-thread CSV writer, for instance). Mutations to the published
    // properties below still happen on main, so the "unsafe" part is
    // disclaimer, not actual unsafety.
    nonisolated(unsafe) static let shared = OnDevicePoseManager()
    
    // MARK: - Pose Detection Properties
    @Published var poseDetected = false
    @Published var currentFormAnalysis: FormAnalysis?
    @Published var repCount: Int = 0
    @Published var workoutState: WorkoutState = .waiting
    @Published var currentSet: Int = 0
    @Published var trackedExerciseType: TrackedExerciseType = .bodyweight

    /// Goal-derived tempo reference points for the current user. `nil` means
    /// the active goal does not receive tempo coaching. Set from the user's
    /// PrimaryGoal at onboarding completion and whenever the goal changes.
    /// See `TempoTargets` for how deviations are detected.
    var tempoTargets: TempoTargets?

    /// Enables per-frame debug logging for squat rep detection.
    /// Toggle from the debug overlay in TrackView. Zero overhead when false.
    @Published var debugLoggerEnabled: Bool = false {
        didSet { SquatRepDebugLogger.shared.isEnabled = debugLoggerEnabled }
    }
    
    /// Stores form analysis at rep completion for score calculation.
    /// 
    /// **Purpose:** Ensures form score can be calculated even if pose detection is temporarily lost
    /// immediately after rep completion. The view layer uses this as a fallback when `currentFormAnalysis`
    /// is unavailable during score calculation.
    @Published var lastRepFormAnalysis: FormAnalysis?
    
    /// Latest pose landmarks in normalised coordinates (0–1).
    /// Populated by MediaPipePoseAdapter from PoseLandmarkerResult.landmarks.
    @Published var currentNormalizedLandmarks: [String: CGPoint]?

    /// Orientation of the most recent pixel buffer fed to MediaPipe.
    /// `connection.videoRotationAngle = 90` rotates buffers to portrait on some devices (e.g. iPhone 16 and earlier)
    /// but is a no-op on others (e.g. iPhone 17 family), so the overlay transform has to branch on the actual
    /// buffer dimensions rather than assume one or the other.
    @Published var landmarkBufferIsPortrait: Bool = false

    /// Wrist-derived bar segment (normalised coords) for barbell exercises.
    /// `nil` when the exercise is not barbell-based or both wrists are not sufficiently visible.
    @Published var currentBarbellLine: BarbellLine?
    
    /// Camera view type for close-grip bench press exercises.
    /// Used to adjust form analysis calculations based on camera angle:
    /// - `.rack`: Top-down view (high, angled down)
    /// - `.floor`: Bottom-up view (low, angled up)
    /// - `.tripod`: Side view (bar level, slight angle)
    /// Set by WorkoutActiveView when starting a close-grip bench press exercise.
    var benchPressViewType: BenchPressViewType = .tripod

    // MARK: - Bodyweight squat viewpoint (auto-classified, debuggable)
    @Published var currentCameraHeightCategory: CameraHeightCategory = .unknown
    @Published var currentCameraViewCategory: CameraViewCategory = .unknown
    @Published var currentSquatViewpointBucket: SquatViewpointBucket = .chest_side
    @Published var currentSquatProfileName: String = SquatViewpointBucket.chest_side.rawValue
    @Published var currentSquatExtensionFrameState: SquatExtensionFrameState = .neither

    private var viewpointSmoother = SquatViewpointSmoother()
    private var squatExtensionFrameStateInternal: SquatExtensionFrameState = .neither
    /// Active rep-detection profile for bodyweight (updated each frame from smoothed viewpoint).
    private var activeBodyweightRepProfile: SquatRepDetectionProfile = SquatRepProfileTable.profile(for: .chest_side)

    // MARK: - Bodyweight shoulder-vertical rep state

    #if DEBUG
    /// Enable to log every state-machine transition, commit decision, and calibration event.
    private let repDebugLog: Bool = false
    #else
    private let repDebugLog: Bool = false
    #endif

    private func repLog(_ msg: @autoclosure () -> String) {
        guard repDebugLog else { return }
        print("[RepDebug] \(msg())")
    }

    // MARK: - Bodyweight squat rep detection state
    //
    // Knee-angle hysteresis: UP ↔ DOWN with EMA-smoothed angle.
    // See validateBodyweightSquatRep() for the algorithm.

    private var bwRepPhase: BodyweightVerticalRepPhase = .up
    private var bwSmoothedKneeAngle: Float?          // EMA-smoothed knee angle
    private var bwRepCycleStartTime: Date?
    private var bwBadFrameStreak: Int = 0
    private let bwBadFrameLimit: Int = 15
    private var bwLastRejectReason: String?   // transient, for debug CSV
    private var rdlLastRejectReason: String?  // transient, for debug CSV
    private var bwSelectedSide: String = ""   // "L" or "R"
    private var bwRawKneeAngle: Float?        // unsmoothed, for debug CSV

    // MARK: - Row rep state (bodyweight-style 2-state hysteresis on elbow angle)
    //
    // 3D world-coordinate elbow angle (shoulder→elbow→wrist) is camera-angle invariant.
    // Pick the better-visible arm side; EMA-smooth; 2-state .extended ↔ .flexed with timing gates.

    private enum RowRepPhase: String { case extended, flexed }
    private var rowRepPhase: RowRepPhase = .extended
    private var rowSmoothedElbowAngle: Float?
    private var rowRepCycleStartTime: Date?
    private var rowBadFrameStreak: Int = 0
    private let rowEMAAlpha: Float = 0.4
    /// Enter FLEXED when smoothed angle ≤ this (top of the pull).
    /// True peak elbow flexion is ~70-100°, but front- and floor-mounted views project the
    /// upper-arm/forearm motion mostly along the camera's depth axis, where MediaPipe's
    /// monocular 3D depth is least accurate. The smoothed angle in those views compresses
    /// substantially: high-rep front-mounted field tests show partial-ROM reps with the
    /// smoothed angle bottoming at 135-141° and only briefly grazing below 138°. Setting
    /// the threshold at 142° gives the cycle a long-enough window (≥0.5s) to clear the
    /// rowMinRepCycleDuration gate even on those shallow reps, while side views still
    /// trigger easily (deep flex). False-positive setup motions are caught by the
    /// shoulder-Y stability and ankle-drift gates downstream.
    private let rowFlexedThreshold: Float = 142
    /// Return to EXTENDED when smoothed angle ≥ this (arms back near straight ≈ 160–170°).
    /// Sized in tandem with the flexed threshold: a real rep's bottom can have a small
    /// mid-cycle bounce (one observed test peaked at 145.1° between two 135° dips), and
    /// the exit threshold has to clear that bounce so a single rep doesn't split into
    /// two counted reps. 150° keeps an ~8° hysteresis gap and stays well below the
    /// 162-178° peaks seen between actual reps.
    private let rowExtendedThreshold: Float = 150
    private let rowMinRepCycleDuration: TimeInterval = 0.5
    private let rowMaxRepCycleDuration: TimeInterval = 5.0
    private let rowMinRepInterval: TimeInterval = 0.5
    /// Row-specific ankle drift tolerance, looser than the global 0.05 because
    /// the bent-over bracing position invites foot micro-shifts and front views
    /// amplify 2D ankle-Y jitter without representing actual walking.
    private let rowAnkleStabilityTolerance: Float = 0.10
    /// Shoulder-Y stability gate: a real row keeps the torso planted in roughly the same
    /// vertical image position throughout the pull. Misfires (standing upright, walking
    /// into position, hand-to-face) shift the shoulder Y substantially. Across the
    /// observed test set, real rows stay within 0.021; misfires exceed 0.053. Threshold
    /// of 0.035 sits in the empirical gap with margin both ways.
    private let rowShoulderYStabilityTolerance: Float = 0.035
    /// Tracks the shoulder Y range across the active rep cycle (`.flexed` phase only).
    private var rowMinShoulderYInFlexed: Float = .greatestFiniteMagnitude
    private var rowMaxShoulderYInFlexed: Float = -.greatestFiniteMagnitude
    /// Tracks the deepest smoothed elbow angle observed during the active flexed cycle.
    /// Used by the shallow-brief-motion gate to distinguish a real pull from a pickup
    /// or putdown motion that briefly grazes the flexed threshold.
    private var rowMinSmoothedElbowAngleInFlexed: Float = .greatestFiniteMagnitude
    /// Subject-tracking gate. When the lifter exits frame between sets and a different
    /// person crosses the background, MediaPipe can latch onto that person and their
    /// elbow angle may oscillate near the row thresholds, producing a phantom rep.
    /// In that case neither wrist is tracked well: across the observed misfire the
    /// max of (left, right) wrist visibility never exceeded 0.78 across the entire
    /// cycle. Real reps consistently see at least one frame where the better wrist
    /// is ≥ 0.96 (lowest observed across 50+ real reps spanning floor/mount and
    /// front/oblique view buckets). 0.85 sits cleanly in that gap.
    private let rowMinBetterWristConfPeak: Float = 0.85
    private var rowMaxBetterWristConfInFlexed: Float = 0
    /// Shallow-brief-motion gate.
    /// Picking up the bar or setting it back down briefly bends the elbows enough to
    /// graze the flexed threshold (137-140° in observed tests), and the cycle finishes
    /// quickly because the user isn't actually pulling — they're just transitioning into
    /// or out of stance. A real pull either descends deeper than `rowShallowBriefMinAngle`
    /// (genuine contraction) OR lasts longer than `rowShallowBriefMaxDuration` (sustained
    /// pull, even if shallow). A cycle that fails BOTH criteria is rejected.
    /// Empirical split across observed row tests:
    ///   real reps (Floor Oblique): minA 94-107°, dur 1.0-1.3s
    ///   real reps (Mount Front, partial ROM): minA 114-137°, dur 0.70-1.27s
    ///   pickup/putdown false positives: minA 137-140°, dur 0.53-0.60s
    /// 130° / 0.65s sits in the empirical gap with margin on both sides.
    private let rowShallowBriefMaxDuration: TimeInterval = 0.65
    private let rowShallowBriefMinAngle: Float = 130
    private var rowLastRejectReason: String?  // transient, for debug CSV

    // MARK: - Deadlift rep state (bodyweight-style 2-state hysteresis on hip angle)
    //
    // Hip angle (shoulder→hip→knee) is camera-angle invariant. At setup the user is hinged
    // (~80–100°); at lockout they're standing tall (~170°). REP counted on the return to hinged.

    private enum DeadliftRepPhase: String { case hinged, lockedOut }
    private var deadliftRepPhase: DeadliftRepPhase = .hinged
    private var deadliftSmoothedHipAngle: Float?
    private var deadliftRepCycleStartTime: Date?
    private var deadliftBadFrameStreak: Int = 0
    private let deadliftEMAAlpha: Float = 0.4
    /// Enter LOCKED OUT when smoothed angle ≥ this.
    private let deadliftLockoutThreshold: Float = 155
    /// Return to HINGED when smoothed angle ≤ this — REP counted on this transition.
    private let deadliftHingeThreshold: Float = 115
    private let deadliftMinRepCycleDuration: TimeInterval = 0.7
    private let deadliftMaxRepCycleDuration: TimeInterval = 6.0
    private let deadliftMinRepInterval: TimeInterval = 0.7
    /// Deadlift-specific ankle drift tolerance, tighter than the global 0.05.
    /// Setup motions before the first real rep — stepping into position over the bar,
    /// shuffling stance, repositioning — produce ankle drift in the 0.04-0.05 range,
    /// just under the global tolerance, so they sneak through as reps. Real deadlift
    /// reps across the test set show drift ≤ 0.008 because the feet are planted once
    /// the user is set up. The 0.015 threshold sits in the empirical gap.
    private let deadliftAnkleStabilityTolerance: Float = 0.015

    // MARK: - Romanian deadlift rep state
    //
    // RDL starts at standing (~170°) and hinges down to ~90–110°, then returns. Mirror image of
    // deadlift — same shape but opposite directionality at rest.

    private enum RdlRepPhase: String { case standing, hinged }
    private var rdlRepPhase: RdlRepPhase = .standing
    private var rdlSmoothedHipAngle: Float?
    private var rdlRepCycleStartTime: Date?
    private var rdlBadFrameStreak: Int = 0
    /// Ankle Y baseline sampled while the user is verifiably standing (smoothed ≥ standing
    /// threshold). Locked in at the transition to `.hinged` so the rep-cycle drift gate
    /// measures against the user's most-planted foot position, not a transitional one.
    /// Mirrors how deadlift's `.lockedOut` transition naturally captures the stable upright
    /// stance.
    private var rdlStandingAnkleY: Float?
    /// Lowest (max image Y) wrist position observed while in `.hinged`. Used to reject
    /// bar pickup/putdown — motions where the bar travels to the floor — vs RDLs where
    /// the bar tracks the thighs and stops at mid-shin level.
    private var rdlMaxLowerWristYInHinge: Float = -.greatestFiniteMagnitude
    /// Deepest (smallest) smoothed hip angle observed while in `.hinged`. Pairs with the
    /// wrist signal above — a real RDL hinges deeper than a pickup/putdown.
    private var rdlMinSmoothedHipAngleInHinge: Float = .greatestFiniteMagnitude
    /// Timestamp of the last frame that deepened `rdlMinSmoothedHipAngleInHinge`. Combined with
    /// `rdlAscentStartTime` to measure how long the user dwelled at the bottom — pickups pause,
    /// real reps don't.
    private var rdlMinUpdateTime: Date?
    /// Timestamp of the first frame in this hinge cycle where smoothed angle rose more than
    /// `rdlBottomAscentMargin` above the running min. Set once per cycle.
    private var rdlAscentStartTime: Date?
    /// Largest excursion above the running min observed since the last min update, in degrees.
    /// Resets to 0 each time `rdlMinSmoothedHipAngleInHinge` deepens. Drives the bottom-rebound
    /// detector below: a deeper min established AFTER a non-trivial excursion means the user
    /// descended, started rising, then deepened again — a setup/positioning signature that
    /// the standard bottom-dwell measure (last-min-update to ascent-start) cannot see because
    /// the min keeps updating during the bounce.
    private var rdlMaxAngleAbovePrevMin: Float = 0
    /// Set true when a "descend → partial ascent → deepen further" pattern is observed in the
    /// current hinge cycle. Causes the rep to be rejected on the transition back to standing.
    private var rdlBottomReboundDetected: Bool = false
    /// Captures a rep candidate that has passed all in-cycle gates but is awaiting post-rep
    /// stability verification. Real reps leave the user planted; walking/putdown misfires see
    /// the ankles drift within the next second.
    private struct RdlPendingRep {
        let candidateTime: Date
        var minAnkleY: Float
        var maxAnkleY: Float
    }
    private var rdlPendingRep: RdlPendingRep?
    private let rdlEMAAlpha: Float = 0.4
    /// Enter HINGED when smoothed angle ≤ this.
    private let rdlHingeThreshold: Float = 130
    /// Return to STANDING when smoothed angle ≥ this — REP counted on this transition.
    /// Set well below true upright (170°+) so a front-mounted camera — where the torso lies
    /// along the depth axis and 3D depth foreshortens "stand-up" peaks to ~155-158° —
    /// still triggers the rep, especially on back-to-back reps where the lifter doesn't
    /// fully relockout between cycles.
    private let rdlStandingThreshold: Float = 150
    private let rdlMinRepCycleDuration: TimeInterval = 0.6
    private let rdlMaxRepCycleDuration: TimeInterval = 5.0
    private let rdlMinRepInterval: TimeInterval = 0.6
    /// RDL-specific ankle drift tolerance, looser than the global 0.05 because
    /// the hinge invites micro-balance shifts and front/floor-mount views
    /// amplify 2D ankle-Y jitter without representing actual walking.
    private let rdlAnkleStabilityTolerance: Float = 0.10
    /// Bar-floor-reach gate.
    /// Pickup/putdown carries the bar to the floor (lowest wrist drops well below the standing
    /// ankle line, AND the hinge is shallower than a real RDL because the lifter bends the knees
    /// and squats slightly to reach the bar). Real RDLs keep the wrists at mid-shin level (small
    /// wrist-ankle delta) and hinge deeper at the bottom. Reject only when BOTH signals fire so
    /// neither a deep pickup nor a wide-grip real rep alone can flip the decision.
    /// `wristDelta`: floor-mounted oblique cameras compress real-rep wristDeltas up to ~0.19
    /// (vs ~0.14 in chest-mounted views), so this threshold trades view-portability for wider
    /// real-rep coverage. The `minHingeAngle` companion catches the cases that overlap.
    /// `minHingeAngle`: extended high-rep oblique-view tests show real RDLs can bottom as
    /// shallow as 90-93° (warm-up reps, fatigue, and oblique-camera depth compression all
    /// reduce the apparent hinge depth), while pickup/putdown bottoms cluster at 101-127°
    /// because the lifter bends the knees and squats slightly to reach the bar. 97° splits
    /// the empirical gap with ~4° margin to real reps and ~4° margin to pickups. Both
    /// signals must still fire together (AND) — a deep wrist-Δ with a deep hinge is a real
    /// rep, not a pickup.
    private let rdlBarFloorReachWristDelta: Float = 0.16
    private let rdlBarFloorReachMinHingeAngle: Float = 97
    /// Bottom-dwell rejection.
    /// Real RDLs bounce off the bottom — time from min-angle-reached to clear ascent is < 0.7s.
    /// Pickup/positioning hinges pause at the deep position (checking grip, breathing, settling)
    /// for 1+ seconds before standing back up. Catching this dwell rejects pickup motions even
    /// when bar-floor-reach signals are compressed by oblique camera views.
    private let rdlMaxBottomDwell: TimeInterval = 0.8
    /// Angle increase above the running min that counts as the start of ascent, ending the
    /// bottom-dwell window. Set above EMA noise to avoid false ascent triggers at the bottom.
    private let rdlBottomAscentMargin: Float = 5.0
    /// Bottom-rebound detection. Real RDL reps descend monotonically to a single minimum, then
    /// ascend monotonically. Setup/positioning hinges before a set (lowering the bar, adjusting
    /// grip, "feeling out" the position) can look like a clean rep on every existing gate but
    /// betray themselves with a small bounce at the bottom: the user reaches a depth, starts to
    /// rise, then deepens further before standing up. This pattern is invisible to the standard
    /// bottom-dwell measure because that measure restarts every time the running min updates.
    /// `rdlBottomReboundExcursionDeg`: minimum excursion above the previous running min required
    /// to count as a "partial ascent" — observed misfire excursion was 1.75°; real reps either
    /// never re-deepen or have no measurable excursion at all, so 1.5° catches the misfire with
    /// margin to EMA noise (alpha=0.4 keeps smoothed jitter under ~1°).
    /// `rdlBottomReboundMinDecreaseDeg`: minimum decrease of the new running min vs the previous
    /// running min required to count as a "deepening." Filters out sub-degree noise blips that
    /// happen to land just below the prior min without representing a real second descent.
    private let rdlBottomReboundExcursionDeg: Float = 1.5
    private let rdlBottomReboundMinDecreaseDeg: Float = 0.5
    /// Post-rep ankle stability window.
    /// Pickup/walking-away misfires can produce a hinge cycle that looks like a real rep on every
    /// in-cycle signal, but the user's body drifts (walking, putting the bar down) within the next
    /// second. Defer rep credit by this duration and watch ankle Y; if it drifts more than the
    /// tolerance, discard the rep. If the user dives into the next hinge cycle within the window,
    /// credit the prior rep immediately (fast cadence) and start the new cycle.
    private let rdlPostRepStabilityWindow: TimeInterval = 1.0
    /// Real reps see 0.001-0.005 ankle Y drift over the post-rep second; walking misfires hit
    /// 0.025-0.07. The 0.015 threshold sits in the empirical gap.
    private let rdlPostRepAnkleDriftMax: Float = 0.015
    /// Hinge depth at or below which the post-rep stability check is skipped. The post-rep
    /// gate exists to catch pickup/putdown motions that mimic a rep on every in-cycle signal,
    /// and those motions have shallow hinges (knees-bent reach for the bar — minAngle ≥ 91°
    /// across all observed pickups). When the hinge dips this far below pickup territory, the
    /// rep is already proven real on its own merits, and the post-rep gate becomes a false-
    /// positive risk: the LAST rep of a set sees the user move (preparing to set the bar
    /// down) within the verification window, which trips the drift check on a real rep.
    /// 85° leaves 6° of margin to the lowest observed pickup hinge (91°) while covering
    /// every real rep in the test set up to 84° comfortably; reps shallower than 85° still
    /// run through the post-rep gate as before.
    private let rdlDeepHingeConfidenceAngle: Float = 85

    private let weightedRepBadFrameLimit: Int = 15

    // MARK: - Stationary-feet gate (shared across weighted exercises)
    //
    // Real-world test data: weighted exercises counted false reps when the user walked into / out
    // of position between reps (or put the bar down at the end of a set). Translating across the
    // floor changes ankle Y in normalized image coords; a real rep keeps feet planted.
    //
    // We sample the ankle Y on each frame in the active rep cycle and reject the rep if the ankle
    // Y range exceeds `ankleStabilityTolerance`. Used by barbell back squat, row, deadlift, RDL,
    // and bench press (where feet are planted on the floor).

    private var currentRepCycleAnkleYMin: Float = .greatestFiniteMagnitude
    private var currentRepCycleAnkleYMax: Float = -.greatestFiniteMagnitude
    /// 0.05 ≈ 5% of frame height. A planted-foot rep keeps ankle Y stable to ~1–2%; walking
    /// toward/away from the camera quickly exceeds this even in a single frame pair.
    private let ankleStabilityTolerance: Float = 0.05

    // MARK: - Automatic Set Detection Properties
    private var inactivityDetector = InactivityDetector()
    private var consecutiveGoodReps = 0
    private var lastRepTime: Date?
    private var setStartTime: Date?
    private var restStartTime: Date?
    private let restPeriodDuration: TimeInterval = 60.0 // 60 seconds rest
    // Allow set-start after first detected rep to avoid deadlocking analysis
    // when cadence/filtering drops the second early rep.
    private let minRepsForSetStart = 1
    private let minTimeBetweenReps: TimeInterval = 0.8  // Minimum 0.8 seconds between reps (MORE SENSITIVE)
    
    // MARK: - Rep Validation Properties
    private var lastRepValidationTime: Date?
    private var repValidationThreshold: TimeInterval = 0.5
    private var movementThreshold: Float = 0.05  // Very sensitive to movement
    private var poseConfidenceThreshold: Float = 0.15  // Even lower confidence threshold for better detection (MORE SENSITIVE)
    /// Require this many consecutive frames in deep/shallow before rep-state transition (reduces false reps).
    /// Shared by bench press.
    private let consistentFramesForRepTransition: Int = 3

    // MARK: - Squat rep counting (hip depth hysteresis, tunable)
    /// Normalized hip depth: shallow / standing band for “top”.
    private let repTopThreshold: Float = 0.14
    /// Depth at or above this leaves top and starts descent.
    private let repStartThreshold: Float = 0.20
    /// Depth at or above this (confirmed) marks bottom for counting.
    private let repBottomThreshold: Float = 0.34
    private let framesForBottomConfirmation: Int = 2
    private let framesForTopConfirmation: Int = 2
    /// Secondary: barbell / bench squat rep quality tag (does not gate rep counting).
    private let hipKneeBottomToleranceNormalizedBarbell: Float = 0.06

    // MARK: - Squat rep depth state machine
    private var squatRepPhase: SquatRepPhase = .idleAtTop
    private var squatRepTopHoldFrames: Int = 0
    private var squatRepBottomHoldFrames: Int = 0
    /// Max hip depth seen during the current squat rep cycle (for analysis / debug).
    private var squatRepMaxDepthThisCycle: Float = 0
    /// True if any frame in the cycle met hip–knee parallel tolerance (secondary quality).
    private var squatRepCycleHipKneeParallelMet: Bool = false
    /// Captured when a rep is counted; read by `commitBodyweightRepIfNeeded`.
    private var lastCountedRepHipKneeDepthQualityMet: Bool = false
    
    // MARK: - Close-Grip Bench Press Rep Detection State
    
    /// Tracks whether the bar has reached chest (bottom position) in the current rep cycle.
    private var reachedBottomThisCycleBenchPress: Bool = false
    /// Consistent-frame counters for bench rep transitions (avoid false reps from jitter).
    private var consecutiveFramesAtBottomBenchPress: Int = 0
    private var consecutiveFramesAtTopBenchPress: Int = 0
    
    /// Timestamps for tracking eccentric (lowering) and concentric (pressing) phases.
    /// Used to measure tempo: eccentric should be ≥1s, concentric should be ≤2s.
    private var benchPressEccentricStartTime: CFTimeInterval?
    private var benchPressBottomTime: CFTimeInterval?
    
    /// Stores wrist Y position at bottom of rep for relative lockout detection.
    /// Used in tripod view to detect lockout even if absolute threshold isn't met.
    /// Cleared after rep validation.
    private var benchPressBottomWristY: Float?
    
    // MARK: - Audio Feedback Properties
    private var lastSpokenRep: Int = 0
    private var repFeedbackInterval = 5 // Speak every 5 reps
    
    private var analysisQueue = DispatchQueue(label: "pose.analysis", qos: .userInteractive)
    
    // MARK: - MediaPipe Pose Properties
    
    private var poseLandmarker: PoseLandmarker?
    private let poseAdapter = MediaPipePoseAdapter()
    
    /// Higher alpha (0.35) so lower body tracks with less lag; deep squats update overlay and rep logic faster.
    private let jointSmoother = JointSmoother(alpha: 0.35, twoStage: true)
    /// More responsive overlay so hip/knee positions follow motion better (alphaWhenMoving 0.35).
    private let overlayLandmarkSmoother = Landmark2DSmoother(alphaWhenMoving: 0.35, alphaWhenStill: 0.1)
    /// Hold last stable form/landmarks for this many frames when pose is missing or low confidence.
    private let holdStablePoseFrames: Int = 3
    private var framesSinceGoodPose: Int = 0
    private(set) var currentAnalysisSource: PoseAnalysisSource = .pose3D
    
    /// Monotonic frame counter used as timestamp for MediaPipe livestream API.
    private var frameTimestampMs: Int = 0

    /// Latest smoothed skeleton from the analysis queue, used by squat rep detection.
    private var lastSmoothedSkeleton: Skeleton3D?
    
    // 3D depth thresholds (hip-displacement / legLength scale).
    private let deepDepthThreshold3D: Float = 0.45
    private let shallowDepthThreshold3D: Float = 0.20
    
    // Cue speaking state
    private var lastCueSpokenAt: Date?
    private var lastCueText: String = ""
    private let cueCooldownSeconds: TimeInterval = 6.0
    private let cueByIssue: [IssueCode: String] = [
        .kneeValgus:        "Push your knees out",
        .kneeVarus:         "Keep your knees over your toes",
        .forwardLean:       "Lift your chest",
        .insufficientDepth: "Squat a little deeper"
    ]
    
    // Aggregation for mid-set feedback (collected during the set, spoken between sets).
    // `PositiveKey` is defined in `SetEndFeedback.swift` so the coaching manager can read it.
    private var issueCounts: [IssueCode: Int] = [:]
    private var positiveCounts: [PositiveKey: Int] = [:]

    // Running mean of FormAnalysis.overallScore across the set (for Stage 2 gate).
    private var sumOverallScore: Double = 0
    private var overallScoreSamples: Int = 0
    
    // Tempo tracking for hypertrophy (milliseconds)
    private var repStartTime: CFTimeInterval?
    private var bottomTime: CFTimeInterval?
    private var lastDepth: Float = 0
    private var sumEccentricMs: Double = 0  // Total time going down
    private var sumPauseMs: Double = 0      // Total time paused at bottom
    private var sumConcentricMs: Double = 0 // Total time coming up
    private var tempoRepSamples: Int = 0
    // Legacy 2D tempo thresholds removed; now uses deepDepthThreshold3D / shallowDepthThreshold3D.

    // Hip-based depth calibration (self-calibrates to standing reference each set)
    private var standingHipHeight: Float?
    private var standingLegLength: Float?
    /// Stable-frame gate for standing calibration (Bug 1 fix).
    private var standingCalibrationCandidate: Float?
    private var standingCalibrationFrames: Int = 0
    private let standingCalibrationRequired: Int = 5
    private let standingCalibrationTolerance: Float = 0.03 // 3% band

    // ROM tracking (depth-based)
    private var sumBottomDepth: Double = 0
    private var bottomDepthSamples: Int = 0
    private var deepFrameCount: Int = 0
    private var totalDepthSamples: Int = 0
    private var currentRepBottomDepthMax: Float = 0

    /// Set by updateTempoTracking when a squat rep completes (before resetting currentRepBottomDepthMax). Used by bodyweight rep commit.
    private var lastCompletedRepDepthAtBottom: Float?

    // MARK: - Bodyweight squat rep-level aggregation (phase-relevant metrics)
    private var bodyweightRepHistory: [BodyweightRepMetrics] = []
    private var bodyweightRepPhase: RepPhase = .idle
    private var currentRepBackAngleMax: Float?
    private var currentRepKneeAlignmentWorst: Float?
    private var bodyweightRepFrameCount: Int = 0
    private var bodyweightKneeWindowSampleCount: Int = 0
    /// Peak `calculateHipDepth3D` during current in-progress rep (for commit).
    private var bodyweightCurrentRepPeakDepth: Float = 0
    private let bodyweightMinFramesInRep = 4
    private let bodyweightMinDepthForViableBottom: Float = 0.22
    private let bodyweightKneeWindowDepthThreshold: Float = 0.24

    override init() {
        super.init()
        // Load MediaPipe model on a background queue so app launch is not blocked.
        // iOS kills the app (SIGKILL) if launch takes too long; the model load is heavy.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setupMediaPipe()
        }
    }
    
    // MARK: - MediaPipe Setup
    
    private func setupMediaPipe() {
        guard let modelPath = Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task") else {
            return
        }
        
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .liveStream
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.5
        // Slightly lower presence/tracking so we keep landmarks in deep squat (lower body can be partly occluded).
        options.minPosePresenceConfidence = 0.4
        options.minTrackingConfidence = 0.4
        options.poseLandmarkerLiveStreamDelegate = self
        
        do {
            poseLandmarker = try PoseLandmarker(options: options)
        } catch {
        }
    }
    
    // MARK: - Pose Detection
    
    func analyzeFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let poseLandmarker = poseLandmarker else { return }

        // Track whether the connection actually rotated the buffer to portrait (varies by device, see property doc).
        let isPortraitBuffer = CVPixelBufferGetHeight(pixelBuffer) > CVPixelBufferGetWidth(pixelBuffer)
        if isPortraitBuffer != landmarkBufferIsPortrait {
            DispatchQueue.main.async { [weak self] in
                self?.landmarkBufferIsPortrait = isPortraitBuffer
            }
        }

        frameTimestampMs += 33 // ~30 fps; must be monotonically increasing
        let ts = frameTimestampMs

        do {
            let mpImage = try MPImage(pixelBuffer: pixelBuffer)
            try poseLandmarker.detectAsync(image: mpImage, timestampInMilliseconds: ts)
        } catch {
            // MediaPipe drops the frame if the previous one is still being processed
        }
    }
    
    /// Called by the PoseLandmarker livestream delegate on a serial queue.
    fileprivate func handleMediaPipeResult(_ result: PoseLandmarkerResult?, timestampMs: Int, error: Error?) {
        guard let result = result,
              let adapted = poseAdapter.adapt(result, timestampMs: timestampMs) else {
            framesSinceGoodPose += 1
            if framesSinceGoodPose >= holdStablePoseFrames {
                DispatchQueue.main.async {
                    self.poseDetected = false
                    self.currentFormAnalysis = nil
                    self.currentNormalizedLandmarks = nil
                    self.currentBarbellLine = nil
                }
            }
            return
        }
        
        guard adapted.skeleton.meetsMinimumRequirements(for: trackedExerciseType) else {
            framesSinceGoodPose += 1
            if framesSinceGoodPose >= holdStablePoseFrames {
                DispatchQueue.main.async {
                    self.poseDetected = false
                    self.currentFormAnalysis = nil
                    self.currentNormalizedLandmarks = nil
                    self.currentBarbellLine = nil
                }
            }
            return
        }
        
        framesSinceGoodPose = 0
        currentAnalysisSource = .pose3D
        
        let smoothed = jointSmoother.smooth(adapted.skeleton)
        lastSmoothedSkeleton = smoothed
        let landmarks = overlayLandmarkSmoother.smooth(adapted.overlayLandmarks)
        // Barbell back squat reuses the bodyweight knee-angle rep algorithm, so it also
        // needs viewpoint-aware profiles.
        if trackedExerciseType == .bodyweight || trackedExerciseType == .barbell {
            updateBodyweightViewpointAndExtension(overlay: landmarks, skeleton: smoothed, confidence: adapted.perJointConfidence)
        }
        let formAnalysis = formAnalysisFrom3D(skeleton: smoothed)
        
        let tempoDepth: Float = {
            switch trackedExerciseType {
            case .bodyweight, .barbell, .benchPress, .row, .deadlift, .romanianDeadlift:
                return calculateHipDepth3D(smoothed)
            case .closeGripBenchPress:
                return formAnalysis.depth
            }
        }()
        updateTempoTracking(currentDepth: tempoDepth)
        
        let publishedBarLine: BarbellLine? = trackedExerciseType.usesBarbell ? adapted.barbellLine : nil
        // Sample ankle Y on the analysis queue so the rep-cycle stability gate is in sync with rep state.
        sampleAnkleStability(landmarks: landmarks)

        DispatchQueue.main.async {
            self.poseDetected = true
            self.currentFormAnalysis = formAnalysis
            self.currentNormalizedLandmarks = landmarks
            self.currentBarbellLine = publishedBarLine
            self.inactivityDetector.updateLastActivity()
        }
        
        aggregateFeedback(from: formAnalysis)

        // Build debug frame before rep counting so we capture pre-event state.
        var debugRepCounted = false
        var debugCommitValid: Bool?
        bwLastRejectReason = nil // Clear transient reject reason from previous frame
        rdlLastRejectReason = nil
        rowLastRejectReason = nil

        // Rep counting should not advance while we're in setup mode (e.g. test overlays).
        // Set start may be explicit (Track `startManualSet`) or rep-driven (`checkForNextSetStart` after reps while `.waiting`).
        // The squat rep state machine is advanced only from this path (never from `checkForNextSetStart`).
        if !SharedCameraSessionManager.shared.isInSetupMode,
           !SharedCameraSessionManager.shared.suppressRepCounting {
            let now = Date()
            if validateRep(skeleton: smoothed, overlay: landmarks, confidence: adapted.perJointConfidence, formAnalysis: formAnalysis, now: now) {
                debugRepCounted = true
                if trackedExerciseType == .bodyweight {
                    let preValid = bodyweightRepHistory.count
                    commitBodyweightRepIfNeeded()
                    debugCommitValid = bodyweightRepHistory.count > preValid
                }
                DispatchQueue.main.async {
                    self.handleRepDetected()
                }
            }

            DispatchQueue.main.async {
                if !SharedCameraSessionManager.shared.trackExplicitSetActive {
                    self.checkForSetEnd()
                }
                self.checkForNextSetStart()
            }
        }

        // Log debug frame (zero overhead when disabled).
        if SquatRepDebugLogger.shared.isEnabled {
            var frame = SquatRepDebugFrame(
                timestamp: CACurrentMediaTime(),
                frameIndex: SquatRepDebugLogger.shared.nextFrameIndex
            )
            frame.exerciseType = "\(trackedExerciseType)"
            frame.viewBucket = viewpointSmoother.activeBucket.rawValue

            // 2D overlay landmarks (useful for any exercise)
            frame.overlayShoulderY = Float(((landmarks["leftShoulder"]?.y ?? 0) + (landmarks["rightShoulder"]?.y ?? 0)) / 2)
            frame.overlayHipY = Float(((landmarks["leftHip"]?.y ?? 0) + (landmarks["rightHip"]?.y ?? 0)) / 2)
            frame.overlayKneeY = Float(((landmarks["leftKnee"]?.y ?? 0) + (landmarks["rightKnee"]?.y ?? 0)) / 2)
            frame.overlayAnkleY = Float(((landmarks["leftAnkle"]?.y ?? 0) + (landmarks["rightAnkle"]?.y ?? 0)) / 2)
            frame.overlayLegSpan = bodyweightOverlayLegSpanY(landmarks)
            if let lw = landmarks["leftWrist"]  { frame.overlayLeftWristY  = Float(lw.y) }
            if let rw = landmarks["rightWrist"] { frame.overlayRightWristY = Float(rw.y) }
            frame.leftWristConfidence  = adapted.perJointConfidence["leftWrist"]
            frame.rightWristConfidence = adapted.perJointConfidence["rightWrist"]

            // Stationary-feet gate snapshot (empty when not in active cycle).
            if currentRepCycleAnkleYMin != .greatestFiniteMagnitude {
                frame.ankleStabilityMinY = currentRepCycleAnkleYMin
                frame.ankleStabilityMaxY = currentRepCycleAnkleYMax
            }

            // Per-exercise primary signal + thresholds.
            switch trackedExerciseType {
            case .bodyweight:
                let profile = activeBodyweightRepProfile
                frame.primaryAngleRaw = bwRawKneeAngle
                frame.primaryAngleSmoothed = bwSmoothedKneeAngle
                frame.selectedSide = bwSelectedSide
                frame.phase = bwRepPhase.rawValue
                frame.thresholdEnter = profile.downAngleThreshold
                frame.thresholdExit = profile.upAngleThreshold
                frame.hipDepth3D = tempoDepth
                frame.standingHipHeight = standingHipHeight
                frame.standingLegLength = standingLegLength
                frame.peakDepthThisRep = bodyweightCurrentRepPeakDepth
                frame.repFrameCount = bodyweightRepFrameCount
                frame.kneeWindowSamples = bodyweightKneeWindowSampleCount
                frame.rejectReason = bwLastRejectReason
            case .barbell:
                let profile = activeBodyweightRepProfile
                frame.primaryAngleRaw = bwRawKneeAngle
                frame.primaryAngleSmoothed = bwSmoothedKneeAngle
                frame.selectedSide = bwSelectedSide
                frame.phase = bwRepPhase.rawValue
                frame.thresholdEnter = profile.downAngleThreshold
                frame.thresholdExit = profile.upAngleThreshold
                frame.hipDepth3D = tempoDepth
                frame.rejectReason = bwLastRejectReason
            case .deadlift:
                frame.primaryAngleSmoothed = deadliftSmoothedHipAngle
                frame.phase = deadliftRepPhase.rawValue
                frame.thresholdEnter = deadliftLockoutThreshold
                frame.thresholdExit = deadliftHingeThreshold
            case .romanianDeadlift:
                frame.primaryAngleSmoothed = rdlSmoothedHipAngle
                frame.phase = rdlRepPhase.rawValue
                frame.thresholdEnter = rdlHingeThreshold
                frame.thresholdExit = rdlStandingThreshold
                frame.rejectReason = rdlLastRejectReason
            case .row:
                frame.primaryAngleSmoothed = rowSmoothedElbowAngle
                frame.phase = rowRepPhase.rawValue
                frame.thresholdEnter = rowFlexedThreshold
                frame.thresholdExit = rowExtendedThreshold
                frame.rejectReason = rowLastRejectReason
            case .benchPress, .closeGripBenchPress:
                frame.benchDepth = formAnalysis.depth
                frame.phase = reachedBottomThisCycleBenchPress ? "atBottom" : "atTop"
                // Bench thresholds live inside `validateBenchPressRep` (0.65 / 0.25);
                // surface them so the CSV is self-describing.
                frame.thresholdEnter = 0.65
                frame.thresholdExit = 0.25
            }

            frame.repCounted = debugRepCounted
            frame.repCommitValid = debugCommitValid
            SquatRepDebugLogger.shared.log(frame)
        }

        // Telemetry observation hook. No-op when consent is off (gated inside
        // TelemetryCoordinator). Strictly observational — reads existing local
        // values, doesn't touch rep-detection or form-analysis state.
        TelemetryCoordinator.shared.recordFrame(timestampMs: timestampMs, formAnalysis: formAnalysis)
        if debugRepCounted {
            TelemetryCoordinator.shared.recordRepEvent(repIndex: repCount)
        }
        if let rejectReason = bwLastRejectReason ?? rdlLastRejectReason ?? rowLastRejectReason {
            TelemetryCoordinator.shared.recordRepRejection(reason: rejectReason)
        }
    }

    // MARK: - Form Analysis (2D overlay)

    private func analyzeFormFrom2DOverlay(_ points: [String: CGPoint]) -> FormAnalysis {
        switch trackedExerciseType {
        case .bodyweight:
            return analyzeBodyweightSquatForm(points)
        case .barbell:
            return analyzeBarbellSquatForm(points)
        case .benchPress:
            return analyzeBenchPressForm(points)
        case .closeGripBenchPress:
            return analyzeCloseGripBenchPressForm(points)
        case .row:
            return analyzeBarbellRowForm(points)
        case .deadlift:
            return analyzeDeadliftForm(points)
        case .romanianDeadlift:
            return analyzeRomanianDeadliftForm(points)
        }
    }
    
    private func analyzeBodyweightSquatForm(_ points: [String: CGPoint]) -> FormAnalysis {
        let depth = calculateBodyweightDepth(points)
        let backAngle = calculateBodyweightBackAngle(points)
        let kneeAlignment = calculateBodyweightKneeAlignment(points)
        let overallScore = calculateBodyweightOverallScore(depth: depth, backAngle: backAngle, kneeAlignment: kneeAlignment)
        let issues = detectBodyweightIssues(depth: depth, backAngle: backAngle, kneeAlignment: kneeAlignment)
        let summary = generateBodyweightFormSummary(depth: depth, backAngle: backAngle, overallScore: overallScore)
        
        return FormAnalysis(
            depth: depth, backAngle: backAngle, kneeAlignment: kneeAlignment,
            overallScore: overallScore, issues: issues, summary: summary,
            repCount: repCount,
            avgEccentricMs: tempoRepSamples > 0 ? Float(sumEccentricMs / Double(tempoRepSamples)) : nil,
            avgPauseMs: tempoRepSamples > 0 ? Float(sumPauseMs / Double(tempoRepSamples)) : nil,
            avgConcentricMs: tempoRepSamples > 0 ? Float(sumConcentricMs / Double(tempoRepSamples)) : nil,
            avgBottomDepth: bottomDepthSamples > 0 ? Float(sumBottomDepth / Double(bottomDepthSamples)) : nil,
            deepRepRatio: totalDepthSamples > 0 ? Float(deepFrameCount) / Float(totalDepthSamples) : nil
        )
    }
    
    private func analyzeBarbellSquatForm(_ points: [String: CGPoint]) -> FormAnalysis {
        let depth = calculateDepth(points)
        let backAngle = calculateBackAngle(points)
        let overallScore = calculateOverallScore(depth: depth, backAngle: backAngle)
        let summary = generateFormSummary(depth: depth, backAngle: backAngle, overallScore: overallScore)
        
        return FormAnalysis(
            depth: depth, backAngle: backAngle, kneeAlignment: 0.0,
            overallScore: overallScore, issues: [], summary: summary,
            repCount: repCount,
            avgEccentricMs: nil as Float?, avgPauseMs: nil as Float?, avgConcentricMs: nil as Float?,
            avgBottomDepth: nil as Float?, deepRepRatio: nil as Float?
        )
    }
    
    // MARK: - Close-Grip Bench Press Form Analysis
    
    /// Analyzes close-grip bench press form with view-specific adjustments for camera angle.
    ///
    /// Form Metrics (weighted scoring):
    /// - **Grip width (20%)**: Should be just outside ribs (0.8-1.0x shoulder width)
    /// - **Elbow position (20%)**: Should be flush to sides (not flared out)
    /// - **Full ROM (30%)**: Elbows locked at top, bar touches chest at bottom
    /// - **Eccentric tempo (15%)**: Lowering phase should be ≥1 second
    /// - **Concentric tempo (15%)**: Pressing phase should be ≤2 seconds
    ///
    /// View-specific adjustments account for camera angle differences:
    /// - Rack view (top-down): Adjusts for compressed width perception
    /// - Floor view (bottom-up): Adjusts for expanded width perception
    /// - Tripod view (side): Standard calculations
    private func analyzeCloseGripBenchPressForm(_ points: [String: CGPoint]) -> FormAnalysis {
        // Calculate close-grip bench press specific metrics
        let gripWidthScore = calculateCloseGripWidthScore(points)
        let elbowPositionScore = calculateElbowPositionScore(points)
        let romScore = calculateBenchPressROMScore(points)
        
        // Get tempo scores (from accumulated tracking data)
        let eccentricScore = calculateBenchPressEccentricScore()
        let concentricScore = calculateBenchPressConcentricScore()
        
        // Calculate overall score with weights:
        // - Grip width: 20%
        // - Elbow position: 20%
        // - Full ROM: 30%
        // - Eccentric tempo: 15%
        // - Concentric tempo: 15%
        let overallScore = (gripWidthScore * 0.20) +
                           (elbowPositionScore * 0.20) +
                           (romScore * 0.30) +
                           (eccentricScore * 0.15) +
                           (concentricScore * 0.15)
        
        
        var issues: [IssueCode] = []
        if gripWidthScore < CoachingContract.Threshold.gripTooWide { issues.append(.gripTooWide) }
        if elbowPositionScore < CoachingContract.Threshold.elbowsFlaring { issues.append(.elbowsFlaring) }
        if romScore < CoachingContract.Threshold.incompleteRom { issues.append(.incompleteRom) }
        issues.append(contentsOf: detectTempoIssues())

        let summary = generateCloseGripBenchPressSummary(
            gripScore: gripWidthScore,
            elbowScore: elbowPositionScore,
            romScore: romScore,
            overallScore: overallScore
        )

        // Use the depth field to store wrist Y position for rep detection
        let depth = calculateBenchPressDepth(points)
        
        return FormAnalysis(
            depth: depth,
            backAngle: 0.0, // Not relevant for bench press
            kneeAlignment: 0.0, // Not relevant for bench press
            overallScore: overallScore,
            issues: issues,
            summary: summary,
            repCount: repCount,
            avgEccentricMs: tempoRepSamples > 0 ? Float(sumEccentricMs / Double(tempoRepSamples)) : nil,
            avgPauseMs: tempoRepSamples > 0 ? Float(sumPauseMs / Double(tempoRepSamples)) : nil,
            avgConcentricMs: tempoRepSamples > 0 ? Float(sumConcentricMs / Double(tempoRepSamples)) : nil,
            avgBottomDepth: nil,
            deepRepRatio: nil
        )
    }
    
    /// Calculates grip width score for close-grip bench press.
    /// 
    /// **Ideal Grip:** 0.8-1.0x shoulder width (just outside ribs)
    /// 
    /// **Scoring (Lenient):**
    /// - Acceptable range: 0.7-1.2x shoulder width (score: 1.0)
    /// - Too narrow: Minimum score 0.5 (was 0.3)
    /// - Too wide: Minimum score 0.5 (was 0.3)
    /// 
    /// **View Adjustments:** Applies camera angle corrections for rack/floor/tripod views.
    private func calculateCloseGripWidthScore(_ points: [String: CGPoint]) -> Float {
        guard let leftWrist = points["leftWrist"],
              let rightWrist = points["rightWrist"],
              let leftShoulder = points["leftShoulder"],
              let rightShoulder = points["rightShoulder"] else {
            return 0.5 // Default score if points not detected
        }
        
        // Calculate grip width relative to shoulder width
        let gripWidth = abs(leftWrist.x - rightWrist.x)
        let shoulderWidth = abs(leftShoulder.x - rightShoulder.x)
        
        guard shoulderWidth > 0 else { return 0.5 }
        
        // Ideal grip width for close-grip is 0.8-1.0x shoulder width (just outside ribs)
        // Regular bench press would be 1.5x+ shoulder width
        let gripRatio = Float(gripWidth / shoulderWidth)
        
        // View-specific adjustments
        let adjustedGripRatio: Float
        switch benchPressViewType {
        case .rack:
            // Top-down view may compress perceived width
            adjustedGripRatio = gripRatio * 1.1
        case .floor:
            // Bottom-up view may expand perceived width
            adjustedGripRatio = gripRatio * 0.95
        case .tripod:
            // Side view is most accurate
            adjustedGripRatio = gripRatio
        }
        
        // Score calculation: ideal is 0.8-1.0, penalize outside this range
        // Made more lenient: wider acceptable range and less harsh penalties
        if adjustedGripRatio >= 0.7 && adjustedGripRatio <= 1.2 {
            return 1.0 // Perfect or acceptable close-grip width
        } else if adjustedGripRatio < 0.7 {
            // Grip too narrow - more lenient
            return max(0.5, adjustedGripRatio / 0.7)
        } else {
            // Grip too wide - more lenient
            let overWidth = adjustedGripRatio - 1.2
            return max(0.5, 1.0 - (overWidth * 1.0))
        }
    }
    
    /// Calculates elbow position score for close-grip bench press.
    /// 
    /// **Ideal Position:** Elbows flush to sides (not flared out)
    /// 
    /// **Scoring (Lenient):**
    /// - Acceptable range: flare ratio ≤ 0.6 (score: 1.0)
    /// - Slightly flared (0.6-0.8): Score 0.7-1.0
    /// - Significantly flared (>0.8): Minimum score 0.5 (was 0.3)
    /// 
    /// **View Adjustments:** Applies camera angle corrections for rack/floor/tripod views.
    private func calculateElbowPositionScore(_ points: [String: CGPoint]) -> Float {
        guard let leftElbow = points["leftElbow"],
              let rightElbow = points["rightElbow"],
              let leftShoulder = points["leftShoulder"],
              let rightShoulder = points["rightShoulder"],
              let leftHip = points["leftHip"],
              let rightHip = points["rightHip"] else {
            return 0.5 // Default score if points not detected
        }
        
        // Calculate elbow distance from torso midline
        let torsoMidlineX = (leftShoulder.x + rightShoulder.x + leftHip.x + rightHip.x) / 4.0
        let shoulderWidth = abs(leftShoulder.x - rightShoulder.x)
        
        guard shoulderWidth > 0 else { return 0.5 }
        
        // Calculate how far elbows are from the body
        let leftElbowOffset = abs(leftElbow.x - torsoMidlineX)
        let rightElbowOffset = abs(rightElbow.x - torsoMidlineX)
        let avgElbowOffset = (leftElbowOffset + rightElbowOffset) / 2.0
        
        // Normalize to shoulder width
        let elbowFlareRatio = Float(avgElbowOffset / shoulderWidth)
        
        // View-specific adjustments
        let adjustedFlareRatio: Float
        switch benchPressViewType {
        case .rack:
            // Top-down view makes elbows appear more tucked
            adjustedFlareRatio = elbowFlareRatio * 1.15
        case .floor:
            // Bottom-up view makes elbows appear more flared
            adjustedFlareRatio = elbowFlareRatio * 0.9
        case .tripod:
            adjustedFlareRatio = elbowFlareRatio
        }
        
        // For close-grip, elbows should be tucked (ratio < 0.5)
        // Score calculation: ideal is 0.3-0.5 (flush to sides)
        // Made more lenient: accept wider range and less harsh penalties
        if adjustedFlareRatio <= 0.6 {
            return 1.0 // Perfect or acceptable elbow position
        } else if adjustedFlareRatio <= 0.8 {
            // Slightly flared - more lenient
            return max(0.7, 1.0 - ((adjustedFlareRatio - 0.6) * 0.75))
        } else {
            // Significantly flared - more lenient
            return max(0.5, 0.85 - ((adjustedFlareRatio - 0.8) * 0.7))
        }
    }
    
    /// Calculates range of motion score for close-grip bench press.
    /// 
    /// **Checks:** Full lockout at top and chest touch at bottom
    /// 
    /// **Scoring (Lenient for Tripod View):**
    /// - Good lockout: Elbow extension > 0.05 (score: 1.0)
    /// - Partial lockout: Extension > 0 (score: 0.8-1.0, was 0.7)
    /// - Incomplete extension: Minimum score 0.6 (was 0.3)
    /// 
    /// **View-Specific:** Uses different reference points for rack/floor/tripod camera angles.
    private func calculateBenchPressROMScore(_ points: [String: CGPoint]) -> Float {
        guard let leftWrist = points["leftWrist"],
              let rightWrist = points["rightWrist"],
              let leftElbow = points["leftElbow"],
              let rightElbow = points["rightElbow"],
              let leftShoulder = points["leftShoulder"],
              let rightShoulder = points["rightShoulder"] else {
            return 0.5 // Default score if points not detected
        }
        
        // Calculate average positions
        let avgWristY = Float((leftWrist.y + rightWrist.y) / 2.0)
        let avgElbowY = Float((leftElbow.y + rightElbow.y) / 2.0)
        let avgShoulderY = Float((leftShoulder.y + rightShoulder.y) / 2.0)
        
        // View-specific ROM assessment
        switch benchPressViewType {
        case .rack:
            // Top-down view: Use Y position relative to shoulders
            // At lockout: wrists should be above (lower Y) than shoulders
            // At bottom: wrists should be at or below shoulder level
            let lockoutScore: Float = avgWristY < avgShoulderY ? 1.0 : max(0.3, 1.0 - (avgWristY - avgShoulderY) * 2)
            return lockoutScore
            
        case .floor:
            // Bottom-up view: Similar assessment but inverted Y
            let lockoutScore: Float = avgWristY > avgShoulderY ? 1.0 : max(0.3, 1.0 - (avgShoulderY - avgWristY) * 2)
            return lockoutScore
            
        case .tripod:
            // Side view: Assess elbow extension
            // At lockout: wrist should be significantly above elbow (lower Y in normalized image coords)
            // Made more lenient: accept smaller extension and give higher minimum scores
            let elbowExtension = avgElbowY - avgWristY
            if elbowExtension > 0.05 {
                return 1.0 // Good lockout
            } else if elbowExtension > 0 {
                return max(0.8, 0.7 + (elbowExtension * 2.0)) // Partial lockout - more lenient
            } else {
                return max(0.6, 0.7 + elbowExtension) // Incomplete extension - more lenient
            }
        }
    }
    
    /// Calculates bench press depth using average wrist Y position for rep detection.
    /// Higher Y = deeper/lower bar position (normalized image coords, Y down).
    private func calculateBenchPressDepth(_ points: [String: CGPoint]) -> Float {
        guard let leftWrist = points["leftWrist"],
              let rightWrist = points["rightWrist"] else {
            return 0.5
        }
        
        // Average wrist Y position (higher Y = deeper/lower bar in normalized image coords)
        return Float((leftWrist.y + rightWrist.y) / 2.0)
    }
    
    /// Calculates eccentric (lowering) tempo score.
    /// 
    /// **Target:** ≥1000ms (1 second) for controlled lowering
    /// 
    /// **Scoring (Lenient):**
    /// - ≥800ms: Score 1.0 (was ≥1000ms)
    /// - ≥600ms: Score 0.9
    /// - ≥400ms: Score 0.75
    /// - <400ms: Minimum score 0.6 (was 0.3)
    /// 
    /// **Default:** Returns 0.8 if no tempo data available (was 0.7)
    private func calculateBenchPressEccentricScore() -> Float {
        guard tempoRepSamples > 0 else { return 0.8 }
        
        let avgEccentricMs = sumEccentricMs / Double(tempoRepSamples)
        
        if avgEccentricMs >= 800 {
            return 1.0
        } else if avgEccentricMs >= 600 {
            return 0.9
        } else if avgEccentricMs >= 400 {
            return 0.75
        } else {
            return max(0.6, Float(avgEccentricMs / 800.0))
        }
    }
    
    /// Calculates concentric (pressing) tempo score.
    /// 
    /// **Target:** ≤2000ms (2 seconds) for explosive pressing
    /// 
    /// **Scoring (Lenient):**
    /// - ≤3000ms: Score 1.0 (was ≤2000ms)
    /// - ≤4000ms: Score 0.9
    /// - ≤5000ms: Score 0.75
    /// - >5000ms: Minimum score 0.6 (was 0.3)
    /// 
    /// **Default:** Returns 0.8 if no tempo data available (was 0.7)
    private func calculateBenchPressConcentricScore() -> Float {
        guard tempoRepSamples > 0 else { return 0.8 }
        
        let avgConcentricMs = sumConcentricMs / Double(tempoRepSamples)
        
        if avgConcentricMs <= 3000 {
            return 1.0
        } else if avgConcentricMs <= 4000 {
            return 0.9
        } else if avgConcentricMs <= 5000 {
            return 0.75
        } else {
            return max(0.6, Float(3000.0 / avgConcentricMs))
        }
    }

    /// Goal-aware tempo issue detection. Only fires on clear deviations; the
    /// LLM at set end weighs rep number, effort, and context to decide what
    /// to actually say. When `tempoTargets` is nil or no tempo samples exist,
    /// nothing fires.
    ///
    /// Trip rules come from `TempoTargets`:
    /// - ecc < `minEccentricMs * 0.5`   → `.eccentricTooFast`
    /// - con > `maxConcentricMs * 1.5`  → `.concentricTooSlow`
    /// - pause < `minStretchPauseMs * 0.6` → `.insufficientStretchPause`
    private func detectTempoIssues() -> [IssueCode] {
        guard let targets = tempoTargets, tempoRepSamples > 0 else { return [] }
        var issues: [IssueCode] = []
        let avgEcc = sumEccentricMs / Double(tempoRepSamples)
        let avgCon = sumConcentricMs / Double(tempoRepSamples)
        let avgPause = sumPauseMs / Double(tempoRepSamples)
        if let minEcc = targets.minEccentricMs, avgEcc < Double(minEcc) * 0.5 {
            issues.append(.eccentricTooFast)
        }
        if let maxCon = targets.maxConcentricMs, avgCon > Double(maxCon) * 1.5 {
            issues.append(.concentricTooSlow)
        }
        if let minPause = targets.minStretchPauseMs, avgPause < Double(minPause) * 0.6 {
            issues.append(.insufficientStretchPause)
        }
        return issues
    }


    /// Generate summary for close-grip bench press form analysis
    private func generateCloseGripBenchPressSummary(gripScore: Float, elbowScore: Float, romScore: Float, overallScore: Float) -> String {
        var summaryParts: [String] = []
        
        // Add positive feedback first
        if gripScore >= 0.8 {
            summaryParts.append("good grip width")
        }
        if elbowScore >= 0.8 {
            summaryParts.append("elbows tucked well")
        }
        if romScore >= 0.8 {
            summaryParts.append("full range of motion")
        }
        
        // Add areas for improvement
        if gripScore < 0.6 {
            summaryParts.append("grip too wide")
        }
        if elbowScore < 0.6 {
            summaryParts.append("elbows flaring out")
        }
        if romScore < 0.6 {
            summaryParts.append("incomplete lockout or depth")
        }

        if summaryParts.isEmpty {
            return "Solid close-grip bench press form"
        }

        return summaryParts.joined(separator: ", ")
    }

    // MARK: - 2D Regular Barbell Bench Press Form Analysis
    //
    // Distinct from close-grip bench: regular bench targets ~1.5x shoulder-width grip
    // (vs ~0.8-1.0x for close grip) and tolerates more elbow flare. Reuses the wrist-Y
    // depth signal and shared ROM / tempo helpers; only the grip and elbow ranges differ.

    private func analyzeBenchPressForm(_ points: [String: CGPoint]) -> FormAnalysis {
        let gripWidthScore = calculateBenchGripWidthScore(points)
        let elbowScore = calculateBenchElbowFlareScore(points)
        let romScore = calculateBenchPressROMScore(points)
        let eccentricScore = calculateBenchPressEccentricScore()
        let concentricScore = calculateBenchPressConcentricScore()

        let overallScore = (gripWidthScore * 0.20) +
                           (elbowScore * 0.20) +
                           (romScore * 0.30) +
                           (eccentricScore * 0.15) +
                           (concentricScore * 0.15)

        var issues: [IssueCode] = []
        // Only fire `gripTooWide` when the grip is genuinely too wide. A low score from a
        // narrow grip is just close-grip territory — different style, not unsafe.
        if gripWidthScore < CoachingContract.Threshold.gripTooWide,
           let ratio = benchGripWidthRatio2D(points), ratio > 1.85 {
            issues.append(.gripTooWide)
        }
        if elbowScore < CoachingContract.Threshold.elbowsFlaring { issues.append(.elbowsFlaring) }
        if romScore < CoachingContract.Threshold.incompleteRom { issues.append(.incompleteRom) }
        issues.append(contentsOf: detectTempoIssues())

        let summary = generateBenchPressSummary(
            gripScore: gripWidthScore,
            elbowScore: elbowScore,
            romScore: romScore,
            overallScore: overallScore
        )
        let depth = calculateBenchPressDepth(points)

        return FormAnalysis(
            depth: depth,
            backAngle: 0.0,
            kneeAlignment: 0.0,
            overallScore: overallScore,
            issues: issues,
            summary: summary,
            repCount: repCount,
            avgEccentricMs: tempoRepSamples > 0 ? Float(sumEccentricMs / Double(tempoRepSamples)) : nil,
            avgPauseMs: tempoRepSamples > 0 ? Float(sumPauseMs / Double(tempoRepSamples)) : nil,
            avgConcentricMs: tempoRepSamples > 0 ? Float(sumConcentricMs / Double(tempoRepSamples)) : nil,
            avgBottomDepth: nil,
            deepRepRatio: nil
        )
    }

    /// Wrist-to-shoulder grip ratio with view-angle correction. Returns nil if landmarks unavailable.
    private func benchGripWidthRatio2D(_ points: [String: CGPoint]) -> Float? {
        guard let leftWrist = points["leftWrist"],
              let rightWrist = points["rightWrist"],
              let leftShoulder = points["leftShoulder"],
              let rightShoulder = points["rightShoulder"] else { return nil }
        let gripWidth = abs(leftWrist.x - rightWrist.x)
        let shoulderWidth = abs(leftShoulder.x - rightShoulder.x)
        guard shoulderWidth > 0 else { return nil }
        let raw = Float(gripWidth / shoulderWidth)
        switch benchPressViewType {
        case .rack:   return raw * 1.1
        case .floor:  return raw * 0.95
        case .tripod: return raw
        }
    }

    /// Regular-bench grip width score: ideal band [1.3, 1.8]x shoulder width, graceful falloff
    /// to either side. Below ~1.0 = close-grip territory; above ~2.0 = shoulder-strain risk.
    private func calculateBenchGripWidthScore(_ points: [String: CGPoint]) -> Float {
        guard let ratio = benchGripWidthRatio2D(points) else { return 0.5 }
        if ratio >= 1.3 && ratio <= 1.8 { return 1.0 }
        if ratio < 1.3 {
            return max(0.4, 1.0 - (1.3 - ratio) * 1.2)
        }
        return max(0.3, 1.0 - (ratio - 1.8) * 1.4)
    }

    /// Regular-bench elbow flare score: tolerates more flare than close-grip. 1.0 inside ≤0.85
    /// of shoulder width; drops sharply past ~1.05 (rotator cuff strain territory).
    private func calculateBenchElbowFlareScore(_ points: [String: CGPoint]) -> Float {
        guard let leftElbow = points["leftElbow"],
              let rightElbow = points["rightElbow"],
              let leftShoulder = points["leftShoulder"],
              let rightShoulder = points["rightShoulder"],
              let leftHip = points["leftHip"],
              let rightHip = points["rightHip"] else { return 0.5 }
        let torsoMidlineX = (leftShoulder.x + rightShoulder.x + leftHip.x + rightHip.x) / 4.0
        let shoulderWidth = abs(leftShoulder.x - rightShoulder.x)
        guard shoulderWidth > 0 else { return 0.5 }
        let leftOffset = abs(leftElbow.x - torsoMidlineX)
        let rightOffset = abs(rightElbow.x - torsoMidlineX)
        let avgOffset = (leftOffset + rightOffset) / 2.0
        let raw = Float(avgOffset / shoulderWidth)
        let flare: Float
        switch benchPressViewType {
        case .rack:   flare = raw * 1.15
        case .floor:  flare = raw * 0.9
        case .tripod: flare = raw
        }
        if flare <= 0.85 { return 1.0 }
        if flare <= 1.05 { return max(0.7, 1.0 - (flare - 0.85) * 1.5) }
        return max(0.4, 0.85 - (flare - 1.05) * 0.9)
    }

    /// Generate summary for regular barbell bench press form analysis.
    private func generateBenchPressSummary(gripScore: Float, elbowScore: Float, romScore: Float, overallScore: Float) -> String {
        var parts: [String] = []
        if gripScore >= 0.8  { parts.append("solid grip width") }
        if elbowScore >= 0.8 { parts.append("elbows in a safe position") }
        if romScore >= 0.8   { parts.append("full range of motion") }
        if gripScore < 0.6   { parts.append("grip width is off") }
        if elbowScore < 0.6  { parts.append("elbows flaring out") }
        if romScore < 0.6    { parts.append("incomplete lockout or chest touch") }
        if parts.isEmpty { return "Solid bench press form" }
        return parts.joined(separator: ", ")
    }

    // MARK: - 3D Form Analysis

    /// Dispatches to exercise-specific 3D form analysis.
    /// Bodyweight: computes frame metrics, updates rep accumulation, then aggregates from rep history or fallback.
    private func formAnalysisFrom3D(skeleton: Skeleton3D) -> FormAnalysis {
        switch trackedExerciseType {
        case .bodyweight:
            let depth = calculateHipDepth3D(skeleton)
            let backAngle = calculateBackAngle3D(skeleton)
            let kneeAlignment = calculateKneeAlignment3D(skeleton)
            updateBodyweightRepAccumulation(depth: depth, backAngle: backAngle, kneeAlignment: kneeAlignment)
            return analyzeBodyweightSquatFromRepHistory(
                repHistory: bodyweightRepHistory,
                fallback: FrameMetrics(depth: depth, backAngle: backAngle, kneeAlignment: kneeAlignment),
                viewpointProfile: activeBodyweightRepProfile
            )
        case .barbell:
            return analyzeSquatForm3D(skeleton)
        case .benchPress:
            return analyzeBenchPressForm3D(skeleton)
        case .closeGripBenchPress:
            return analyzeCloseGripBenchPressForm3D(skeleton)
        case .row:
            return analyzeBarbellRowForm3D(skeleton)
        case .deadlift:
            return analyzeDeadliftForm3D(skeleton)
        case .romanianDeadlift:
            return analyzeRomanianDeadliftForm3D(skeleton)
        }
    }

    // MARK: - Bodyweight Rep Accumulation (phase-relevant)

    private func updateBodyweightRepAccumulation(depth: Float, backAngle: Float, kneeAlignment: Float) {
        let startDepth = activeBodyweightRepProfile.repAccumulationStartDepth
        let kneeDepthLine = max(
            bodyweightKneeWindowDepthThreshold,
            activeBodyweightRepProfile.repCountDepthThreshold * 0.92
        )
        switch bodyweightRepPhase {
        case .idle:
            if depth >= startDepth {
                bodyweightRepPhase = .accumulating
                bodyweightRepFrameCount = 0
                bodyweightKneeWindowSampleCount = 0
                bodyweightCurrentRepPeakDepth = depth
                currentRepBackAngleMax = nil
                currentRepKneeAlignmentWorst = nil
            }
        case .accumulating:
            bodyweightCurrentRepPeakDepth = max(bodyweightCurrentRepPeakDepth, depth)
            bodyweightRepFrameCount += 1
            if let cur = currentRepBackAngleMax {
                currentRepBackAngleMax = max(cur, backAngle)
            } else {
                currentRepBackAngleMax = backAngle
            }
            if depth > kneeDepthLine {
                bodyweightKneeWindowSampleCount += 1
                if let cur = currentRepKneeAlignmentWorst {
                    currentRepKneeAlignmentWorst = min(cur, kneeAlignment)
                } else {
                    currentRepKneeAlignmentWorst = kneeAlignment
                }
            }
        }
    }

    /// Clears in-progress bodyweight rep accumulation (squat rep cycle abandoned before count).
    private func abortInProgressBodyweightRepAccumulation() {
        bodyweightRepPhase = .idle
        bodyweightRepFrameCount = 0
        bodyweightKneeWindowSampleCount = 0
        bodyweightCurrentRepPeakDepth = 0
        currentRepBackAngleMax = nil
        currentRepKneeAlignmentWorst = nil
    }

    // MARK: - Bodyweight Set-Level Aggregation

    /// Builds FormAnalysis from rep history using recurring-pattern rules; falls back to frame metrics when no valid reps.
    private func analyzeBodyweightSquatFromRepHistory(
        repHistory: [BodyweightRepMetrics],
        fallback: FrameMetrics,
        viewpointProfile: SquatRepDetectionProfile
    ) -> FormAnalysis {
        let validReps = repHistory.filter { $0.valid }
        guard !validReps.isEmpty else {
            return buildFormAnalysisFromFrameMetrics(fallback, viewpointProfile: viewpointProfile)
        }

        let depthAtBottomMin = validReps.map(\.depthAtBottom).min() ?? fallback.depth
        let backAngleMaxOverall = validReps.map(\.backAngleMax).max() ?? fallback.backAngle
        let kneeWorstOverall = validReps.map(\.kneeAlignmentWorstNearBottom).min() ?? fallback.kneeAlignment

        let leanCount = validReps.filter(\.excessiveForwardLean).count
        let valgusCount = validReps.filter(\.kneeValgus).count
        let n = validReps.count
        let valgusPct = n > 0 ? Float(valgusCount) / Float(n) : 0
        let leanPct = n > 0 ? Float(leanCount) / Float(n) : 0

        let backAngle75th: Float = {
            let sorted = validReps.map(\.backAngleMax).sorted()
            let idx = Int(Float(sorted.count) * 0.75)
            return sorted[min(idx, sorted.count - 1)]
        }()

        let p = viewpointProfile
        let depthShallowLine = CoachingContract.Threshold.depthShallow * max(0.45, min(1.15, p.formWeightDepth))
        let forwardLeanLine = CoachingContract.Threshold.forwardLean / max(0.55, min(1.25, p.formWeightForwardLean))
        let valgusRepFloor = max(2, Int(ceil(2.0 / Double(max(0.5, p.formWeightKneeTracking)))))
        let valgusPctLine = min(0.5, 0.25 * Float(p.formIssueEvidenceMultiplier) / max(0.55, p.formWeightKneeTracking))
        let leanRepFloor = max(2, Int(ceil(2.0 * Double(p.formIssueEvidenceMultiplier) / Double(max(0.65, p.formWeightForwardLean)))))
        let leanPctLine = min(0.45, 0.25 * Float(p.formIssueEvidenceMultiplier) / max(0.55, p.formWeightForwardLean))

        var issues: [IssueCode] = []
        if depthAtBottomMin < depthShallowLine {
            issues.append(.insufficientDepth)
        }
        if leanCount >= leanRepFloor || (n > 0 && leanPct >= leanPctLine) || backAngle75th > forwardLeanLine {
            issues.append(.forwardLean)
        }
        if valgusCount >= valgusRepFloor || (n > 0 && valgusPct >= valgusPctLine) {
            issues.append(.kneeValgus)
        } else if validReps.contains(where: { $0.kneeAlignmentWorstNearBottom > CoachingContract.Threshold.kneeVarus }) {
            let varusCount = validReps.filter { $0.kneeAlignmentWorstNearBottom > CoachingContract.Threshold.kneeVarus }.count
            let varusFloor = max(2, Int(ceil(Double(valgusRepFloor) * Double(p.formIssueEvidenceMultiplier) * 0.9)))
            if varusCount >= varusFloor || (n > 0 && Float(varusCount) / Float(n) >= valgusPctLine) {
                issues.append(.kneeVarus)
            }
        }
        let parallelMiss = validReps.filter { !$0.hipKneeDepthQualityMet }.count
        let goodDepthLine = p.repGoodDepthThreshold
        if n >= 2,
           parallelMiss >= 2,
           Float(parallelMiss) / Float(n) >= 0.5,
           depthAtBottomMin >= goodDepthLine * 0.95,
           !issues.contains(.insufficientDepth) {
            issues.append(.insufficientDepth)
        }
        issues = Array(issues.prefix(CoachingContract.maxIssuesInPayload))

        let overallScore = calculateOverallScore3D(
            depth: depthAtBottomMin,
            backAngle: backAngleMaxOverall,
            kneeAlignment: kneeWorstOverall,
            exerciseType: .bodyweight
        )
        let summary = generateFormSummary3D(
            depth: depthAtBottomMin,
            backAngle: backAngleMaxOverall,
            overallScore: overallScore
        )

        return FormAnalysis(
            depth: depthAtBottomMin,
            backAngle: backAngleMaxOverall,
            kneeAlignment: kneeWorstOverall,
            overallScore: overallScore,
            issues: issues,
            summary: summary,
            repCount: repCount,
            avgEccentricMs: tempoRepSamples > 0 ? Float(sumEccentricMs / Double(tempoRepSamples)) : nil,
            avgPauseMs: tempoRepSamples > 0 ? Float(sumPauseMs / Double(tempoRepSamples)) : nil,
            avgConcentricMs: tempoRepSamples > 0 ? Float(sumConcentricMs / Double(tempoRepSamples)) : nil,
            avgBottomDepth: bottomDepthSamples > 0 ? Float(sumBottomDepth / Double(bottomDepthSamples)) : nil,
            deepRepRatio: totalDepthSamples > 0 ? Float(deepFrameCount) / Float(totalDepthSamples) : nil
        )
    }

    private func buildFormAnalysisFromFrameMetrics(
        _ f: FrameMetrics,
        viewpointProfile: SquatRepDetectionProfile? = nil
    ) -> FormAnalysis {
        let overallScore = calculateOverallScore3D(
            depth: f.depth,
            backAngle: f.backAngle,
            kneeAlignment: f.kneeAlignment,
            exerciseType: trackedExerciseType
        )
        let issues: [IssueCode]
        if trackedExerciseType == .bodyweight, let vp = viewpointProfile {
            issues = detectBodyweightIssues3DWithViewpoint(
                depth: f.depth,
                backAngle: f.backAngle,
                kneeAlignment: f.kneeAlignment,
                profile: vp
            )
        } else {
            issues = detectIssues3D(depth: f.depth, backAngle: f.backAngle, kneeAlignment: f.kneeAlignment)
        }
        let summary = generateFormSummary3D(
            depth: f.depth,
            backAngle: f.backAngle,
            overallScore: overallScore
        )
        return FormAnalysis(
            depth: f.depth,
            backAngle: f.backAngle,
            kneeAlignment: f.kneeAlignment,
            overallScore: overallScore,
            issues: issues,
            summary: summary,
            repCount: repCount,
            avgEccentricMs: tempoRepSamples > 0 ? Float(sumEccentricMs / Double(tempoRepSamples)) : nil,
            avgPauseMs: tempoRepSamples > 0 ? Float(sumPauseMs / Double(tempoRepSamples)) : nil,
            avgConcentricMs: tempoRepSamples > 0 ? Float(sumConcentricMs / Double(tempoRepSamples)) : nil,
            avgBottomDepth: bottomDepthSamples > 0 ? Float(sumBottomDepth / Double(bottomDepthSamples)) : nil,
            deepRepRatio: totalDepthSamples > 0 ? Float(deepFrameCount) / Float(totalDepthSamples) : nil
        )
    }
    
    // MARK: - 3D Squat Form Analysis
    
    private func analyzeSquatForm3D(_ skeleton: Skeleton3D) -> FormAnalysis {
        let movementDepthScore = calculateHipDepth3D(skeleton)
        let backAngle = calculateBackAngle3D(skeleton)
        let kneeAlignment = calculateKneeAlignment3D(skeleton)
        let overallScore = calculateOverallScore3D(
            depth: movementDepthScore, backAngle: backAngle, kneeAlignment: kneeAlignment,
            exerciseType: .barbell
        )
        let issues = detectIssues3D(
            depth: movementDepthScore, backAngle: backAngle, kneeAlignment: kneeAlignment
        )
        let summary = generateFormSummary3D(
            depth: movementDepthScore, backAngle: backAngle, overallScore: overallScore
        )
        
        return FormAnalysis(
            depth: movementDepthScore,
            backAngle: backAngle,
            kneeAlignment: kneeAlignment,
            overallScore: overallScore,
            issues: issues,
            summary: summary,
            repCount: repCount,
            avgEccentricMs: tempoRepSamples > 0 ? Float(sumEccentricMs / Double(tempoRepSamples)) : nil,
            avgPauseMs: tempoRepSamples > 0 ? Float(sumPauseMs / Double(tempoRepSamples)) : nil,
            avgConcentricMs: tempoRepSamples > 0 ? Float(sumConcentricMs / Double(tempoRepSamples)) : nil,
            avgBottomDepth: bottomDepthSamples > 0 ? Float(sumBottomDepth / Double(bottomDepthSamples)) : nil,
            deepRepRatio: totalDepthSamples > 0 ? Float(deepFrameCount) / Float(totalDepthSamples) : nil
        )
    }
    
    /// Hip-to-foot vertical displacement depth, normalized by leg length. Body-proportion invariant.
    /// Self-calibrates: tracks the maximum hip height seen (standing reference).
    /// Falls back to knee-angle depth until calibration data is available.
    private func calculateHipDepth3D(_ skeleton: Skeleton3D) -> Float {
        guard let leftHip = skeleton.position("leftHip"),
              let rightHip = skeleton.position("rightHip"),
              let leftAnkle = skeleton.position("leftAnkle"),
              let rightAnkle = skeleton.position("rightAnkle") else { return 0.5 }

        let hipCenter = (leftHip + rightHip) / 2.0
        let ankleCenter = (leftAnkle + rightAnkle) / 2.0
        let currentHipHeight = hipCenter.y - ankleCenter.y

        let currentLegLen = length(hipCenter - ankleCenter)

        // Stable-frame gate: require N consecutive frames within tolerance band
        // before locking standingHipHeight. Prevents single-frame noise poisoning.
        if let candidate = standingCalibrationCandidate {
            let tolerance = candidate * standingCalibrationTolerance
            if abs(currentHipHeight - candidate) <= tolerance {
                standingCalibrationFrames += 1
                // Track the max within the stable window as the candidate
                if currentHipHeight > candidate {
                    standingCalibrationCandidate = currentHipHeight
                }
                if standingCalibrationFrames >= standingCalibrationRequired {
                    let stableHeight = standingCalibrationCandidate!
                    if stableHeight > (standingHipHeight ?? 0) {
                        let prev = standingHipHeight
                        standingHipHeight = stableHeight
                        standingLegLength = currentLegLen
                        repLog("CALIBRATION LOCKED  hipHeight=\(stableHeight) prev=\(prev.map { String($0) } ?? "nil") legLen=\(currentLegLen) after \(standingCalibrationRequired) stable frames")
                    }
                    // Reset candidate so we can detect taller standing later
                    standingCalibrationCandidate = nil
                    standingCalibrationFrames = 0
                }
            } else if currentHipHeight > candidate {
                // Taller frame: restart candidate with new height
                standingCalibrationCandidate = currentHipHeight
                standingCalibrationFrames = 1
            } else {
                // Shorter than candidate — user may be mid-squat. Only reset if
                // significantly shorter (walked away, new person, etc.)
                if currentHipHeight < candidate * 0.85 {
                    standingCalibrationCandidate = nil
                    standingCalibrationFrames = 0
                }
                // Otherwise: just ignore this frame, keep candidate alive
            }
        } else {
            // No candidate yet: start tracking
            standingCalibrationCandidate = currentHipHeight
            standingCalibrationFrames = 1
        }

        guard let refHeight = standingHipHeight,
              let legLen = standingLegLength, legLen > 0.01 else {
            return calculateMovementDepthScore3D_legacy(skeleton)
        }

        let displacement = refHeight - currentHipHeight
        let depthRaw = displacement / legLen
        return max(0, min(1, depthRaw))
    }

    /// Legacy knee-angle based depth. Used as fallback before hip-height calibration.
    private func calculateMovementDepthScore3D_legacy(_ skeleton: Skeleton3D) -> Float {
        guard let leftHip = skeleton.position("leftHip"),
              let rightHip = skeleton.position("rightHip"),
              let leftKnee = skeleton.position("leftKnee"),
              let rightKnee = skeleton.position("rightKnee"),
              let leftAnkle = skeleton.position("leftAnkle"),
              let rightAnkle = skeleton.position("rightAnkle") else {
            return 0.5
        }

        let leftKneeAngle = angleDegrees(a: leftHip, b: leftKnee, c: leftAnkle)
        let rightKneeAngle = angleDegrees(a: rightHip, b: rightKnee, c: rightAnkle)
        let avgKneeAngle = (leftKneeAngle + rightKneeAngle) / 2.0

        return max(0, min(1, (170 - avgKneeAngle) / 110))
    }
    
    /// Torso lean angle from vertical, computed from 3D shoulder/hip vectors.
    private func calculateBackAngle3D(_ skeleton: Skeleton3D) -> Float {
        guard let leftShoulder = skeleton.position("leftShoulder"),
              let rightShoulder = skeleton.position("rightShoulder"),
              let leftHip = skeleton.position("leftHip"),
              let rightHip = skeleton.position("rightHip") else {
            return 0.0
        }
        
        let shoulderCenter = (leftShoulder + rightShoulder) / 2.0
        let hipCenter = (leftHip + rightHip) / 2.0
        let torso = shoulderCenter - hipCenter
        let lenTorso = length(torso)
        guard lenTorso > .ulpOfOne else { return 0.0 }
        
        let vertical = SIMD3<Float>(0, 1, 0)
        let cosAngle = dot(torso / lenTorso, vertical)
        return acos(max(-1, min(1, cosAngle))) * 180.0 / .pi
    }
    
    /// Lateral knee tracking relative to ankles in 3D.
    private func calculateKneeAlignment3D(_ skeleton: Skeleton3D) -> Float {
        guard let leftKnee = skeleton.position("leftKnee"),
              let rightKnee = skeleton.position("rightKnee"),
              let leftAnkle = skeleton.position("leftAnkle"),
              let rightAnkle = skeleton.position("rightAnkle") else {
            return 0.0
        }
        
        let leftTracking = leftKnee.x - leftAnkle.x
        let rightTracking = rightKnee.x - rightAnkle.x
        let avg = (leftTracking + rightTracking) / 2.0
        return max(-1, min(1, avg / 0.05))
    }
    
    // MARK: - Sub-Score Helpers (config-driven, body-proportion invariant)

    /// Linear ramp between depthMinThreshold (score 0) and depthTarget (score 1).
    private func computeDepthScore(_ depth: Float, config: SquatScoringConfig) -> Float {
        if depth >= config.depthTarget { return 1.0 }
        if depth <= config.depthMinThreshold { return 0.0 }
        return (depth - config.depthMinThreshold)
             / (config.depthTarget - config.depthMinThreshold)
    }

    /// Banded: perfect up to anglePerfectMax, gradual taper to 0.65 at angleAcceptableMax,
    /// then steeper penalty beyond.
    private func computeAngleScore(_ backAngle: Float, config: SquatScoringConfig) -> Float {
        if backAngle <= config.anglePerfectMax { return 1.0 }
        if backAngle <= config.angleAcceptableMax {
            let t = (backAngle - config.anglePerfectMax)
                  / (config.angleAcceptableMax - config.anglePerfectMax)
            return 1.0 - t * 0.35
        }
        let excess = backAngle - config.angleAcceptableMax
        return max(0, 0.65 - excess / 60.0)
    }

    /// Asymmetric: valgus (kneeAlignment < 0) is penalized heavily; varus only mildly.
    private func computeAlignmentScore(_ kneeAlignment: Float, config: SquatScoringConfig) -> Float {
        if kneeAlignment < config.valgusHeavyPenaltyBelow {
            let severity = abs(kneeAlignment - config.valgusHeavyPenaltyBelow)
            return max(0, 0.5 - severity * 0.5)
        }
        if kneeAlignment < 0 {
            let t = abs(kneeAlignment) / abs(config.valgusHeavyPenaltyBelow)
            return 1.0 - t * 0.5
        }
        if kneeAlignment > config.varusMildPenaltyAbove {
            let excess = kneeAlignment - config.varusMildPenaltyAbove
            return max(0.7, 1.0 - excess * 0.3)
        }
        return 1.0
    }

    /// Weighted overall score with exercise-type config and a minimum score floor
    /// for reps that are clearly adequate on depth and alignment.
    private func calculateOverallScore3D(
        depth: Float, backAngle: Float, kneeAlignment: Float,
        exerciseType: TrackedExerciseType
    ) -> Float {
        let config: SquatScoringConfig = (exerciseType == .barbell) ? .barbell : .bodyweight

        let depthScore = computeDepthScore(depth, config: config)
        let angleScore = computeAngleScore(backAngle, config: config)
        let alignmentScore = computeAlignmentScore(kneeAlignment, config: config)

        var score = depthScore * config.weightDepth
                  + angleScore * config.weightAngle
                  + alignmentScore * config.weightAlignment
        score = min(score, 1.0)

        if depthScore >= config.scoreFloorDepthMin
            && alignmentScore >= config.scoreFloorAlignMin
            && backAngle <= config.scoreFloorAngleMax {
            score = max(score, config.scoreFloor)
        }

        return score
    }
    
    private func detectIssues3D(depth: Float, backAngle: Float, kneeAlignment: Float) -> [IssueCode] {
        var issues: [IssueCode] = []
        if depth < CoachingContract.Threshold.depthShallow { issues.append(.insufficientDepth) }
        if backAngle > CoachingContract.Threshold.forwardLean { issues.append(.forwardLean) }
        if kneeAlignment < CoachingContract.Threshold.kneeValgus {
            issues.append(.kneeValgus)
        } else if kneeAlignment > CoachingContract.Threshold.kneeVarus {
            issues.append(.kneeVarus)
        }
        return Array(issues.prefix(CoachingContract.maxIssuesInPayload))
    }

    /// Single-frame issue hints for bodyweight with viewpoint-aware thresholds (fallback when no rep history).
    private func detectBodyweightIssues3DWithViewpoint(
        depth: Float,
        backAngle: Float,
        kneeAlignment: Float,
        profile: SquatRepDetectionProfile
    ) -> [IssueCode] {
        var issues: [IssueCode] = []
        let depthLine = CoachingContract.Threshold.depthShallow * max(0.45, min(1.15, profile.formWeightDepth))
        let leanLine = CoachingContract.Threshold.forwardLean / max(0.55, min(1.25, profile.formWeightForwardLean))
        let wKnee = min(1.2, max(0.5, profile.formWeightKneeTracking))
        let kneeValgusLine = CoachingContract.Threshold.kneeValgus - (1.0 - wKnee) * 0.12
        let kneeVarusLine = CoachingContract.Threshold.kneeVarus + (1.0 - wKnee) * 0.08
        if depth < depthLine { issues.append(.insufficientDepth) }
        if backAngle > leanLine { issues.append(.forwardLean) }
        if kneeAlignment < kneeValgusLine {
            issues.append(.kneeValgus)
        } else if kneeAlignment > kneeVarusLine {
            issues.append(.kneeVarus)
        }
        return Array(issues.prefix(CoachingContract.maxIssuesInPayload))
    }
    
    private func generateFormSummary3D(depth: Float, backAngle: Float, overallScore: Float) -> String {
        let pct = Int(overallScore * 100)
        if overallScore > 0.85 { return "Excellent form (3D)! Score: \(pct)%" }
        if overallScore > 0.7  { return "Good form (3D). Score: \(pct)%" }
        if overallScore > 0.5  { return "Form needs work (3D). Score: \(pct)%" }
        return "Focus on form basics (3D). Score: \(pct)%"
    }
    
    // MARK: - 3D Close-Grip Bench Press Form Analysis
    
    private func analyzeCloseGripBenchPressForm3D(_ skeleton: Skeleton3D) -> FormAnalysis {
        let gripWidthScore = calculateCloseGripWidthScore3D(skeleton)
        let elbowPositionScore = calculateElbowPositionScore3D(skeleton)
        let romScore = calculateBenchPressROMScore3D(skeleton)
        let eccentricScore = calculateBenchPressEccentricScore()
        let concentricScore = calculateBenchPressConcentricScore()
        
        let overallScore = (gripWidthScore * 0.20) +
                           (elbowPositionScore * 0.20) +
                           (romScore * 0.30) +
                           (eccentricScore * 0.15) +
                           (concentricScore * 0.15)
        
        var issues: [IssueCode] = []
        if gripWidthScore < CoachingContract.Threshold.gripTooWide { issues.append(.gripTooWide) }
        if elbowPositionScore < CoachingContract.Threshold.elbowsFlaring { issues.append(.elbowsFlaring) }
        if romScore < CoachingContract.Threshold.incompleteRom { issues.append(.incompleteRom) }
        issues.append(contentsOf: detectTempoIssues())

        let summary = generateCloseGripBenchPressSummary(
            gripScore: gripWidthScore,
            elbowScore: elbowPositionScore,
            romScore: romScore,
            overallScore: overallScore
        )

        let depth = calculateBenchPressDepth3D(skeleton)
        
        return FormAnalysis(
            depth: depth,
            backAngle: 0.0,
            kneeAlignment: 0.0,
            overallScore: overallScore,
            issues: issues,
            summary: summary,
            repCount: repCount,
            avgEccentricMs: tempoRepSamples > 0 ? Float(sumEccentricMs / Double(tempoRepSamples)) : nil,
            avgPauseMs: tempoRepSamples > 0 ? Float(sumPauseMs / Double(tempoRepSamples)) : nil,
            avgConcentricMs: tempoRepSamples > 0 ? Float(sumConcentricMs / Double(tempoRepSamples)) : nil,
            avgBottomDepth: nil,
            deepRepRatio: nil
        )
    }
    
    /// 3D grip width: uses actual 3D distance between wrists vs shoulders (camera-invariant).
    private func calculateCloseGripWidthScore3D(_ skeleton: Skeleton3D) -> Float {
        guard let lw = skeleton.position("leftWrist"),
              let rw = skeleton.position("rightWrist"),
              let ls = skeleton.position("leftShoulder"),
              let rs = skeleton.position("rightShoulder") else { return 0.5 }
        
        let gripWidth = length(lw - rw)
        let shoulderWidth = length(ls - rs)
        guard shoulderWidth > .ulpOfOne else { return 0.5 }
        
        let ratio = gripWidth / shoulderWidth
        if ratio >= 0.7 && ratio <= 1.2 { return 1.0 }
        if ratio < 0.7 { return max(0.5, ratio / 0.7) }
        return max(0.5, 1.0 - (ratio - 1.2))
    }
    
    /// 3D elbow flare: lateral elbow offset vs shoulder width (camera-invariant).
    private func calculateElbowPositionScore3D(_ skeleton: Skeleton3D) -> Float {
        guard let le = skeleton.position("leftElbow"),
              let re = skeleton.position("rightElbow"),
              let ls = skeleton.position("leftShoulder"),
              let rs = skeleton.position("rightShoulder"),
              let lh = skeleton.position("leftHip"),
              let rh = skeleton.position("rightHip") else { return 0.5 }
        
        let center = (ls + rs + lh + rh) / 4.0
        let shoulderWidth = length(ls - rs)
        guard shoulderWidth > .ulpOfOne else { return 0.5 }
        
        let avgOffset = (abs(le.x - center.x) + abs(re.x - center.x)) / 2.0
        let flare = avgOffset / shoulderWidth
        
        if flare <= 0.6 { return 1.0 }
        if flare <= 0.8 { return max(0.7, 1.0 - (flare - 0.6) * 0.75) }
        return max(0.5, 0.85 - (flare - 0.8) * 0.7)
    }
    
    /// 3D ROM: elbow extension angle (camera-invariant).
    private func calculateBenchPressROMScore3D(_ skeleton: Skeleton3D) -> Float {
        guard let lw = skeleton.position("leftWrist"),
              let rw = skeleton.position("rightWrist"),
              let le = skeleton.position("leftElbow"),
              let re = skeleton.position("rightElbow"),
              let ls = skeleton.position("leftShoulder"),
              let rs = skeleton.position("rightShoulder") else { return 0.5 }
        
        let leftAngle = angleDegrees(a: ls, b: le, c: lw)
        let rightAngle = angleDegrees(a: rs, b: re, c: rw)
        let avg = (leftAngle + rightAngle) / 2.0
        
        if avg > 150 { return 1.0 }
        if avg > 120 { return 0.8 }
        return max(0.6, avg / 150.0)
    }
    
    /// 3D bench press depth: elbow-angle based, camera-invariant.
    /// Lockout (~170°) → 0.0, chest touch (~80°) → 1.0.
    private func calculateBenchPressDepth3D(_ skeleton: Skeleton3D) -> Float {
        guard let lw = skeleton.position("leftWrist"),
              let rw = skeleton.position("rightWrist"),
              let le = skeleton.position("leftElbow"),
              let re = skeleton.position("rightElbow"),
              let ls = skeleton.position("leftShoulder"),
              let rs = skeleton.position("rightShoulder") else { return 0.5 }
        
        let leftAngle = angleDegrees(a: ls, b: le, c: lw)
        let rightAngle = angleDegrees(a: rs, b: re, c: rw)
        let avg = (leftAngle + rightAngle) / 2.0
        return max(0, min(1, (170 - avg) / 90))
    }

    // MARK: - 3D Regular Barbell Bench Press Form Analysis

    private func analyzeBenchPressForm3D(_ skeleton: Skeleton3D) -> FormAnalysis {
        let gripWidthScore = calculateBenchGripWidthScore3D(skeleton)
        let elbowPositionScore = calculateBenchElbowFlareScore3D(skeleton)
        let romScore = calculateBenchPressROMScore3D(skeleton)
        let eccentricScore = calculateBenchPressEccentricScore()
        let concentricScore = calculateBenchPressConcentricScore()

        let overallScore = (gripWidthScore * 0.20) +
                           (elbowPositionScore * 0.20) +
                           (romScore * 0.30) +
                           (eccentricScore * 0.15) +
                           (concentricScore * 0.15)

        var issues: [IssueCode] = []
        if gripWidthScore < CoachingContract.Threshold.gripTooWide,
           let ratio = benchGripWidthRatio3D(skeleton), ratio > 1.85 {
            issues.append(.gripTooWide)
        }
        if elbowPositionScore < CoachingContract.Threshold.elbowsFlaring { issues.append(.elbowsFlaring) }
        if romScore < CoachingContract.Threshold.incompleteRom { issues.append(.incompleteRom) }
        issues.append(contentsOf: detectTempoIssues())

        let summary = generateBenchPressSummary(
            gripScore: gripWidthScore,
            elbowScore: elbowPositionScore,
            romScore: romScore,
            overallScore: overallScore
        )
        let depth = calculateBenchPressDepth3D(skeleton)

        return FormAnalysis(
            depth: depth,
            backAngle: 0.0,
            kneeAlignment: 0.0,
            overallScore: overallScore,
            issues: issues,
            summary: summary,
            repCount: repCount,
            avgEccentricMs: tempoRepSamples > 0 ? Float(sumEccentricMs / Double(tempoRepSamples)) : nil,
            avgPauseMs: tempoRepSamples > 0 ? Float(sumPauseMs / Double(tempoRepSamples)) : nil,
            avgConcentricMs: tempoRepSamples > 0 ? Float(sumConcentricMs / Double(tempoRepSamples)) : nil,
            avgBottomDepth: nil,
            deepRepRatio: nil
        )
    }

    /// 3D wrist-to-shoulder grip ratio (camera-invariant). Returns nil if landmarks unavailable.
    private func benchGripWidthRatio3D(_ skeleton: Skeleton3D) -> Float? {
        guard let lw = skeleton.position("leftWrist"),
              let rw = skeleton.position("rightWrist"),
              let ls = skeleton.position("leftShoulder"),
              let rs = skeleton.position("rightShoulder") else { return nil }
        let gripWidth = length(lw - rw)
        let shoulderWidth = length(ls - rs)
        guard shoulderWidth > .ulpOfOne else { return nil }
        return gripWidth / shoulderWidth
    }

    /// 3D regular-bench grip width: ideal band [1.3, 1.8]x shoulder width.
    private func calculateBenchGripWidthScore3D(_ skeleton: Skeleton3D) -> Float {
        guard let ratio = benchGripWidthRatio3D(skeleton) else { return 0.5 }
        if ratio >= 1.3 && ratio <= 1.8 { return 1.0 }
        if ratio < 1.3 {
            return max(0.4, 1.0 - (1.3 - ratio) * 1.2)
        }
        return max(0.3, 1.0 - (ratio - 1.8) * 1.4)
    }

    /// 3D regular-bench elbow flare: lateral elbow offset / shoulder width, more permissive than close-grip.
    private func calculateBenchElbowFlareScore3D(_ skeleton: Skeleton3D) -> Float {
        guard let le = skeleton.position("leftElbow"),
              let re = skeleton.position("rightElbow"),
              let ls = skeleton.position("leftShoulder"),
              let rs = skeleton.position("rightShoulder"),
              let lh = skeleton.position("leftHip"),
              let rh = skeleton.position("rightHip") else { return 0.5 }
        let center = (ls + rs + lh + rh) / 4.0
        let shoulderWidth = length(ls - rs)
        guard shoulderWidth > .ulpOfOne else { return 0.5 }
        let avgOffset = (abs(le.x - center.x) + abs(re.x - center.x)) / 2.0
        let flare = avgOffset / shoulderWidth
        if flare <= 0.85 { return 1.0 }
        if flare <= 1.05 { return max(0.7, 1.0 - (flare - 0.85) * 1.5) }
        return max(0.4, 0.85 - (flare - 1.05) * 0.9)
    }

    private func calculateDepth(_ points: [String: CGPoint]) -> Float {
        // Simplified depth calculation based on hip position
        guard let leftHip = points["leftHip"], let rightHip = points["rightHip"] else {
            return 0.5
        }
        
        // Calculate average hip position as depth indicator
        let hipY = (leftHip.y + rightHip.y) / 2.0
        return Float(hipY)
    }
    
    // MARK: - Barbell Row Form Analysis (2D overlay)

    /// Analyzes barbell row form from 2D overlay landmarks.
    ///
    /// Form Metrics (weighted scoring):
    /// - **Momentum / hip drive (30%)**: Torso should stay at a stable hinge angle; rising indicates hip drive.
    /// - **Back neutrality (30%)**: Spine should remain flat; head dropping below the shoulder line indicates rounding.
    /// - **Elbow flare (25%)**: Elbows should pull back toward hips, not flare out past 60° from the torso.
    /// - **Knee/foot rotation (15%)**: Knees should track straight ahead, not collapse inward.
    private func analyzeBarbellRowForm(_ points: [String: CGPoint]) -> FormAnalysis {
        let momentumScore = calculateRowMomentumScore(points)
        let backScore = calculateRowBackNeutralityScore(points)
        let elbowScore = calculateRowElbowFlareScore(points)
        let kneeScore = calculateRowKneeRotationScore(points)

        let overallScore = (momentumScore * 0.30) +
                           (backScore * 0.30) +
                           (elbowScore * 0.25) +
                           (kneeScore * 0.15)

        var issues: [IssueCode] = []
        if momentumScore < CoachingContract.Threshold.rowMomentum { issues.append(.rowMomentumDrive) }
        if backScore < CoachingContract.Threshold.rowBackNeutral { issues.append(.rowRoundedBack) }
        if elbowScore < CoachingContract.Threshold.rowElbowFlare { issues.append(.rowElbowFlare) }
        if kneeScore < CoachingContract.Threshold.rowKneeRotation { issues.append(.rowKneeInternalRotation) }
        issues = Array(issues.prefix(CoachingContract.maxIssuesInPayload))

        let backAngle = calculateRowHingeAngle(points)
        let summary = generateRowFormSummary(overallScore: overallScore)

        return FormAnalysis(
            depth: 0.5,
            backAngle: backAngle,
            kneeAlignment: kneeScore - 0.5,
            overallScore: overallScore,
            issues: issues,
            summary: summary,
            repCount: repCount,
            avgEccentricMs: nil, avgPauseMs: nil, avgConcentricMs: nil,
            avgBottomDepth: nil, deepRepRatio: nil
        )
    }

    /// 3D barbell row form analysis using world-coordinate skeleton.
    private func analyzeBarbellRowForm3D(_ skeleton: Skeleton3D) -> FormAnalysis {
        let momentumScore = calculateRowMomentumScore3D(skeleton)
        let backScore = calculateRowBackNeutralityScore3D(skeleton)
        let elbowScore = calculateRowElbowFlareScore3D(skeleton)
        let kneeScore = calculateRowKneeRotationScore3D(skeleton)

        let overallScore = (momentumScore * 0.30) +
                           (backScore * 0.30) +
                           (elbowScore * 0.25) +
                           (kneeScore * 0.15)

        var issues: [IssueCode] = []
        if momentumScore < CoachingContract.Threshold.rowMomentum { issues.append(.rowMomentumDrive) }
        if backScore < CoachingContract.Threshold.rowBackNeutral { issues.append(.rowRoundedBack) }
        if elbowScore < CoachingContract.Threshold.rowElbowFlare { issues.append(.rowElbowFlare) }
        if kneeScore < CoachingContract.Threshold.rowKneeRotation { issues.append(.rowKneeInternalRotation) }
        issues = Array(issues.prefix(CoachingContract.maxIssuesInPayload))

        let backAngle = calculateRowHingeAngle3D(skeleton)
        let summary = generateRowFormSummary(overallScore: overallScore)

        return FormAnalysis(
            depth: 0.5,
            backAngle: backAngle,
            kneeAlignment: kneeScore - 0.5,
            overallScore: overallScore,
            issues: issues,
            summary: summary,
            repCount: repCount,
            avgEccentricMs: nil, avgPauseMs: nil, avgConcentricMs: nil,
            avgBottomDepth: nil, deepRepRatio: nil
        )
    }

    // MARK: Barbell Row — Hinge Angle

    /// Returns the torso angle from horizontal (degrees). Ideal row position is 25-50°.
    /// Uses the midpoint of hips and the midpoint of shoulders to define the torso line.
    private func calculateRowHingeAngle(_ points: [String: CGPoint]) -> Float {
        guard let leftHip = points["leftHip"], let rightHip = points["rightHip"],
              let leftShoulder = points["leftShoulder"], let rightShoulder = points["rightShoulder"] else {
            return 35.0 // Default to middle of ideal range
        }
        let midHip = CGPoint(x: (leftHip.x + rightHip.x) / 2, y: (leftHip.y + rightHip.y) / 2)
        let midShoulder = CGPoint(x: (leftShoulder.x + rightShoulder.x) / 2, y: (leftShoulder.y + rightShoulder.y) / 2)
        let dx = Float(midShoulder.x - midHip.x)
        let dy = Float(midShoulder.y - midHip.y)
        // Angle from horizontal; in screen coords Y increases downward, so we use abs(dy)
        let angleRad = atan2(abs(dy), abs(dx))
        return angleRad * 180.0 / .pi
    }

    private func calculateRowHingeAngle3D(_ skeleton: Skeleton3D) -> Float {
        guard let lh = skeleton.position("leftHip"), let rh = skeleton.position("rightHip"),
              let ls = skeleton.position("leftShoulder"), let rs = skeleton.position("rightShoulder") else {
            return 35.0
        }
        let midHip = (lh + rh) * 0.5
        let midShoulder = (ls + rs) * 0.5
        let torso = midShoulder - midHip
        // Angle from horizontal: asin(|vertical component| / length)
        let len = length(torso)
        guard len > .ulpOfOne else { return 35.0 }
        let angleRad = asin(abs(torso.y) / len)
        return angleRad * 180.0 / .pi
    }

    // MARK: Barbell Row — Momentum / Hip Drive Detection

    /// Scores how stable the torso hinge position is.
    /// If the torso angle is too upright (> 55°), the user is likely using hip drive
    /// or standing up between reps. Returns 1.0 for stable hinge, 0.0 for fully upright.
    private func calculateRowMomentumScore(_ points: [String: CGPoint]) -> Float {
        let angle = calculateRowHingeAngle(points)
        if angle <= CoachingContract.Threshold.rowHingeIdealMax {
            return 1.0 // In the hinge — no momentum
        }
        // Linear ramp-down from ideal-max to too-upright
        let uprightLine = CoachingContract.Threshold.rowHingeTooUpright
        if angle >= uprightLine { return 0.0 }
        return 1.0 - (angle - CoachingContract.Threshold.rowHingeIdealMax) / (uprightLine - CoachingContract.Threshold.rowHingeIdealMax)
    }

    private func calculateRowMomentumScore3D(_ skeleton: Skeleton3D) -> Float {
        let angle = calculateRowHingeAngle3D(skeleton)
        if angle <= CoachingContract.Threshold.rowHingeIdealMax { return 1.0 }
        let uprightLine = CoachingContract.Threshold.rowHingeTooUpright
        if angle >= uprightLine { return 0.0 }
        return 1.0 - (angle - CoachingContract.Threshold.rowHingeIdealMax) / (uprightLine - CoachingContract.Threshold.rowHingeIdealMax)
    }

    // MARK: Barbell Row — Rounded Back Detection

    /// Checks spine neutrality by comparing the head-shoulder-hip angle.
    /// A neutral spine produces ~170-180° at the shoulder. Rounding drops the head forward,
    /// collapsing this angle. Returns 1.0 for flat back, 0.0 for severely rounded.
    private func calculateRowBackNeutralityScore(_ points: [String: CGPoint]) -> Float {
        guard let leftHip = points["leftHip"], let rightHip = points["rightHip"],
              let leftShoulder = points["leftShoulder"], let rightShoulder = points["rightShoulder"] else {
            return 0.7 // Default to slightly-good if we can't see
        }
        let midHip = CGPoint(x: (leftHip.x + rightHip.x) / 2, y: (leftHip.y + rightHip.y) / 2)
        let midShoulder = CGPoint(x: (leftShoulder.x + rightShoulder.x) / 2, y: (leftShoulder.y + rightShoulder.y) / 2)

        // Use nose or ear as head reference
        let headPoint: CGPoint
        if let nose = points["nose"] {
            headPoint = nose
        } else if let leftEar = points["leftEar"], let rightEar = points["rightEar"] {
            headPoint = CGPoint(x: (leftEar.x + rightEar.x) / 2, y: (leftEar.y + rightEar.y) / 2)
        } else {
            return 0.7
        }

        // Compute angle at mid-shoulder formed by hip → shoulder → head
        let toHip = SIMD2<Float>(Float(midHip.x - midShoulder.x), Float(midHip.y - midShoulder.y))
        let toHead = SIMD2<Float>(Float(headPoint.x - midShoulder.x), Float(headPoint.y - midShoulder.y))
        let lenA = simd_length(toHip)
        let lenB = simd_length(toHead)
        guard lenA > 0.001, lenB > 0.001 else { return 0.7 }
        let cosAngle = simd_dot(toHip, toHead) / (lenA * lenB)
        let angleDeg = acos(max(-1, min(1, cosAngle))) * 180.0 / .pi

        // 170-180° = flat spine (score 1.0)
        // 130° = moderately rounded (score ~0.5)
        // <110° = severely rounded (score 0.0)
        if angleDeg >= 165 { return 1.0 }
        if angleDeg <= 110 { return 0.0 }
        return (angleDeg - 110) / (165 - 110)
    }

    private func calculateRowBackNeutralityScore3D(_ skeleton: Skeleton3D) -> Float {
        guard let lh = skeleton.position("leftHip"), let rh = skeleton.position("rightHip"),
              let ls = skeleton.position("leftShoulder"), let rs = skeleton.position("rightShoulder") else {
            return 0.7
        }
        let midHip = (lh + rh) * 0.5
        let midShoulder = (ls + rs) * 0.5

        let headPos: SIMD3<Float>
        if let nose = skeleton.position("nose") {
            headPos = nose
        } else if let cs = skeleton.position("centerShoulder") {
            // Fall back to center shoulder offset upward
            headPos = cs + SIMD3<Float>(0, 0.15, 0)
        } else {
            return 0.7
        }

        let angleDeg = angleDegrees(a: midHip, b: midShoulder, c: headPos)
        if angleDeg >= 165 { return 1.0 }
        if angleDeg <= 110 { return 0.0 }
        return (angleDeg - 110) / (165 - 110)
    }

    // MARK: Barbell Row — Elbow Flare Detection

    /// Measures the angle between the upper arm (shoulder→elbow) and the torso (shoulder→hip).
    /// Elbows should pull back toward the hips (~30-45°), not flare out (>60°).
    /// Returns 1.0 for tucked elbows, 0.0 for fully flared.
    private func calculateRowElbowFlareScore(_ points: [String: CGPoint]) -> Float {
        guard let leftShoulder = points["leftShoulder"], let rightShoulder = points["rightShoulder"],
              let leftElbow = points["leftElbow"], let rightElbow = points["rightElbow"],
              let leftHip = points["leftHip"], let rightHip = points["rightHip"] else {
            return 0.7
        }

        // Compute angle for each arm
        let leftAngle = elbowTorsoAngle2D(shoulder: leftShoulder, elbow: leftElbow, hip: leftHip)
        let rightAngle = elbowTorsoAngle2D(shoulder: rightShoulder, elbow: rightElbow, hip: rightHip)
        let avgAngle = (leftAngle + rightAngle) / 2.0

        let limit = CoachingContract.Threshold.rowElbowFlareAngle
        if avgAngle <= limit * 0.75 { return 1.0 }  // Well tucked
        if avgAngle >= 90 { return 0.0 }              // Severely flared
        if avgAngle <= limit { return max(0.6, 1.0 - (avgAngle - limit * 0.75) / (limit * 0.25)) }
        return max(0.0, 1.0 - (avgAngle - limit) / (90 - limit))
    }

    /// Helper: angle between upper arm (shoulder→elbow) and torso (shoulder→hip) in 2D, in degrees.
    private func elbowTorsoAngle2D(shoulder: CGPoint, elbow: CGPoint, hip: CGPoint) -> Float {
        let toElbow = SIMD2<Float>(Float(elbow.x - shoulder.x), Float(elbow.y - shoulder.y))
        let toHip = SIMD2<Float>(Float(hip.x - shoulder.x), Float(hip.y - shoulder.y))
        let lenA = simd_length(toElbow)
        let lenB = simd_length(toHip)
        guard lenA > 0.001, lenB > 0.001 else { return 45 }
        let cosAngle = simd_dot(toElbow, toHip) / (lenA * lenB)
        return acos(max(-1, min(1, cosAngle))) * 180.0 / .pi
    }

    private func calculateRowElbowFlareScore3D(_ skeleton: Skeleton3D) -> Float {
        guard let ls = skeleton.position("leftShoulder"), let rs = skeleton.position("rightShoulder"),
              let le = skeleton.position("leftElbow"), let re = skeleton.position("rightElbow"),
              let lh = skeleton.position("leftHip"), let rh = skeleton.position("rightHip") else {
            return 0.7
        }

        let leftAngle = angleDegrees(a: le, b: ls, c: lh)
        let rightAngle = angleDegrees(a: re, b: rs, c: rh)
        let avgAngle = (leftAngle + rightAngle) / 2.0

        let limit = CoachingContract.Threshold.rowElbowFlareAngle
        if avgAngle <= limit * 0.75 { return 1.0 }
        if avgAngle >= 90 { return 0.0 }
        if avgAngle <= limit { return max(0.6, 1.0 - (avgAngle - limit * 0.75) / (limit * 0.25)) }
        return max(0.0, 1.0 - (avgAngle - limit) / (90 - limit))
    }

    // MARK: Barbell Row — Knee / Foot Internal Rotation Detection

    /// Detects internal rotation of knees relative to ankles.
    /// Compares the horizontal distance between knees vs ankles.
    /// If knees are substantially inside the ankles, the user is internally rotated.
    /// Returns 1.0 for knees tracking well, 0.0 for severe internal rotation.
    private func calculateRowKneeRotationScore(_ points: [String: CGPoint]) -> Float {
        guard let leftKnee = points["leftKnee"], let rightKnee = points["rightKnee"],
              let leftAnkle = points["leftAnkle"], let rightAnkle = points["rightAnkle"] else {
            return 0.8 // Default good if not visible
        }
        let kneeWidth = abs(Float(leftKnee.x - rightKnee.x))
        let ankleWidth = abs(Float(leftAnkle.x - rightAnkle.x))
        guard ankleWidth > 0.001 else { return 0.8 }

        let ratio = kneeWidth / ankleWidth
        // ratio ~1.0 = aligned. < 0.7 = knees caving inward.
        if ratio >= 0.85 { return 1.0 }
        if ratio <= 0.5 { return 0.0 }
        return (ratio - 0.5) / (0.85 - 0.5)
    }

    private func calculateRowKneeRotationScore3D(_ skeleton: Skeleton3D) -> Float {
        guard let lk = skeleton.position("leftKnee"), let rk = skeleton.position("rightKnee"),
              let la = skeleton.position("leftAnkle"), let ra = skeleton.position("rightAnkle") else {
            return 0.8
        }
        // Use the XZ plane (horizontal) distance
        let kneeSpread = length(SIMD2<Float>(lk.x - rk.x, lk.z - rk.z))
        let ankleSpread = length(SIMD2<Float>(la.x - ra.x, la.z - ra.z))
        guard ankleSpread > 0.001 else { return 0.8 }

        let ratio = kneeSpread / ankleSpread
        if ratio >= 0.85 { return 1.0 }
        if ratio <= 0.5 { return 0.0 }
        return (ratio - 0.5) / (0.85 - 0.5)
    }

    // MARK: Barbell Row — Summary

    private func generateRowFormSummary(overallScore: Float) -> String {
        let pct = Int(overallScore * 100)
        if overallScore > 0.85 { return "Excellent row form! Score: \(pct)%" }
        if overallScore > 0.7  { return "Good row form. Score: \(pct)%" }
        if overallScore > 0.5  { return "Row form needs some work. Score: \(pct)%" }
        return "Focus on row basics. Score: \(pct)%"
    }

    // MARK: Barbell Row — Rep Validation

    /// Row rep detection — bodyweight-style algorithm on the 3D elbow angle.
    ///
    /// Real-world testing showed front/oblique camera angles failed (0/3) because the previous
    /// validator required BOTH wrists at full visibility — front-on, the far-side wrist is
    /// occluded by the torso. This version mirrors the bodyweight squat algorithm:
    ///   1. Pick the better-visible arm side (more spatial spread, like the squat does for legs).
    ///   2. Compute the 3D elbow angle (shoulder→elbow→wrist) — camera-angle invariant.
    ///   3. EMA-smooth to reduce landmark jitter.
    ///   4. Two-state machine .extended ↔ .flexed with hysteresis.
    ///   5. Timing gates reject impossibly fast / slow cycles.
    ///   6. Stationary-feet gate rejects "walking into / out of position" false reps.
    private func validateRowRep(
        skeleton: Skeleton3D?,
        overlay: [String: CGPoint]?,
        confidence: [String: Float],
        now: Date
    ) -> Bool {
        guard let skeleton = skeleton else { return false }

        let ls = skeleton.position("leftShoulder"),  le = skeleton.position("leftElbow"),  lw = skeleton.position("leftWrist")
        let rs = skeleton.position("rightShoulder"), re = skeleton.position("rightElbow"), rw = skeleton.position("rightWrist")
        let leftOk  = ls != nil && le != nil && lw != nil
        let rightOk = rs != nil && re != nil && rw != nil

        let s: SIMD3<Float>, e: SIMD3<Float>, w: SIMD3<Float>
        if leftOk, rightOk {
            // Pick the side with more spatial spread (closer to camera in side / oblique views).
            let lSpread = abs(ls!.x - lw!.x) + abs(ls!.y - lw!.y) + abs(ls!.z - lw!.z)
            let rSpread = abs(rs!.x - rw!.x) + abs(rs!.y - rw!.y) + abs(rs!.z - rw!.z)
            if rSpread >= lSpread { s = rs!; e = re!; w = rw! } else { s = ls!; e = le!; w = lw! }
        } else if rightOk { s = rs!; e = re!; w = rw! }
          else if leftOk  { s = ls!; e = le!; w = lw! }
          else {
            rowBadFrameStreak += 1
            if rowBadFrameStreak >= weightedRepBadFrameLimit { rowSmoothedElbowAngle = nil }
            return false
        }
        rowBadFrameStreak = 0

        let raw = angleDegrees(a: s, b: e, c: w)
        let smoothed: Float = if let prev = rowSmoothedElbowAngle {
            rowEMAAlpha * raw + (1 - rowEMAAlpha) * prev
        } else { raw }
        rowSmoothedElbowAngle = smoothed

        switch rowRepPhase {
        case .extended:
            if smoothed <= rowFlexedThreshold {
                rowRepPhase = .flexed
                rowRepCycleStartTime = now
                beginAnkleStabilityCycle(overlay: overlay)
                rowMinShoulderYInFlexed = .greatestFiniteMagnitude
                rowMaxShoulderYInFlexed = -.greatestFiniteMagnitude
                rowMinSmoothedElbowAngleInFlexed = smoothed
                rowMaxBetterWristConfInFlexed = max(confidence["leftWrist"] ?? 0, confidence["rightWrist"] ?? 0)
                if let ov = overlay,
                   let ls = ov["leftShoulder"], let rs = ov["rightShoulder"] {
                    let shY = Float((ls.y + rs.y) / 2)
                    rowMinShoulderYInFlexed = shY
                    rowMaxShoulderYInFlexed = shY
                }
            }
            return false

        case .flexed:
            // Sample shoulder Y on every frame in the active cycle (parallel to ankle gate).
            if let ov = overlay,
               let ls = ov["leftShoulder"], let rs = ov["rightShoulder"] {
                let shY = Float((ls.y + rs.y) / 2)
                rowMinShoulderYInFlexed = min(rowMinShoulderYInFlexed, shY)
                rowMaxShoulderYInFlexed = max(rowMaxShoulderYInFlexed, shY)
            }
            // Track the deepest elbow angle reached this cycle for the shallow-brief gate.
            rowMinSmoothedElbowAngleInFlexed = min(rowMinSmoothedElbowAngleInFlexed, smoothed)
            // Track the best-tracked wrist confidence at any frame in this cycle.
            let betterWristConfThisFrame = max(confidence["leftWrist"] ?? 0, confidence["rightWrist"] ?? 0)
            rowMaxBetterWristConfInFlexed = max(rowMaxBetterWristConfInFlexed, betterWristConfThisFrame)

            guard smoothed >= rowExtendedThreshold else { return false }
            let dur = now.timeIntervalSince(rowRepCycleStartTime ?? now)
            if let last = lastRepValidationTime, now.timeIntervalSince(last) < rowMinRepInterval {
                rowLastRejectReason = String(format: "minInterval dt=%.2fs", now.timeIntervalSince(last))
                rowRepPhase = .extended; rowRepCycleStartTime = nil
                resetCurrentRepCycleAnkleStability()
                rowMinSmoothedElbowAngleInFlexed = .greatestFiniteMagnitude
                rowMaxBetterWristConfInFlexed = 0
                return false
            }
            if dur < rowMinRepCycleDuration {
                rowLastRejectReason = String(format: "tooShort dur=%.2fs", dur)
                rowRepPhase = .extended; rowRepCycleStartTime = nil
                resetCurrentRepCycleAnkleStability()
                rowMinSmoothedElbowAngleInFlexed = .greatestFiniteMagnitude
                rowMaxBetterWristConfInFlexed = 0
                return false
            }
            if dur > rowMaxRepCycleDuration {
                rowLastRejectReason = String(format: "tooLong dur=%.2fs", dur)
                rowRepPhase = .extended; rowRepCycleStartTime = nil
                resetCurrentRepCycleAnkleStability()
                rowMinSmoothedElbowAngleInFlexed = .greatestFiniteMagnitude
                rowMaxBetterWristConfInFlexed = 0
                return false
            }
            if ankleDriftExceedsTolerance(tolerance: rowAnkleStabilityTolerance) {
                let driftRange = currentRepCycleAnkleYMax - currentRepCycleAnkleYMin
                rowLastRejectReason = String(format: "ankleDrift range=%.4f tol=%.4f", driftRange, rowAnkleStabilityTolerance)
                rowRepPhase = .extended; rowRepCycleStartTime = nil
                resetCurrentRepCycleAnkleStability()
                rowMinSmoothedElbowAngleInFlexed = .greatestFiniteMagnitude
                rowMaxBetterWristConfInFlexed = 0
                return false
            }
            // Shoulder-Y stability gate: a real row keeps the torso planted in roughly the
            // same vertical image position throughout the pull. Misfires (standing upright
            // into position, walking, hand-to-face, partial setup) shift the shoulder Y
            // substantially. This is the row analog of the ankle stability gate.
            if rowMinShoulderYInFlexed != .greatestFiniteMagnitude {
                let shoulderRange = rowMaxShoulderYInFlexed - rowMinShoulderYInFlexed
                if shoulderRange > rowShoulderYStabilityTolerance {
                    rowLastRejectReason = String(format: "shoulderShift range=%.4f tol=%.4f", shoulderRange, rowShoulderYStabilityTolerance)
                    rowRepPhase = .extended; rowRepCycleStartTime = nil
                    resetCurrentRepCycleAnkleStability()
                    rowMinSmoothedElbowAngleInFlexed = .greatestFiniteMagnitude
                    rowMaxBetterWristConfInFlexed = 0
                    return false
                }
            }
            // Shallow-brief-motion gate: bar pickup and putdown briefly graze the flexed
            // threshold (~137-140°) over a short window (0.5-0.6s) because the user is
            // transitioning into or out of stance, not actually pulling. A real rep is
            // either deeper or longer. Reject only when both signals fire.
            if dur < rowShallowBriefMaxDuration
               && rowMinSmoothedElbowAngleInFlexed > rowShallowBriefMinAngle {
                rowLastRejectReason = String(
                    format: "shallowBrief dur=%.2fs minA=%.1f",
                    dur, rowMinSmoothedElbowAngleInFlexed
                )
                rowRepPhase = .extended; rowRepCycleStartTime = nil
                resetCurrentRepCycleAnkleStability()
                rowMinSmoothedElbowAngleInFlexed = .greatestFiniteMagnitude
                rowMaxBetterWristConfInFlexed = 0
                return false
            }
            // Subject-tracking gate: if neither wrist was tracked confidently at any
            // frame in this cycle, the pose model likely latched onto a non-lifter in
            // frame (e.g., someone walking through the background between sets). The
            // elbow angle from a mistracked subject can oscillate near the row
            // thresholds and produce a phantom rep.
            if rowMaxBetterWristConfInFlexed < rowMinBetterWristConfPeak {
                rowLastRejectReason = String(
                    format: "lowWristConf peak=%.2f thr=%.2f",
                    rowMaxBetterWristConfInFlexed, rowMinBetterWristConfPeak
                )
                rowRepPhase = .extended; rowRepCycleStartTime = nil
                resetCurrentRepCycleAnkleStability()
                rowMinSmoothedElbowAngleInFlexed = .greatestFiniteMagnitude
                rowMaxBetterWristConfInFlexed = 0
                return false
            }
            // Rep counted.
            lastRepValidationTime = now
            rowRepPhase = .extended
            rowRepCycleStartTime = nil
            resetCurrentRepCycleAnkleStability()
            rowMinSmoothedElbowAngleInFlexed = .greatestFiniteMagnitude
            rowMaxBetterWristConfInFlexed = 0
            return true
        }
    }

    // MARK: - Deadlift Form Analysis (2D overlay)

    /// Analyzes conventional deadlift form from 2D overlay landmarks.
    ///
    /// Form Metrics (weighted scoring):
    /// - **Back neutrality (35%)**: Spine should stay flat from setup to lockout.
    /// - **Hip-shoulder coordination (25%)**: Hips and shoulders should rise at the same rate.
    /// - **Bar path / drift (20%)**: Bar should stay close to the shins and thighs.
    /// - **Lockout position (20%)**: Stand tall at the top without hyperextending.
    private func analyzeDeadliftForm(_ points: [String: CGPoint]) -> FormAnalysis {
        let backScore = calculateDeadliftBackScore(points)
        let hipShootScore = calculateDeadliftHipShootScore(points)
        let barDriftScore = calculateDeadliftBarDriftScore(points)
        let lockoutScore = calculateDeadliftLockoutScore(points)

        let overallScore = (backScore * 0.35) +
                           (hipShootScore * 0.25) +
                           (barDriftScore * 0.20) +
                           (lockoutScore * 0.20)

        var issues: [IssueCode] = []
        if backScore < CoachingContract.Threshold.dlRoundedBack { issues.append(.deadliftRoundedBack) }
        if hipShootScore < CoachingContract.Threshold.dlHipShoot { issues.append(.deadliftHipShootUp) }
        if barDriftScore < CoachingContract.Threshold.dlBarDrift { issues.append(.deadliftBarDrift) }
        if lockoutScore < CoachingContract.Threshold.dlHyperextension { issues.append(.deadliftHyperextension) }
        issues = Array(issues.prefix(CoachingContract.maxIssuesInPayload))

        let backAngle = calculateDeadliftTorsoAngle(points)
        let summary = generateDeadliftFormSummary(overallScore: overallScore)

        return FormAnalysis(
            depth: 0.5,
            backAngle: backAngle,
            kneeAlignment: 0.0,
            overallScore: overallScore,
            issues: issues,
            summary: summary,
            repCount: repCount,
            avgEccentricMs: nil, avgPauseMs: nil, avgConcentricMs: nil,
            avgBottomDepth: nil, deepRepRatio: nil
        )
    }

    /// 3D deadlift form analysis using world-coordinate skeleton.
    private func analyzeDeadliftForm3D(_ skeleton: Skeleton3D) -> FormAnalysis {
        let backScore = calculateDeadliftBackScore3D(skeleton)
        let hipShootScore = calculateDeadliftHipShootScore3D(skeleton)
        let barDriftScore = calculateDeadliftBarDriftScore3D(skeleton)
        let lockoutScore = calculateDeadliftLockoutScore3D(skeleton)

        let overallScore = (backScore * 0.35) +
                           (hipShootScore * 0.25) +
                           (barDriftScore * 0.20) +
                           (lockoutScore * 0.20)

        var issues: [IssueCode] = []
        if backScore < CoachingContract.Threshold.dlRoundedBack { issues.append(.deadliftRoundedBack) }
        if hipShootScore < CoachingContract.Threshold.dlHipShoot { issues.append(.deadliftHipShootUp) }
        if barDriftScore < CoachingContract.Threshold.dlBarDrift { issues.append(.deadliftBarDrift) }
        if lockoutScore < CoachingContract.Threshold.dlHyperextension { issues.append(.deadliftHyperextension) }
        issues = Array(issues.prefix(CoachingContract.maxIssuesInPayload))

        let backAngle = calculateDeadliftTorsoAngle3D(skeleton)
        let summary = generateDeadliftFormSummary(overallScore: overallScore)

        return FormAnalysis(
            depth: 0.5,
            backAngle: backAngle,
            kneeAlignment: 0.0,
            overallScore: overallScore,
            issues: issues,
            summary: summary,
            repCount: repCount,
            avgEccentricMs: nil, avgPauseMs: nil, avgConcentricMs: nil,
            avgBottomDepth: nil, deepRepRatio: nil
        )
    }

    // MARK: Deadlift — Torso Angle

    /// Returns the torso angle from vertical (degrees). 0° = standing upright, 90° = horizontal.
    /// Used as the backAngle field in FormAnalysis.
    private func calculateDeadliftTorsoAngle(_ points: [String: CGPoint]) -> Float {
        guard let leftHip = points["leftHip"], let rightHip = points["rightHip"],
              let leftShoulder = points["leftShoulder"], let rightShoulder = points["rightShoulder"] else {
            return 0.0
        }
        let midHip = CGPoint(x: (leftHip.x + rightHip.x) / 2, y: (leftHip.y + rightHip.y) / 2)
        let midShoulder = CGPoint(x: (leftShoulder.x + rightShoulder.x) / 2, y: (leftShoulder.y + rightShoulder.y) / 2)
        let dx = Float(midShoulder.x - midHip.x)
        let dy = Float(midShoulder.y - midHip.y)
        // Angle from vertical (Y axis) — in screen coords Y increases downward
        let angleRad = atan2(abs(dx), abs(dy))
        return angleRad * 180.0 / .pi
    }

    private func calculateDeadliftTorsoAngle3D(_ skeleton: Skeleton3D) -> Float {
        guard let lh = skeleton.position("leftHip"), let rh = skeleton.position("rightHip"),
              let ls = skeleton.position("leftShoulder"), let rs = skeleton.position("rightShoulder") else {
            return 0.0
        }
        let midHip = (lh + rh) * 0.5
        let midShoulder = (ls + rs) * 0.5
        let torso = midShoulder - midHip
        let len = length(torso)
        guard len > .ulpOfOne else { return 0.0 }
        // Angle from vertical: acos(|Y component| / length)
        let angleRad = acos(min(1.0, abs(torso.y) / len))
        return angleRad * 180.0 / .pi
    }

    // MARK: Deadlift — Rounded Back Detection

    /// Checks spine neutrality using the head-shoulder-hip angle, similar to the row detection
    /// but with tighter thresholds since deadlift loading is axial and rounding is higher risk.
    /// A neutral spine under load produces ~160-180° at the shoulder vertex.
    /// Returns 1.0 for flat back, 0.0 for severely rounded.
    private func calculateDeadliftBackScore(_ points: [String: CGPoint]) -> Float {
        guard let leftHip = points["leftHip"], let rightHip = points["rightHip"],
              let leftShoulder = points["leftShoulder"], let rightShoulder = points["rightShoulder"] else {
            return 0.7
        }
        let midHip = CGPoint(x: (leftHip.x + rightHip.x) / 2, y: (leftHip.y + rightHip.y) / 2)
        let midShoulder = CGPoint(x: (leftShoulder.x + rightShoulder.x) / 2, y: (leftShoulder.y + rightShoulder.y) / 2)

        let headPoint: CGPoint
        if let nose = points["nose"] {
            headPoint = nose
        } else if let leftEar = points["leftEar"], let rightEar = points["rightEar"] {
            headPoint = CGPoint(x: (leftEar.x + rightEar.x) / 2, y: (leftEar.y + rightEar.y) / 2)
        } else {
            return 0.7
        }

        let toHip = SIMD2<Float>(Float(midHip.x - midShoulder.x), Float(midHip.y - midShoulder.y))
        let toHead = SIMD2<Float>(Float(headPoint.x - midShoulder.x), Float(headPoint.y - midShoulder.y))
        let lenA = simd_length(toHip)
        let lenB = simd_length(toHead)
        guard lenA > 0.001, lenB > 0.001 else { return 0.7 }
        let cosAngle = simd_dot(toHip, toHead) / (lenA * lenB)
        let angleDeg = acos(max(-1, min(1, cosAngle))) * 180.0 / .pi

        let neutralMin = CoachingContract.Threshold.dlSpineNeutralMin
        let severeMin = CoachingContract.Threshold.dlSpineRoundedSevere
        if angleDeg >= neutralMin { return 1.0 }
        if angleDeg <= severeMin { return 0.0 }
        return (angleDeg - severeMin) / (neutralMin - severeMin)
    }

    private func calculateDeadliftBackScore3D(_ skeleton: Skeleton3D) -> Float {
        guard let lh = skeleton.position("leftHip"), let rh = skeleton.position("rightHip"),
              let ls = skeleton.position("leftShoulder"), let rs = skeleton.position("rightShoulder") else {
            return 0.7
        }
        let midHip = (lh + rh) * 0.5
        let midShoulder = (ls + rs) * 0.5

        let headPos: SIMD3<Float>
        if let nose = skeleton.position("nose") {
            headPos = nose
        } else if let cs = skeleton.position("centerShoulder") {
            headPos = cs + SIMD3<Float>(0, 0.15, 0)
        } else {
            return 0.7
        }

        let angleDeg = angleDegrees(a: midHip, b: midShoulder, c: headPos)
        let neutralMin = CoachingContract.Threshold.dlSpineNeutralMin
        let severeMin = CoachingContract.Threshold.dlSpineRoundedSevere
        if angleDeg >= neutralMin { return 1.0 }
        if angleDeg <= severeMin { return 0.0 }
        return (angleDeg - severeMin) / (neutralMin - severeMin)
    }

    // MARK: Deadlift — Hip Shoot-Up Detection

    /// Detects when hips rise faster than shoulders (the "stripper deadlift").
    /// Compares the relative vertical positions of hips and shoulders.
    /// When hips are high relative to shoulders (torso nearly horizontal while hips are up),
    /// the hip-to-shoulder Y ratio is skewed.
    /// Returns 1.0 when hips and shoulders are coordinated, 0.0 when hips are shooting up.
    private func calculateDeadliftHipShootScore(_ points: [String: CGPoint]) -> Float {
        guard let leftHip = points["leftHip"], let rightHip = points["rightHip"],
              let leftShoulder = points["leftShoulder"], let rightShoulder = points["rightShoulder"],
              let leftKnee = points["leftKnee"], let rightKnee = points["rightKnee"] else {
            return 0.7
        }
        let midHipY = Float((leftHip.y + rightHip.y) / 2)
        let midShoulderY = Float((leftShoulder.y + rightShoulder.y) / 2)
        let midKneeY = Float((leftKnee.y + rightKnee.y) / 2)

        // In screen coords Y increases downward. During the pull:
        // - Shoulders should be above hips (shoulder Y < hip Y)
        // - The hip-shoulder vertical gap should be proportional
        // - If hips rise close to shoulder level while knees are still bent, hips are shooting up

        let hipShoulderGap = midHipY - midShoulderY  // positive = hips below shoulders (normal)
        let hipKneeGap = midKneeY - midHipY          // positive = knees below hips (normal)

        // If hips are at or above shoulder level, that's a problem
        guard hipShoulderGap > 0 else { return 0.2 }

        // Ratio: how much of the total pull height is hip-to-shoulder vs hip-to-knee
        // When hips shoot up, hipShoulderGap shrinks relative to hipKneeGap
        let totalSpan = hipShoulderGap + max(0, hipKneeGap)
        guard totalSpan > 0.001 else { return 0.7 }

        let shoulderRatio = hipShoulderGap / totalSpan
        let threshold = CoachingContract.Threshold.dlHipShoulderRatioMin

        if shoulderRatio >= threshold { return 1.0 }
        if shoulderRatio <= threshold * 0.3 { return 0.0 }
        return (shoulderRatio - threshold * 0.3) / (threshold - threshold * 0.3)
    }

    private func calculateDeadliftHipShootScore3D(_ skeleton: Skeleton3D) -> Float {
        guard let lh = skeleton.position("leftHip"), let rh = skeleton.position("rightHip"),
              let ls = skeleton.position("leftShoulder"), let rs = skeleton.position("rightShoulder"),
              let lk = skeleton.position("leftKnee"), let rk = skeleton.position("rightKnee") else {
            return 0.7
        }
        let midHipY = (lh.y + rh.y) * 0.5
        let midShoulderY = (ls.y + rs.y) * 0.5
        let midKneeY = (lk.y + rk.y) * 0.5

        // In 3D space, Y typically increases upward (opposite of screen coords)
        let hipShoulderGap = midShoulderY - midHipY  // positive = shoulders above hips (normal)
        let hipKneeGap = midHipY - midKneeY          // positive = hips above knees (normal)

        guard hipShoulderGap > 0 else { return 0.2 }

        let totalSpan = hipShoulderGap + max(0, hipKneeGap)
        guard totalSpan > 0.001 else { return 0.7 }

        let shoulderRatio = hipShoulderGap / totalSpan
        let threshold = CoachingContract.Threshold.dlHipShoulderRatioMin
        if shoulderRatio >= threshold { return 1.0 }
        if shoulderRatio <= threshold * 0.3 { return 0.0 }
        return (shoulderRatio - threshold * 0.3) / (threshold - threshold * 0.3)
    }

    // MARK: Deadlift — Bar Drift Detection

    /// Detects when the bar drifts away from the body (forward of the midfoot line).
    /// Approximated by measuring horizontal offset of wrists from the hip-to-ankle midline.
    /// Returns 1.0 for bar tight to the body, 0.0 for severe drift.
    private func calculateDeadliftBarDriftScore(_ points: [String: CGPoint]) -> Float {
        guard let leftWrist = points["leftWrist"], let rightWrist = points["rightWrist"],
              let leftHip = points["leftHip"], let rightHip = points["rightHip"],
              let leftShoulder = points["leftShoulder"], let rightShoulder = points["rightShoulder"] else {
            return 0.8
        }
        let midWristX = Float((leftWrist.x + rightWrist.x) / 2)
        let midHipX = Float((leftHip.x + rightHip.x) / 2)
        let shoulderWidth = abs(Float(leftShoulder.x - rightShoulder.x))
        guard shoulderWidth > 0.001 else { return 0.8 }

        // Horizontal offset of wrists from hip center, normalized by shoulder width
        let drift = abs(midWristX - midHipX) / shoulderWidth
        let driftLimit = CoachingContract.Threshold.dlBarDriftRatio

        if drift <= driftLimit * 0.5 { return 1.0 }   // Bar is very close to body
        if drift >= driftLimit * 2.0 { return 0.0 }    // Severe drift
        if drift <= driftLimit { return max(0.6, 1.0 - (drift - driftLimit * 0.5) / (driftLimit * 0.5)) }
        return max(0.0, 1.0 - (drift - driftLimit) / driftLimit)
    }

    private func calculateDeadliftBarDriftScore3D(_ skeleton: Skeleton3D) -> Float {
        guard let lw = skeleton.position("leftWrist"), let rw = skeleton.position("rightWrist"),
              let lh = skeleton.position("leftHip"), let rh = skeleton.position("rightHip"),
              let ls = skeleton.position("leftShoulder"), let rs = skeleton.position("rightShoulder") else {
            return 0.8
        }
        let midWrist = (lw + rw) * 0.5
        let midHip = (lh + rh) * 0.5
        let shoulderWidth = length(ls - rs)
        guard shoulderWidth > 0.001 else { return 0.8 }

        // Use XZ horizontal plane for drift measurement (ignore Y)
        let driftVec = SIMD2<Float>(midWrist.x - midHip.x, midWrist.z - midHip.z)
        let drift = simd_length(driftVec) / shoulderWidth
        let driftLimit = CoachingContract.Threshold.dlBarDriftRatio

        if drift <= driftLimit * 0.5 { return 1.0 }
        if drift >= driftLimit * 2.0 { return 0.0 }
        if drift <= driftLimit { return max(0.6, 1.0 - (drift - driftLimit * 0.5) / (driftLimit * 0.5)) }
        return max(0.0, 1.0 - (drift - driftLimit) / driftLimit)
    }

    // MARK: Deadlift — Hyperextension at Lockout Detection

    /// Detects leaning back past vertical at the top of the deadlift.
    /// The torso angle from vertical should be near 0° at lockout.
    /// If the shoulders are behind the hips (negative angle = past vertical), it's hyperextension.
    /// Returns 1.0 for a clean lockout, 0.0 for excessive lean-back.
    private func calculateDeadliftLockoutScore(_ points: [String: CGPoint]) -> Float {
        guard let leftHip = points["leftHip"], let rightHip = points["rightHip"],
              let leftShoulder = points["leftShoulder"], let rightShoulder = points["rightShoulder"] else {
            return 0.8
        }
        let midHipX = Float((leftHip.x + rightHip.x) / 2)
        let midHipY = Float((leftHip.y + rightHip.y) / 2)
        let midShoulderX = Float((leftShoulder.x + rightShoulder.x) / 2)
        let midShoulderY = Float((leftShoulder.y + rightShoulder.y) / 2)

        // Torso angle from vertical
        let dx = midShoulderX - midHipX
        let dy = midShoulderY - midHipY  // screen coords: Y increases down
        let torsoAngle = atan2(abs(dx), abs(dy)) * 180.0 / .pi

        // Only flag hyperextension when the user is near-vertical (lockout position)
        // If they're still in the pull (angle > 25° from vertical), skip this check
        guard torsoAngle < 20.0 else { return 1.0 }

        // Check if shoulders are behind hips (leaning back)
        // In a side view, if the shoulder X is behind (depending on facing direction)
        // we detect this via the torso being past vertical
        let hyperLimit = CoachingContract.Threshold.dlHyperextensionAngle
        if torsoAngle <= hyperLimit * 0.5 { return 1.0 }  // Clean upright lockout
        if torsoAngle <= hyperLimit { return 0.8 }         // Slight lean, acceptable
        // Past vertical — the shoulder-hip line goes beyond straight up
        return max(0.2, 1.0 - (torsoAngle - hyperLimit) / 15.0)
    }

    private func calculateDeadliftLockoutScore3D(_ skeleton: Skeleton3D) -> Float {
        guard let lh = skeleton.position("leftHip"), let rh = skeleton.position("rightHip"),
              let ls = skeleton.position("leftShoulder"), let rs = skeleton.position("rightShoulder") else {
            return 0.8
        }
        let midHip = (lh + rh) * 0.5
        let midShoulder = (ls + rs) * 0.5
        let torso = midShoulder - midHip
        let len = length(torso)
        guard len > .ulpOfOne else { return 0.8 }

        // Angle from vertical (Y-axis)
        let torsoAngle = acos(min(1.0, abs(torso.y) / len)) * 180.0 / .pi

        // Only check lockout when near-vertical
        guard torsoAngle < 20.0 else { return 1.0 }

        // Check if shoulder is behind the hip in the sagittal plane (Z axis)
        // A positive Z offset means leaning back (depends on facing direction)
        let sagittalOffset = abs(torso.z) / len
        let sagittalAngle = asin(min(1.0, sagittalOffset)) * 180.0 / .pi

        let hyperLimit = CoachingContract.Threshold.dlHyperextensionAngle
        if sagittalAngle <= hyperLimit * 0.5 { return 1.0 }
        if sagittalAngle <= hyperLimit { return 0.8 }
        return max(0.2, 1.0 - (sagittalAngle - hyperLimit) / 15.0)
    }

    // MARK: Deadlift — Summary

    private func generateDeadliftFormSummary(overallScore: Float) -> String {
        let pct = Int(overallScore * 100)
        if overallScore > 0.85 { return "Excellent deadlift form! Score: \(pct)%" }
        if overallScore > 0.7  { return "Good deadlift form. Score: \(pct)%" }
        if overallScore > 0.5  { return "Deadlift form needs some work. Score: \(pct)%" }
        return "Focus on deadlift basics. Score: \(pct)%"
    }

    // MARK: Deadlift — Rep Validation

    /// Deadlift rep detection — bodyweight-style algorithm on the 3D hip angle.
    ///
    /// At setup the user is hinged with bar on the floor (hip angle ≈ 80–100°). At lockout they
    /// are standing tall (≈ 170°). A rep is the round trip hinged → lockedOut → hinged.
    ///
    /// The previous validator used hip vertical position relative to standing calibration —
    /// brittle when the standing calibration drifts and prone to false reps when the user
    /// walks toward / away from the camera or sets the bar down between reps.
    private func validateDeadliftRep(skeleton: Skeleton3D?, overlay: [String: CGPoint]?, now: Date) -> Bool {
        guard let skeleton = skeleton else { return false }

        // Pick the better-visible side and compute hip angle (shoulder→hip→knee).
        let ls = skeleton.position("leftShoulder"),  lh = skeleton.position("leftHip"),  lk = skeleton.position("leftKnee")
        let rs = skeleton.position("rightShoulder"), rh = skeleton.position("rightHip"), rk = skeleton.position("rightKnee")
        let leftOk  = ls != nil && lh != nil && lk != nil
        let rightOk = rs != nil && rh != nil && rk != nil

        let sh: SIMD3<Float>, hp: SIMD3<Float>, kn: SIMD3<Float>
        if leftOk, rightOk {
            let lSpread = abs(ls!.x - lk!.x) + abs(ls!.y - lk!.y) + abs(ls!.z - lk!.z)
            let rSpread = abs(rs!.x - rk!.x) + abs(rs!.y - rk!.y) + abs(rs!.z - rk!.z)
            if rSpread >= lSpread { sh = rs!; hp = rh!; kn = rk! } else { sh = ls!; hp = lh!; kn = lk! }
        } else if rightOk { sh = rs!; hp = rh!; kn = rk! }
          else if leftOk  { sh = ls!; hp = lh!; kn = lk! }
          else {
            deadliftBadFrameStreak += 1
            if deadliftBadFrameStreak >= weightedRepBadFrameLimit { deadliftSmoothedHipAngle = nil }
            return false
        }
        deadliftBadFrameStreak = 0

        let raw = angleDegrees(a: sh, b: hp, c: kn)
        let smoothed: Float = if let prev = deadliftSmoothedHipAngle {
            deadliftEMAAlpha * raw + (1 - deadliftEMAAlpha) * prev
        } else { raw }
        deadliftSmoothedHipAngle = smoothed

        switch deadliftRepPhase {
        case .hinged:
            if smoothed >= deadliftLockoutThreshold {
                deadliftRepPhase = .lockedOut
                deadliftRepCycleStartTime = now
                beginAnkleStabilityCycle(overlay: overlay)
            }
            return false

        case .lockedOut:
            guard smoothed <= deadliftHingeThreshold else { return false }
            let dur = now.timeIntervalSince(deadliftRepCycleStartTime ?? now)
            if let last = lastRepValidationTime, now.timeIntervalSince(last) < deadliftMinRepInterval {
                deadliftRepPhase = .hinged; deadliftRepCycleStartTime = nil
                resetCurrentRepCycleAnkleStability()
                return false
            }
            if dur < deadliftMinRepCycleDuration {
                deadliftRepPhase = .hinged; deadliftRepCycleStartTime = nil
                resetCurrentRepCycleAnkleStability()
                return false
            }
            if dur > deadliftMaxRepCycleDuration {
                deadliftRepPhase = .hinged; deadliftRepCycleStartTime = nil
                resetCurrentRepCycleAnkleStability()
                return false
            }
            if ankleDriftExceedsTolerance(tolerance: deadliftAnkleStabilityTolerance) {
                deadliftRepPhase = .hinged; deadliftRepCycleStartTime = nil
                resetCurrentRepCycleAnkleStability()
                return false
            }
            // Rep counted.
            lastRepValidationTime = now
            deadliftRepPhase = .hinged
            deadliftRepCycleStartTime = nil
            resetCurrentRepCycleAnkleStability()
            return true
        }
    }

    // MARK: - Romanian Deadlift Form Analysis (2D overlay)

    /// Analyzes Romanian deadlift form from 2D overlay landmarks.
    ///
    /// The RDL is a pure hip-hinge with a fixed, slight knee bend. Key differences from
    /// the conventional deadlift: knees must NOT bend further during the descent, and
    /// the emphasis is on hamstring stretch / hinge depth rather than floor-to-lockout power.
    ///
    /// Form Metrics (weighted scoring):
    /// - **Back neutrality (30%)**: Spine should stay flat throughout the hinge.
    /// - **Knee discipline (30%)**: Knees should hold a soft fixed bend (~160-175°), not squat down.
    /// - **Hinge depth (20%)**: Torso should reach at least 50° from vertical for full hamstring stretch.
    /// - **Bar path (20%)**: Bar should slide along the thighs, not drift forward.
    private func analyzeRomanianDeadliftForm(_ points: [String: CGPoint]) -> FormAnalysis {
        let backScore = calculateRdlBackScore(points)
        let kneeScore = calculateRdlKneeBendScore(points)
        let hingeScore = calculateRdlHingeDepthScore(points)
        let barDriftScore = calculateRdlBarDriftScore(points)

        let overallScore = (backScore * 0.30) +
                           (kneeScore * 0.30) +
                           (hingeScore * 0.20) +
                           (barDriftScore * 0.20)

        var issues: [IssueCode] = []
        if backScore < CoachingContract.Threshold.rdlRoundedBack { issues.append(.rdlRoundedBack) }
        if kneeScore < CoachingContract.Threshold.rdlKneeBend { issues.append(.rdlExcessiveKneeBend) }
        if hingeScore < CoachingContract.Threshold.rdlShallowHinge { issues.append(.rdlShallowHinge) }
        if barDriftScore < CoachingContract.Threshold.rdlBarDrift { issues.append(.rdlBarDrift) }
        issues = Array(issues.prefix(CoachingContract.maxIssuesInPayload))

        let backAngle = calculateDeadliftTorsoAngle(points) // reuse deadlift torso angle calc
        let summary = generateRdlFormSummary(overallScore: overallScore)

        return FormAnalysis(
            depth: 0.5,
            backAngle: backAngle,
            kneeAlignment: 0.0,
            overallScore: overallScore,
            issues: issues,
            summary: summary,
            repCount: repCount,
            avgEccentricMs: nil, avgPauseMs: nil, avgConcentricMs: nil,
            avgBottomDepth: nil, deepRepRatio: nil
        )
    }

    /// 3D Romanian deadlift form analysis using world-coordinate skeleton.
    private func analyzeRomanianDeadliftForm3D(_ skeleton: Skeleton3D) -> FormAnalysis {
        let backScore = calculateRdlBackScore3D(skeleton)
        let kneeScore = calculateRdlKneeBendScore3D(skeleton)
        let hingeScore = calculateRdlHingeDepthScore3D(skeleton)
        let barDriftScore = calculateRdlBarDriftScore3D(skeleton)

        let overallScore = (backScore * 0.30) +
                           (kneeScore * 0.30) +
                           (hingeScore * 0.20) +
                           (barDriftScore * 0.20)

        var issues: [IssueCode] = []
        if backScore < CoachingContract.Threshold.rdlRoundedBack { issues.append(.rdlRoundedBack) }
        if kneeScore < CoachingContract.Threshold.rdlKneeBend { issues.append(.rdlExcessiveKneeBend) }
        if hingeScore < CoachingContract.Threshold.rdlShallowHinge { issues.append(.rdlShallowHinge) }
        if barDriftScore < CoachingContract.Threshold.rdlBarDrift { issues.append(.rdlBarDrift) }
        issues = Array(issues.prefix(CoachingContract.maxIssuesInPayload))

        let backAngle = calculateDeadliftTorsoAngle3D(skeleton) // reuse deadlift torso angle calc
        let summary = generateRdlFormSummary(overallScore: overallScore)

        return FormAnalysis(
            depth: 0.5,
            backAngle: backAngle,
            kneeAlignment: 0.0,
            overallScore: overallScore,
            issues: issues,
            summary: summary,
            repCount: repCount,
            avgEccentricMs: nil, avgPauseMs: nil, avgConcentricMs: nil,
            avgBottomDepth: nil, deepRepRatio: nil
        )
    }

    // MARK: RDL — Rounded Back Detection

    /// Checks spine neutrality using the same head-shoulder-hip angle approach as the
    /// conventional deadlift. RDL loading is lighter but the hinge is deeper, so
    /// rounding risk persists throughout the eccentric (lowering) phase.
    private func calculateRdlBackScore(_ points: [String: CGPoint]) -> Float {
        // Reuse the deadlift back score — same biomechanic, same thresholds
        return calculateDeadliftBackScore(points)
    }

    private func calculateRdlBackScore3D(_ skeleton: Skeleton3D) -> Float {
        return calculateDeadliftBackScore3D(skeleton)
    }

    // MARK: RDL — Excessive Knee Bend Detection

    /// The hallmark of the RDL: knees should hold a fixed soft bend (~160-175°).
    /// If the knee angle drops below ~140°, the user is squatting into the movement
    /// rather than hinging. Measures the average knee angle (shoulder→hip→ankle bisection
    /// at the knee vertex).
    /// Returns 1.0 for soft fixed bend, 0.0 for deep knee bend.
    private func calculateRdlKneeBendScore(_ points: [String: CGPoint]) -> Float {
        guard let leftHip = points["leftHip"], let rightHip = points["rightHip"],
              let leftKnee = points["leftKnee"], let rightKnee = points["rightKnee"],
              let leftAnkle = points["leftAnkle"], let rightAnkle = points["rightAnkle"] else {
            return 0.7
        }

        // Compute knee angle for each side: hip→knee→ankle
        let leftAngleDeg = angle2D(a: leftHip, b: leftKnee, c: leftAnkle)
        let rightAngleDeg = angle2D(a: rightHip, b: rightKnee, c: rightAnkle)
        let avgKneeAngle = (leftAngleDeg + rightAngleDeg) / 2.0

        let idealMin = CoachingContract.Threshold.rdlKneeAngleIdealMin
        let tooMuch = CoachingContract.Threshold.rdlKneeAngleTooMuch

        // 175° = nearly straight (perfect RDL). 155° = acceptable soft bend. 135° = too much.
        if avgKneeAngle >= idealMin { return 1.0 }
        if avgKneeAngle <= tooMuch { return 0.0 }
        return (avgKneeAngle - tooMuch) / (idealMin - tooMuch)
    }

    /// Helper: angle at vertex b formed by rays b→a and b→c, in 2D screen coords (degrees).
    private func angle2D(a: CGPoint, b: CGPoint, c: CGPoint) -> Float {
        let ba = SIMD2<Float>(Float(a.x - b.x), Float(a.y - b.y))
        let bc = SIMD2<Float>(Float(c.x - b.x), Float(c.y - b.y))
        let lenBA = simd_length(ba)
        let lenBC = simd_length(bc)
        guard lenBA > 0.001, lenBC > 0.001 else { return 170 }
        let cosAngle = simd_dot(ba, bc) / (lenBA * lenBC)
        return acos(max(-1, min(1, cosAngle))) * 180.0 / .pi
    }

    private func calculateRdlKneeBendScore3D(_ skeleton: Skeleton3D) -> Float {
        guard let lh = skeleton.position("leftHip"), let rh = skeleton.position("rightHip"),
              let lk = skeleton.position("leftKnee"), let rk = skeleton.position("rightKnee"),
              let la = skeleton.position("leftAnkle"), let ra = skeleton.position("rightAnkle") else {
            return 0.7
        }

        let leftAngleDeg = angleDegrees(a: lh, b: lk, c: la)
        let rightAngleDeg = angleDegrees(a: rh, b: rk, c: ra)
        let avgKneeAngle = (leftAngleDeg + rightAngleDeg) / 2.0

        let idealMin = CoachingContract.Threshold.rdlKneeAngleIdealMin
        let tooMuch = CoachingContract.Threshold.rdlKneeAngleTooMuch
        if avgKneeAngle >= idealMin { return 1.0 }
        if avgKneeAngle <= tooMuch { return 0.0 }
        return (avgKneeAngle - tooMuch) / (idealMin - tooMuch)
    }

    // MARK: RDL — Hinge Depth Detection

    /// Checks whether the user hinges deeply enough for a full hamstring stretch.
    /// The torso should reach at least 50° from vertical (ideally 60-80°).
    /// Returns 1.0 for deep hinge, 0.0 for barely bending forward.
    private func calculateRdlHingeDepthScore(_ points: [String: CGPoint]) -> Float {
        let torsoAngle = calculateDeadliftTorsoAngle(points) // degrees from vertical
        let deepEnough = CoachingContract.Threshold.rdlHingeDepthMin
        let shallow = CoachingContract.Threshold.rdlHingeShallow

        if torsoAngle >= deepEnough { return 1.0 }
        if torsoAngle <= shallow { return 0.0 }
        return (torsoAngle - shallow) / (deepEnough - shallow)
    }

    private func calculateRdlHingeDepthScore3D(_ skeleton: Skeleton3D) -> Float {
        let torsoAngle = calculateDeadliftTorsoAngle3D(skeleton)
        let deepEnough = CoachingContract.Threshold.rdlHingeDepthMin
        let shallow = CoachingContract.Threshold.rdlHingeShallow

        if torsoAngle >= deepEnough { return 1.0 }
        if torsoAngle <= shallow { return 0.0 }
        return (torsoAngle - shallow) / (deepEnough - shallow)
    }

    // MARK: RDL — Bar Drift Detection

    /// Detects when the bar drifts away from the thighs during the RDL.
    /// Uses the same wrist-to-hip offset approach as the conventional deadlift
    /// but with a tighter threshold since the RDL emphasizes the bar
    /// tracing the quads/thighs throughout.
    private func calculateRdlBarDriftScore(_ points: [String: CGPoint]) -> Float {
        guard let leftWrist = points["leftWrist"], let rightWrist = points["rightWrist"],
              let leftHip = points["leftHip"], let rightHip = points["rightHip"],
              let leftShoulder = points["leftShoulder"], let rightShoulder = points["rightShoulder"] else {
            return 0.8
        }
        let midWristX = Float((leftWrist.x + rightWrist.x) / 2)
        let midHipX = Float((leftHip.x + rightHip.x) / 2)
        let shoulderWidth = abs(Float(leftShoulder.x - rightShoulder.x))
        guard shoulderWidth > 0.001 else { return 0.8 }

        let drift = abs(midWristX - midHipX) / shoulderWidth
        let driftLimit = CoachingContract.Threshold.rdlBarDriftRatio

        if drift <= driftLimit * 0.5 { return 1.0 }
        if drift >= driftLimit * 2.0 { return 0.0 }
        if drift <= driftLimit { return max(0.6, 1.0 - (drift - driftLimit * 0.5) / (driftLimit * 0.5)) }
        return max(0.0, 1.0 - (drift - driftLimit) / driftLimit)
    }

    private func calculateRdlBarDriftScore3D(_ skeleton: Skeleton3D) -> Float {
        guard let lw = skeleton.position("leftWrist"), let rw = skeleton.position("rightWrist"),
              let lh = skeleton.position("leftHip"), let rh = skeleton.position("rightHip"),
              let ls = skeleton.position("leftShoulder"), let rs = skeleton.position("rightShoulder") else {
            return 0.8
        }
        let midWrist = (lw + rw) * 0.5
        let midHip = (lh + rh) * 0.5
        let shoulderWidth = length(ls - rs)
        guard shoulderWidth > 0.001 else { return 0.8 }

        let driftVec = SIMD2<Float>(midWrist.x - midHip.x, midWrist.z - midHip.z)
        let drift = simd_length(driftVec) / shoulderWidth
        let driftLimit = CoachingContract.Threshold.rdlBarDriftRatio

        if drift <= driftLimit * 0.5 { return 1.0 }
        if drift >= driftLimit * 2.0 { return 0.0 }
        if drift <= driftLimit { return max(0.6, 1.0 - (drift - driftLimit * 0.5) / (driftLimit * 0.5)) }
        return max(0.0, 1.0 - (drift - driftLimit) / driftLimit)
    }

    // MARK: RDL — Summary

    private func generateRdlFormSummary(overallScore: Float) -> String {
        let pct = Int(overallScore * 100)
        if overallScore > 0.85 { return "Excellent RDL form! Score: \(pct)%" }
        if overallScore > 0.7  { return "Good RDL form. Score: \(pct)%" }
        if overallScore > 0.5  { return "RDL form needs some work. Score: \(pct)%" }
        return "Focus on RDL basics. Score: \(pct)%"
    }

    // MARK: RDL — Rep Validation

    /// RDL rep detection — bodyweight-style algorithm on the 3D hip angle.
    ///
    /// User starts standing (~170°), hinges down to ~90–110°, returns to standing. Mirror image
    /// of the conventional deadlift (which starts hinged) — same shape, swapped rest state.
    private func validateRomanianDeadliftRep(skeleton: Skeleton3D?, overlay: [String: CGPoint]?, now: Date) -> Bool {
        guard let skeleton = skeleton else { return false }

        let ls = skeleton.position("leftShoulder"),  lh = skeleton.position("leftHip"),  lk = skeleton.position("leftKnee")
        let rs = skeleton.position("rightShoulder"), rh = skeleton.position("rightHip"), rk = skeleton.position("rightKnee")
        let leftOk  = ls != nil && lh != nil && lk != nil
        let rightOk = rs != nil && rh != nil && rk != nil

        let sh: SIMD3<Float>, hp: SIMD3<Float>, kn: SIMD3<Float>
        if leftOk, rightOk {
            let lSpread = abs(ls!.x - lk!.x) + abs(ls!.y - lk!.y) + abs(ls!.z - lk!.z)
            let rSpread = abs(rs!.x - rk!.x) + abs(rs!.y - rk!.y) + abs(rs!.z - rk!.z)
            if rSpread >= lSpread { sh = rs!; hp = rh!; kn = rk! } else { sh = ls!; hp = lh!; kn = lk! }
        } else if rightOk { sh = rs!; hp = rh!; kn = rk! }
          else if leftOk  { sh = ls!; hp = lh!; kn = lk! }
          else {
            rdlBadFrameStreak += 1
            if rdlBadFrameStreak >= weightedRepBadFrameLimit { rdlSmoothedHipAngle = nil }
            return false
        }
        rdlBadFrameStreak = 0

        let raw = angleDegrees(a: sh, b: hp, c: kn)
        let smoothed: Float = if let prev = rdlSmoothedHipAngle {
            rdlEMAAlpha * raw + (1 - rdlEMAAlpha) * prev
        } else { raw }
        rdlSmoothedHipAngle = smoothed

        switch rdlRepPhase {
        case .standing:
            // Post-rep verification: a candidate rep is awaiting confirmation that the user
            // remains planted. Sample ankle Y on each frame; if the user dives into the next
            // hinge before the window elapses, credit the prior rep immediately and start the
            // new cycle. After the window elapses, accept the rep if drift stayed within
            // tolerance, otherwise discard.
            if var pending = rdlPendingRep {
                if let ov = overlay, let la = ov["leftAnkle"], let ra = ov["rightAnkle"] {
                    let ankleY = Float((la.y + ra.y) / 2)
                    pending.minAnkleY = min(pending.minAnkleY, ankleY)
                    pending.maxAnkleY = max(pending.maxAnkleY, ankleY)
                    rdlPendingRep = pending
                }
                if smoothed <= rdlHingeThreshold {
                    let priorTime = pending.candidateTime
                    rdlPendingRep = nil
                    lastRepValidationTime = priorTime
                    rdlRepPhase = .hinged
                    rdlRepCycleStartTime = now
                    rdlMaxLowerWristYInHinge = -.greatestFiniteMagnitude
                    rdlMinSmoothedHipAngleInHinge = .greatestFiniteMagnitude
                    rdlMinUpdateTime = now
                    rdlAscentStartTime = nil
                    rdlMaxAngleAbovePrevMin = 0
                    rdlBottomReboundDetected = false
                    if let stableY = rdlStandingAnkleY {
                        currentRepCycleAnkleYMin = stableY
                        currentRepCycleAnkleYMax = stableY
                    } else {
                        beginAnkleStabilityCycle(overlay: overlay)
                    }
                    return true
                }
                let elapsed = now.timeIntervalSince(pending.candidateTime)
                if elapsed >= rdlPostRepStabilityWindow {
                    let drift = pending.maxAnkleY - pending.minAnkleY
                    rdlPendingRep = nil
                    if drift > rdlPostRepAnkleDriftMax {
                        rdlLastRejectReason = String(
                            format: "postRepDrift=%.4f tol=%.4f",
                            drift, rdlPostRepAnkleDriftMax
                        )
                        return false
                    }
                    lastRepValidationTime = now
                    return true
                }
                return false
            }

            // Continuously refresh the ankle baseline while the user is verifiably standing,
            // so the rep cycle starts measuring drift from a planted-feet reference point.
            if smoothed >= rdlStandingThreshold,
               let ov = overlay,
               let la = ov["leftAnkle"], let ra = ov["rightAnkle"] {
                rdlStandingAnkleY = Float((la.y + ra.y) / 2)
            }
            if smoothed <= rdlHingeThreshold {
                rdlRepPhase = .hinged
                rdlRepCycleStartTime = now
                rdlMaxLowerWristYInHinge = -.greatestFiniteMagnitude
                rdlMinSmoothedHipAngleInHinge = .greatestFiniteMagnitude
                rdlMinUpdateTime = now
                rdlAscentStartTime = nil
                rdlMaxAngleAbovePrevMin = 0
                rdlBottomReboundDetected = false
                if let stableY = rdlStandingAnkleY {
                    currentRepCycleAnkleYMin = stableY
                    currentRepCycleAnkleYMax = stableY
                } else {
                    beginAnkleStabilityCycle(overlay: overlay)
                }
            }
            return false

        case .hinged:
            // Track the lowest (largest-Y) wrist and the deepest (smallest-angle) hinge seen this
            // cycle so the bar-floor-reach gate below can reject pickups/putdowns. The wrist signal
            // uses the lower of the two wrists — only one needs to be visible/tracked.
            if let ov = overlay {
                var lowestWristY: Float = -.greatestFiniteMagnitude
                if let lw = ov["leftWrist"]  { lowestWristY = max(lowestWristY, Float(lw.y)) }
                if let rw = ov["rightWrist"] { lowestWristY = max(lowestWristY, Float(rw.y)) }
                if lowestWristY != -.greatestFiniteMagnitude {
                    rdlMaxLowerWristYInHinge = max(rdlMaxLowerWristYInHinge, lowestWristY)
                }
            }
            let prevMin = rdlMinSmoothedHipAngleInHinge
            rdlMinSmoothedHipAngleInHinge = min(rdlMinSmoothedHipAngleInHinge, smoothed)
            if rdlMinSmoothedHipAngleInHinge < prevMin {
                rdlMinUpdateTime = now
                // Bottom-rebound: the running min just deepened. If, before this deepening, the
                // smoothed angle had risen meaningfully above the previous min, the cycle is a
                // "descend → partial ascent → deepen further" pattern — a setup/positioning
                // hinge, not a clean rep. Require the previous min to be finite (skips the cycle's
                // first ever min set on entry) and the new min to be at least
                // `rdlBottomReboundMinDecreaseDeg` below it to filter noise blips.
                if prevMin.isFinite,
                   rdlMaxAngleAbovePrevMin >= rdlBottomReboundExcursionDeg,
                   (prevMin - rdlMinSmoothedHipAngleInHinge) >= rdlBottomReboundMinDecreaseDeg {
                    rdlBottomReboundDetected = true
                }
                rdlMaxAngleAbovePrevMin = 0
            } else {
                rdlMaxAngleAbovePrevMin = max(
                    rdlMaxAngleAbovePrevMin,
                    smoothed - rdlMinSmoothedHipAngleInHinge
                )
                if rdlAscentStartTime == nil &&
                   smoothed > rdlMinSmoothedHipAngleInHinge + rdlBottomAscentMargin {
                    rdlAscentStartTime = now
                }
            }

            guard smoothed >= rdlStandingThreshold else { return false }
            let dur = now.timeIntervalSince(rdlRepCycleStartTime ?? now)
            if let last = lastRepValidationTime, now.timeIntervalSince(last) < rdlMinRepInterval {
                rdlLastRejectReason = String(format: "minInterval dt=%.2fs", now.timeIntervalSince(last))
                resetRdlBarFloorReachTrackers()
                rdlRepPhase = .standing; rdlRepCycleStartTime = nil
                resetCurrentRepCycleAnkleStability()
                return false
            }
            if dur < rdlMinRepCycleDuration {
                rdlLastRejectReason = String(format: "tooShort dur=%.2fs", dur)
                resetRdlBarFloorReachTrackers()
                rdlRepPhase = .standing; rdlRepCycleStartTime = nil
                resetCurrentRepCycleAnkleStability()
                return false
            }
            if dur > rdlMaxRepCycleDuration {
                rdlLastRejectReason = String(format: "tooLong dur=%.2fs", dur)
                resetRdlBarFloorReachTrackers()
                rdlRepPhase = .standing; rdlRepCycleStartTime = nil
                resetCurrentRepCycleAnkleStability()
                return false
            }
            if ankleDriftExceedsTolerance(tolerance: rdlAnkleStabilityTolerance) {
                let driftRange = currentRepCycleAnkleYMax - currentRepCycleAnkleYMin
                rdlLastRejectReason = String(format: "ankleDrift range=%.4f tol=%.4f", driftRange, rdlAnkleStabilityTolerance)
                resetRdlBarFloorReachTrackers()
                rdlRepPhase = .standing; rdlRepCycleStartTime = nil
                rdlMinUpdateTime = nil; rdlAscentStartTime = nil
                rdlMaxAngleAbovePrevMin = 0
                rdlBottomReboundDetected = false
                resetCurrentRepCycleAnkleStability()
                return false
            }
            // Bottom-dwell gate: pickup/positioning hinges pause at the deep position before
            // standing back up; real reps bounce off the bottom. Measure the gap between
            // last-min-update and start-of-ascent — long gaps mean the user dwelled.
            if let minTime = rdlMinUpdateTime, let ascentTime = rdlAscentStartTime {
                let dwell = ascentTime.timeIntervalSince(minTime)
                if dwell > rdlMaxBottomDwell {
                    rdlLastRejectReason = String(format: "bottomDwell=%.2fs", dwell)
                    resetRdlBarFloorReachTrackers()
                    rdlRepPhase = .standing; rdlRepCycleStartTime = nil
                    rdlMinUpdateTime = nil; rdlAscentStartTime = nil
                    rdlMaxAngleAbovePrevMin = 0
                    rdlBottomReboundDetected = false
                    resetCurrentRepCycleAnkleStability()
                    return false
                }
            }
            // Bottom-rebound gate: catches "descend → partial ascent → deepen further" cycles
            // that the bottom-dwell gate misses because the min keeps updating during the bounce.
            // Real RDLs go down monotonically and up monotonically; this pattern is a setup or
            // positioning hinge (lowering the bar, adjusting grip, "feeling out" the hinge).
            if rdlBottomReboundDetected {
                rdlLastRejectReason = "bottomRebound"
                resetRdlBarFloorReachTrackers()
                rdlRepPhase = .standing; rdlRepCycleStartTime = nil
                rdlMinUpdateTime = nil; rdlAscentStartTime = nil
                rdlMaxAngleAbovePrevMin = 0
                rdlBottomReboundDetected = false
                resetCurrentRepCycleAnkleStability()
                return false
            }
            // Bar-floor-reach gate: pickup/putdown drops the wrists to floor level AND keeps the
            // hinge shallow (lifter bends knees to reach the bar instead of folding the hips).
            // Reject only when both signals fire — a real RDL hits at most one (deep hinge with
            // shin-level wrists, or shallow rep with shin-level wrists), never both.
            if let standingAnkle = rdlStandingAnkleY,
               rdlMaxLowerWristYInHinge != -.greatestFiniteMagnitude,
               rdlMinSmoothedHipAngleInHinge != .greatestFiniteMagnitude {
                let wristDelta = rdlMaxLowerWristYInHinge - standingAnkle
                let minHingeAngle = rdlMinSmoothedHipAngleInHinge
                if wristDelta > rdlBarFloorReachWristDelta && minHingeAngle > rdlBarFloorReachMinHingeAngle {
                    rdlLastRejectReason = String(
                        format: "barAtFloor wristDelta=%.3f minAngle=%.1f",
                        wristDelta, minHingeAngle
                    )
                    resetRdlBarFloorReachTrackers()
                    rdlRepPhase = .standing; rdlRepCycleStartTime = nil
                    rdlMinUpdateTime = nil; rdlAscentStartTime = nil
                    rdlMaxAngleAbovePrevMin = 0
                    rdlBottomReboundDetected = false
                    resetCurrentRepCycleAnkleStability()
                    return false
                }
            }
            // All in-cycle gates passed. Defer the rep credit until post-rep stability is
            // confirmed — the standing case above handles the verification window. Without an
            // ankle baseline, we can't verify drift, so credit immediately.
            //
            // Confidence skip: when the hinge depth was clearly real-rep territory (minAngle
            // ≤ rdlDeepHingeConfidenceAngle), bypass the post-rep window entirely. The
            // post-rep gate is meant to catch shallow pickup/putdown motions that look like
            // reps; a deep hinge has already cleared that bar on its own. Otherwise the last
            // rep of a set gets falsely rejected when the user moves to set the bar down
            // within the verification window.
            let deepHingeConfident = rdlMinSmoothedHipAngleInHinge != .greatestFiniteMagnitude
                && rdlMinSmoothedHipAngleInHinge <= rdlDeepHingeConfidenceAngle
            resetRdlBarFloorReachTrackers()
            rdlRepPhase = .standing
            rdlRepCycleStartTime = nil
            rdlMinUpdateTime = nil
            rdlAscentStartTime = nil
            rdlMaxAngleAbovePrevMin = 0
            rdlBottomReboundDetected = false
            resetCurrentRepCycleAnkleStability()
            if deepHingeConfident {
                lastRepValidationTime = now
                return true
            }
            let pendingBaselineY: Float? = {
                if let ov = overlay, let la = ov["leftAnkle"], let ra = ov["rightAnkle"] {
                    return Float((la.y + ra.y) / 2)
                }
                return rdlStandingAnkleY
            }()
            guard let baselineY = pendingBaselineY else {
                lastRepValidationTime = now
                return true
            }
            rdlPendingRep = RdlPendingRep(
                candidateTime: now,
                minAnkleY: baselineY,
                maxAnkleY: baselineY
            )
            return false
        }
    }

    private func resetRdlBarFloorReachTrackers() {
        rdlMaxLowerWristYInHinge = -.greatestFiniteMagnitude
        rdlMinSmoothedHipAngleInHinge = .greatestFiniteMagnitude
    }

    // MARK: - Bodyweight-Specific Calculations

    private func calculateBodyweightDepth(_ points: [String: CGPoint]) -> Float {
        // Use nose position for depth calculation - always visible and reliable
        guard let nose = points["nose"] else {
            return 0.5
        }
        
        // Normalized image coords (0–1): Y=0 is top, Y=1 is bottom (same as MediaPipe overlay)
        // When squatting: nose Y increases (moves down); when standing: nose Y decreases (moves up)
        
        // Simple depth calculation: higher Y = deeper squat
        // Normalize to 0-1 range where 0 = standing, 1 = deep squat
        let depth = max(0, min(1, nose.y))
        
        return Float(depth)
    }
    
    private func calculateBodyweightBackAngle(_ points: [String: CGPoint]) -> Float {
        // Enhanced back angle calculation for bodyweight squats
        // More sensitive to natural posture without barbell interference
        
        guard let leftShoulder = points["leftShoulder"],
              let rightShoulder = points["rightShoulder"],
              let leftHip = points["leftHip"],
              let rightHip = points["rightHip"] else {
            return 90.0
        }
        
        // Calculate shoulder and hip centers
        let shoulderCenter = CGPoint(
            x: (leftShoulder.x + rightShoulder.x) / 2.0,
            y: (leftShoulder.y + rightShoulder.y) / 2.0
        )
        
        let hipCenter = CGPoint(
            x: (leftHip.x + rightHip.x) / 2.0,
            y: (leftHip.y + rightHip.y) / 2.0
        )
        
        // Calculate angle between vertical and back line
        let dx = shoulderCenter.x - hipCenter.x
        let dy = shoulderCenter.y - hipCenter.y
        let angle = atan2(dx, dy) * 180.0 / .pi
        
        // Enhanced angle calculation for bodyweight squats
        // More forgiving for natural movement patterns
        let normalizedAngle = abs(angle)
        return Float(normalizedAngle)
    }
    
    private func calculateBodyweightKneeAlignment(_ points: [String: CGPoint]) -> Float {
        // Enhanced knee alignment calculation for bodyweight squats
        // More sensitive to natural knee tracking
        
        guard let leftKnee = points["leftKnee"], let rightKnee = points["rightKnee"],
              let leftAnkle = points["leftAnkle"], let rightAnkle = points["rightAnkle"] else {
            return 0.0
        }
        
        // Calculate knee tracking relative to ankles
        let leftKneeTracking = leftKnee.x - leftAnkle.x
        let rightKneeTracking = rightKnee.x - rightAnkle.x
        
        // Enhanced alignment calculation for bodyweight squats
        // More forgiving for natural movement patterns
        let averageTracking = (leftKneeTracking + rightKneeTracking) / 2.0
        let normalizedAlignment = max(-1.0, min(1.0, averageTracking / 0.1))
        
        return Float(normalizedAlignment)
    }
    
    private func calculateBodyweightOverallScore(depth: Float, backAngle: Float, kneeAlignment: Float) -> Float {
        // Enhanced scoring algorithm for bodyweight squats
        // Weighted toward mobility and control rather than load
        
        // Depth score - more forgiving for bodyweight
        let depthScore = min(depth * 1.5, 1.0) // Enhanced depth sensitivity
        
        // Angle score - optimized for bodyweight movement patterns
        let angleScore = 1.0 - abs(backAngle - 85.0) / 85.0 // Prefer 85 degrees for bodyweight
        
        // Knee alignment score - enhanced for bodyweight
        let alignmentScore = 1.0 - abs(kneeAlignment) / 2.0
        
        // Weighted scoring for bodyweight squats
        // Emphasizes natural movement patterns
        let overallScore = (depthScore * 0.4 + angleScore * 0.4 + alignmentScore * 0.2)
        
        return min(overallScore, 1.0)
    }

    // MARK: - Rule-based issue detection for cues
    private func detectBodyweightIssues(depth: Float, backAngle: Float, kneeAlignment: Float) -> [IssueCode] {
        var issues: [IssueCode] = []
        if depth < 0.45 { issues.append(.insufficientDepth) }
        if backAngle > CoachingContract.Threshold.forwardLean { issues.append(.forwardLean) }
        if kneeAlignment < CoachingContract.Threshold.kneeValgus {
            issues.append(.kneeValgus)
        } else if kneeAlignment > CoachingContract.Threshold.kneeVarus {
            issues.append(.kneeVarus)
        }
        return Array(issues.prefix(CoachingContract.maxIssuesInPayload))
    }
    
    private func generateBodyweightFormSummary(depth: Float, backAngle: Float, overallScore: Float) -> String {
        let scorePercentage = Int(overallScore * 100)
        
        if overallScore > 0.85 {
            return "Excellent bodyweight form! Score: \(scorePercentage)%"
        } else if overallScore > 0.7 {
            return "Good bodyweight form. Score: \(scorePercentage)%"
        } else if overallScore > 0.5 {
            return "Bodyweight form needs work. Score: \(scorePercentage)%"
        } else {
            return "Focus on bodyweight form basics. Score: \(scorePercentage)%"
        }
    }
    
    private func calculateBackAngle(_ points: [String: CGPoint]) -> Float {
        // Simplified back angle calculation
        guard let leftShoulder = points["leftShoulder"],
              let rightShoulder = points["rightShoulder"],
              let leftHip = points["leftHip"],
              let rightHip = points["rightHip"] else {
            return 90.0
        }
        
        // Calculate shoulder and hip centers
        let shoulderCenter = CGPoint(
            x: (leftShoulder.x + rightShoulder.x) / 2.0,
            y: (leftShoulder.y + rightShoulder.y) / 2.0
        )
        
        let hipCenter = CGPoint(
            x: (leftHip.x + rightHip.x) / 2.0,
            y: (leftHip.y + rightHip.y) / 2.0
        )
        
        // Calculate angle between vertical and back line
        let dx = shoulderCenter.x - hipCenter.x
        let dy = shoulderCenter.y - hipCenter.y
        let angle = atan2(dx, dy) * 180.0 / .pi
        
        return Float(abs(angle))
    }
    
    private func calculateOverallScore(depth: Float, backAngle: Float) -> Float {
        // Simplified scoring algorithm
        let depthScore = min(depth * 2.0, 1.0) // Normalize depth
        let angleScore = 1.0 - abs(backAngle - 90.0) / 90.0 // Prefer 90 degrees
        
        return (depthScore + angleScore) / 2.0
    }
    
    private func generateFormSummary(depth: Float, backAngle: Float, overallScore: Float) -> String {
        let scorePercentage = Int(overallScore * 100)
        
        if overallScore > 0.8 {
            return "Excellent form! Score: \(scorePercentage)%"
        } else if overallScore > 0.6 {
            return "Good form. Score: \(scorePercentage)%"
        } else {
            return "Form needs improvement. Score: \(scorePercentage)%"
        }
    }
    
    // MARK: - Automatic Set Detection Methods
    
    func resetRepCount() {
        DispatchQueue.main.async {
            self.repCount = 0
            self.lastRepFormAnalysis = nil
        }
        consecutiveGoodReps = 0
        lastRepTime = nil
        setStartTime = nil
        lastRepValidationTime = nil
        lastSpokenRep = 0
        resetSquatRepPhaseState()
        bodyweightRepHistory.removeAll()
        bodyweightRepPhase = .idle
        bodyweightCurrentRepPeakDepth = 0
        lastCountedRepHipKneeDepthQualityMet = false
        bwSmoothedKneeAngle = nil
        bwRawKneeAngle = nil
        consecutiveFramesAtBottomBenchPress = 0
        consecutiveFramesAtTopBenchPress = 0
        framesSinceGoodPose = 0
        inactivityDetector.resetTimer()
        // Reset tempo tracking
        repStartTime = nil
        bottomTime = nil
        lastDepth = 0
        sumEccentricMs = 0
        sumPauseMs = 0
        sumConcentricMs = 0
        tempoRepSamples = 0
        // Reset ROM tracking
        sumBottomDepth = 0
        bottomDepthSamples = 0
        deepFrameCount = 0
        totalDepthSamples = 0
        currentRepBottomDepthMax = 0
        // Reset close-grip bench press rep detection state
        reachedBottomThisCycleBenchPress = false
        benchPressEccentricStartTime = nil
        benchPressBottomTime = nil
        benchPressBottomWristY = nil
        // Reset pose smoothing state
        currentAnalysisSource = .pose3D
        jointSmoother.reset()
        overlayLandmarkSmoother.reset()
        
        if trackedExerciseType == .closeGripBenchPress || trackedExerciseType == .benchPress {
            initializeBenchPressRepTracking()
        }
        viewpointSmoother.reset(keepBucket: .chest_side)
        activeBodyweightRepProfile = SquatRepProfileTable.profile(for: .chest_side)
        squatExtensionFrameStateInternal = .neither
        resetBodyweightSquatRepCycleState()
        resetRowRepCycleState()
        resetDeadliftRepCycleState()
        resetRdlRepCycleState()
        DispatchQueue.main.async {
            self.currentCameraHeightCategory = .unknown
            self.currentCameraViewCategory = .unknown
            self.currentSquatViewpointBucket = .chest_side
            self.currentSquatProfileName = SquatViewpointBucket.chest_side.rawValue
            self.currentSquatExtensionFrameState = .neither
        }
    }
    
    func resetRepCountingState() {
        DispatchQueue.main.async {
            self.repCount = 0
            self.workoutState = .waiting
            self.lastRepFormAnalysis = nil
        }
        consecutiveGoodReps = 0
        lastRepTime = nil
        setStartTime = nil
        lastRepValidationTime = nil
        lastSpokenRep = 0
        resetSquatRepPhaseState()
        bodyweightRepHistory.removeAll()
        bodyweightRepPhase = .idle
        bodyweightCurrentRepPeakDepth = 0
        lastCountedRepHipKneeDepthQualityMet = false
        bwSmoothedKneeAngle = nil
        bwRawKneeAngle = nil
        consecutiveFramesAtBottomBenchPress = 0
        consecutiveFramesAtTopBenchPress = 0
        framesSinceGoodPose = 0
        inactivityDetector.resetTimer()
        repStartTime = nil
        bottomTime = nil
        lastDepth = 0
        sumEccentricMs = 0
        sumPauseMs = 0
        sumConcentricMs = 0
        tempoRepSamples = 0
        sumBottomDepth = 0
        bottomDepthSamples = 0
        deepFrameCount = 0
        totalDepthSamples = 0
        currentRepBottomDepthMax = 0
        standingHipHeight = nil
        standingLegLength = nil
        standingCalibrationCandidate = nil
        standingCalibrationFrames = 0
        reachedBottomThisCycleBenchPress = false
        benchPressEccentricStartTime = nil
        benchPressBottomTime = nil
        benchPressBottomWristY = nil
        currentAnalysisSource = .pose3D

        if trackedExerciseType == .closeGripBenchPress || trackedExerciseType == .benchPress {
            initializeBenchPressRepTracking()
        }
        viewpointSmoother.reset(keepBucket: .chest_side)
        activeBodyweightRepProfile = SquatRepProfileTable.profile(for: .chest_side)
        squatExtensionFrameStateInternal = .neither
        resetBodyweightSquatRepCycleState()
        resetRowRepCycleState()
        resetDeadliftRepCycleState()
        resetRdlRepCycleState()
        DispatchQueue.main.async {
            self.currentCameraHeightCategory = .unknown
            self.currentCameraViewCategory = .unknown
            self.currentSquatViewpointBucket = .chest_side
            self.currentSquatProfileName = SquatViewpointBucket.chest_side.rawValue
            self.currentSquatExtensionFrameState = .neither
        }
    }
    
    /// Initializes bench press rep tracking state for proper first-rep detection.
    /// Sets up eccentric start time so the first rep's eccentric phase is tracked.
    /// Called when starting a close-grip bench press exercise.
    func initializeBenchPressRepTracking() {
        // Initialize eccentric start time immediately so first rep is tracked
        // This ensures we can measure eccentric tempo from the very first rep
        benchPressEccentricStartTime = CACurrentMediaTime()
        reachedBottomThisCycleBenchPress = false
        benchPressBottomTime = nil
        benchPressBottomWristY = nil
    }
    
    func getCurrentRepCount() -> Int {
        return repCount
    }
    
    func checkForSetEnd() {
        guard workoutState == .exercising else { return }
        
        if inactivityDetector.checkInactivity() {
            handleSetEnd()
        }
    }
    
    func startNewSet() {
        DispatchQueue.main.async {
            self.currentSet += 1
            self.workoutState = .waiting
            self.resetRepCount()
            
            // Provide audio feedback
            SpeechManager.shared.speak("Starting set \(self.currentSet)", priority: .normal)
        }
    }
    
    // MARK: - Bodyweight viewpoint + extension (runs on analysis queue)

    private func updateBodyweightViewpointAndExtension(
        overlay: [String: CGPoint],
        skeleton: Skeleton3D,
        confidence: [String: Float]
    ) {
        let (hCat, _) = SquatViewpointClassifier.classifyCameraHeight(overlay: overlay)
        let (vCat, _) = SquatViewpointClassifier.classifyCameraView(overlay: overlay, confidence: confidence)
        let rawBucket = SquatViewpointBucket.bucket(height: hCat, view: vCat)
        _ = viewpointSmoother.push(candidate: rawBucket)
        activeBodyweightRepProfile = SquatRepProfileTable.profile(for: viewpointSmoother.activeBucket)

        let depth = calculateHipDepth3D(skeleton)
        let newExt = SquatExtensionFrameClassifier.nextState(
            previous: squatExtensionFrameStateInternal,
            hipDepth: depth,
            profile: activeBodyweightRepProfile
        )
        if newExt != squatExtensionFrameStateInternal {
            squatExtensionFrameStateInternal = newExt
            DispatchQueue.main.async {
                self.currentSquatExtensionFrameState = newExt
            }
        }

        DispatchQueue.main.async {
            self.currentCameraHeightCategory = hCat
            self.currentCameraViewCategory = vCat
            self.currentSquatViewpointBucket = self.viewpointSmoother.activeBucket
            self.currentSquatProfileName = self.viewpointSmoother.activeBucket.rawValue
        }
    }

    /// Per-exercise validator opts in to the ankle gate; the analysis-queue sampler is exercise-
    /// agnostic but only writes during the active rep cycle (gated by `isInActiveRepCycle`).
    private func sampleAnkleStability(landmarks: [String: CGPoint]) {
        guard isInActiveRepCycle else { return }
        guard let la = landmarks["leftAnkle"], let ra = landmarks["rightAnkle"] else { return }
        let ankleY = Float((la.y + ra.y) / 2)
        currentRepCycleAnkleYMin = min(currentRepCycleAnkleYMin, ankleY)
        currentRepCycleAnkleYMax = max(currentRepCycleAnkleYMax, ankleY)
    }

    /// True when the active rep state machine is in its mid-cycle phase. Read by `sampleAnkleStability`.
    /// Each per-exercise validator owns its own state machine but they all advance through this
    /// shared concept of "cycle started but not yet completed".
    private var isInActiveRepCycle: Bool {
        switch trackedExerciseType {
        case .bodyweight, .barbell:
            return bwRepPhase == .down
        case .row:
            return rowRepPhase == .flexed
        case .deadlift:
            return deadliftRepPhase == .lockedOut
        case .romanianDeadlift:
            return rdlRepPhase == .hinged
        case .benchPress, .closeGripBenchPress:
            return reachedBottomThisCycleBenchPress
        }
    }

    /// Captures the starting ankle Y when a rep cycle begins. Call from each validator's
    /// rest→active transition, then `barbellAnkleDriftExceedsTolerance()` checks at completion.
    private func beginAnkleStabilityCycle(overlay: [String: CGPoint]?) {
        resetCurrentRepCycleAnkleStability()
        guard let ov = overlay,
              let la = ov["leftAnkle"], let ra = ov["rightAnkle"] else { return }
        let ankleY = Float((la.y + ra.y) / 2)
        currentRepCycleAnkleYMin = ankleY
        currentRepCycleAnkleYMax = ankleY
    }

    private func resetCurrentRepCycleAnkleStability() {
        currentRepCycleAnkleYMin = .greatestFiniteMagnitude
        currentRepCycleAnkleYMax = -.greatestFiniteMagnitude
    }

    private func ankleDriftExceedsTolerance(tolerance: Float? = nil) -> Bool {
        guard currentRepCycleAnkleYMin != .greatestFiniteMagnitude,
              currentRepCycleAnkleYMax != -.greatestFiniteMagnitude else { return false }
        let tol = tolerance ?? ankleStabilityTolerance
        return (currentRepCycleAnkleYMax - currentRepCycleAnkleYMin) > tol
    }

    private func bodyweightOverlayLegSpanY(_ overlay: [String: CGPoint]) -> Float? {
        guard let lh = overlay["leftHip"], let rh = overlay["rightHip"],
              let la = overlay["leftAnkle"], let ra = overlay["rightAnkle"] else { return nil }
        let hipY = Float((lh.y + rh.y) / 2)
        let ankleY = Float((la.y + ra.y) / 2)
        let span = abs(hipY - ankleY)
        return span > 0.02 ? span : nil
    }

    private func rejectBodyweightRep(reason: SquatRepRejectReason, note: String = "") {
        repLog("REP REJECTED  reason=\(reason.rawValue) \(note)")
        bwLastRejectReason = "\(reason.rawValue) \(note)"
        resetBodyweightSquatRepCycleState()
        abortInProgressBodyweightRepAccumulation()
    }

    private func resetBodyweightSquatRepCycleState() {
        bwRepPhase = .up
        bwSmoothedKneeAngle = nil
        bwRepCycleStartTime = nil
        bwBadFrameStreak = 0
        bwRawKneeAngle = nil
        squatRepCycleHipKneeParallelMet = false
        resetCurrentRepCycleAnkleStability()
    }

    // MARK: - Bodyweight squat rep detection (knee angle)
    //
    // Algorithm (matches the MediaPipe squat_counter.py reference script):
    //   1. Extract 3D hip, knee, ankle from the better-visible side.
    //   2. Compute the knee angle (hip→knee→ankle) via angleDegrees().
    //   3. Apply EMA smoothing to reduce landmark jitter.
    //   4. Two-state machine (UP / DOWN) with hysteresis:
    //        UP  → DOWN when smoothed angle ≤ downAngleThreshold  (user squats)
    //        DOWN → UP  when smoothed angle ≥ upAngleThreshold    (user stands — rep counted)
    //      The up-threshold is set well below true standing extension (170°) so a
    //      front-mounted camera — where the femur lies along the depth axis and 3D
    //      depth foreshortens "lockout" to ~155-158° — still triggers the rep.
    //   5. Timing gates reject impossibly fast or slow cycles.
    //
    private func validateBodyweightSquatRep(overlay: [String: CGPoint], skeleton: Skeleton3D, now: Date) -> Bool {
        let profile = activeBodyweightRepProfile

        // --- 1. Extract 3D hip, knee, ankle from the better-visible side ---

        let rh = skeleton.position("rightHip"),  rk = skeleton.position("rightKnee"),  ra = skeleton.position("rightAnkle")
        let lh = skeleton.position("leftHip"),   lk = skeleton.position("leftKnee"),   la = skeleton.position("leftAnkle")
        let rightOk = rh != nil && rk != nil && ra != nil
        let leftOk  = lh != nil && lk != nil && la != nil

        let hip: SIMD3<Float>, knee: SIMD3<Float>, ankle: SIMD3<Float>
        if rightOk, leftOk {
            // Both visible — prefer the side with more spatial spread (closer to camera in side view).
            let rSpread = abs(rh!.x - ra!.x) + abs(rh!.y - ra!.y)
            let lSpread = abs(lh!.x - la!.x) + abs(lh!.y - la!.y)
            if rSpread >= lSpread { hip = rh!; knee = rk!; ankle = ra!; bwSelectedSide = "R" }
            else                  { hip = lh!; knee = lk!; ankle = la!; bwSelectedSide = "L" }
        } else if rightOk { hip = rh!; knee = rk!; ankle = ra!; bwSelectedSide = "R" }
          else if leftOk  { hip = lh!; knee = lk!; ankle = la!; bwSelectedSide = "L" }
          else {
            bwBadFrameStreak += 1
            if bwBadFrameStreak >= bwBadFrameLimit { bwSmoothedKneeAngle = nil }
            return false
        }
        bwBadFrameStreak = 0

        // --- 2. Knee angle + EMA ---

        let rawAngle = angleDegrees(a: hip, b: knee, c: ankle)  // standing ≈ 170°, deep squat ≈ 60–90°
        bwRawKneeAngle = rawAngle

        let alpha = profile.kneeAngleEMAAlpha
        let smoothed: Float = if let prev = bwSmoothedKneeAngle {
            alpha * rawAngle + (1 - alpha) * prev
        } else {
            rawAngle
        }
        bwSmoothedKneeAngle = smoothed

        // --- 3. UP / DOWN state machine ---

        switch bwRepPhase {
        case .up:
            if smoothed <= profile.downAngleThreshold {
                bwRepPhase = .down
                bwRepCycleStartTime = now
                if trackedExerciseType == .barbell {
                    beginAnkleStabilityCycle(overlay: overlay)
                }
                repLog("UP→DOWN  angle=\(smoothed)")
            }
            return false

        case .down:
            guard smoothed >= profile.upAngleThreshold else { return false }

            let dur = now.timeIntervalSince(bwRepCycleStartTime ?? now)
            if let last = lastRepValidationTime, now.timeIntervalSince(last) < profile.minRepInterval {
                rejectBodyweightRep(reason: .minRepInterval, note: "dt=\(now.timeIntervalSince(last))")
                return false
            }
            if dur < profile.minRepCycleDuration {
                rejectBodyweightRep(reason: .minCycleDuration, note: "dur=\(dur)")
                return false
            }
            if dur > profile.maxRepCycleDuration {
                rejectBodyweightRep(reason: .maxCycleDuration, note: "dur=\(dur)")
                return false
            }
            if trackedExerciseType == .barbell, ankleDriftExceedsTolerance() {
                let drift = currentRepCycleAnkleYMax - currentRepCycleAnkleYMin
                rejectBodyweightRep(reason: .ankleDrift, note: "drift=\(drift)")
                resetCurrentRepCycleAnkleStability()
                return false
            }

            // Rep counted.
            lastCountedRepHipKneeDepthQualityMet = squatRepCycleHipKneeParallelMet
            lastRepValidationTime = now
            bwRepPhase = .up
            bwRepCycleStartTime = nil
            squatRepCycleHipKneeParallelMet = false
            if trackedExerciseType == .barbell { resetCurrentRepCycleAnkleStability() }
            repLog("DOWN→UP  REP COUNTED  angle=\(smoothed) dur=\(dur)")
            return true
        }
    }

    // MARK: - Squat rep detection (hip depth hysteresis)

    /// Hip-vs-knee vertical relationship for secondary quality tagging only (does not gate counting).
    private func squatRepHipKneeMetrics(_ skeleton: Skeleton3D) -> SquatRepFrame? {
        guard let lh = skeleton.position("leftHip"),
              let rh = skeleton.position("rightHip"),
              let lk = skeleton.position("leftKnee"),
              let rk = skeleton.position("rightKnee"),
              let la = skeleton.position("leftAnkle"),
              let ra = skeleton.position("rightAnkle") else { return nil }

        let avgHipY = (lh.y + rh.y) / 2
        let avgKneeY = (lk.y + rk.y) / 2
        let hipCenter = (lh + rh) / 2
        let ankleCenter = (la + ra) / 2
        let legLen = standingLegLength ?? length(hipCenter - ankleCenter)
        guard legLen > 0.01 else { return nil }

        let delta = (avgHipY - avgKneeY) / legLen
        return SquatRepFrame(avgHipY: avgHipY, avgKneeY: avgKneeY, legLength: legLen, normalizedHipKneeDelta: delta)
    }

    private func updateSquatRepHipKneeParallelTag(skeleton: Skeleton3D) {
        guard let frame = squatRepHipKneeMetrics(skeleton) else { return }
        let tol: Float = hipKneeBottomToleranceNormalizedBarbell
        if frame.normalizedHipKneeDelta <= tol {
            squatRepCycleHipKneeParallelMet = true
        }
    }

    /// Clears barbell/benchPress hip-depth rep machine only (after a counted rep). Bodyweight uses shoulder-vertical cycle state instead.
    private func resetSquatRepDepthMachineOnly() {
        guard trackedExerciseType != .bodyweight else { return }
        squatRepPhase = .idleAtTop
        squatRepTopHoldFrames = 0
        squatRepBottomHoldFrames = 0
        squatRepMaxDepthThisCycle = 0
        squatRepCycleHipKneeParallelMet = false
    }

    /// Abandon in-flight rep: each exercise type clears its own rep state machine.
    private func abandonSquatRepCycle() {
        switch trackedExerciseType {
        case .bodyweight:
            abortInProgressBodyweightRepAccumulation()
            resetBodyweightSquatRepCycleState()
        case .barbell:
            // `.barbell` runs the bodyweight knee-angle algorithm: clear that state machine.
            resetBodyweightSquatRepCycleState()
        case .row:
            resetRowRepCycleState()
        case .deadlift:
            resetDeadliftRepCycleState()
        case .romanianDeadlift:
            resetRdlRepCycleState()
        case .benchPress, .closeGripBenchPress:
            resetBenchPressRepCycleState()
        }
    }

    /// Clears the bench-press rep state machine. Used for both regular and close-grip bench
    /// when an in-flight rep cycle needs to be abandoned (set end, rep count reset, etc.).
    private func resetBenchPressRepCycleState() {
        reachedBottomThisCycleBenchPress = false
        consecutiveFramesAtBottomBenchPress = 0
        consecutiveFramesAtTopBenchPress = 0
        benchPressBottomTime = nil
        benchPressBottomWristY = nil
        benchPressEccentricStartTime = nil
        resetCurrentRepCycleAnkleStability()
    }

    private func resetRowRepCycleState() {
        rowRepPhase = .extended
        rowSmoothedElbowAngle = nil
        rowRepCycleStartTime = nil
        rowBadFrameStreak = 0
        rowMinShoulderYInFlexed = .greatestFiniteMagnitude
        rowMaxShoulderYInFlexed = -.greatestFiniteMagnitude
        rowMinSmoothedElbowAngleInFlexed = .greatestFiniteMagnitude
        rowMaxBetterWristConfInFlexed = 0
        resetCurrentRepCycleAnkleStability()
    }

    private func resetDeadliftRepCycleState() {
        deadliftRepPhase = .hinged
        deadliftSmoothedHipAngle = nil
        deadliftRepCycleStartTime = nil
        deadliftBadFrameStreak = 0
        resetCurrentRepCycleAnkleStability()
    }

    private func resetRdlRepCycleState() {
        rdlRepPhase = .standing
        rdlSmoothedHipAngle = nil
        rdlRepCycleStartTime = nil
        rdlBadFrameStreak = 0
        rdlMinUpdateTime = nil
        rdlAscentStartTime = nil
        rdlPendingRep = nil
        resetRdlBarFloorReachTrackers()
        resetCurrentRepCycleAnkleStability()
    }

    /// Full reset for new set / rep counting reset (includes abandoning partial bodyweight rep).
    private func resetSquatRepPhaseState() {
        abandonSquatRepCycle()
    }

    private func validateRep(
        skeleton: Skeleton3D?,
        overlay: [String: CGPoint]?,
        confidence: [String: Float],
        formAnalysis: FormAnalysis,
        now: Date
    ) -> Bool {
        switch trackedExerciseType {
        case .benchPress, .closeGripBenchPress:
            if let last = lastRepValidationTime,
               now.timeIntervalSince(last) < minTimeBetweenReps {
                return false
            }
            let requiredScore = poseConfidenceThreshold * 0.5
            if formAnalysis.overallScore < requiredScore {
                return false
            }
            return validateBenchPressRep(formAnalysis: formAnalysis, overlay: overlay, now: now)
        case .bodyweight, .barbell:
            // Barbell back squat reuses the bodyweight knee-angle algorithm: same biomechanics,
            // and the 3D world-coordinate angle is camera-angle invariant. The validator applies
            // a stationary-feet gate for `.barbell` to reject false reps from approaching/leaving
            // the camera.
            guard let sk = skeleton, let ov = overlay else { return false }
            return validateBodyweightSquatRep(overlay: ov, skeleton: sk, now: now)
        case .row:
            return validateRowRep(skeleton: skeleton, overlay: overlay, confidence: confidence, now: now)
        case .deadlift:
            return validateDeadliftRep(skeleton: skeleton, overlay: overlay, now: now)
        case .romanianDeadlift:
            return validateRomanianDeadliftRep(skeleton: skeleton, overlay: overlay, now: now)
        }
    }

    /// Hip-depth hysteresis squat rep validator. Currently unused — kept for reference
    /// while the bodyweight knee-angle validator handles `.bodyweight` and `.barbell`.
    private func validateSquatRepHipDepthLegacy(skeleton: Skeleton3D?, now: Date) -> Bool {
        guard let skeleton = skeleton else { return false }
        let depth = calculateHipDepth3D(skeleton)

        switch squatRepPhase {
        case .idleAtTop:
            if depth >= repStartThreshold {
                squatRepPhase = .descending
                squatRepMaxDepthThisCycle = depth
                squatRepCycleHipKneeParallelMet = false
                squatRepTopHoldFrames = 0
                squatRepBottomHoldFrames = 0
                updateSquatRepHipKneeParallelTag(skeleton: skeleton)
                return false
            }
            if depth <= repTopThreshold {
                squatRepTopHoldFrames = min(squatRepTopHoldFrames + 1, framesForTopConfirmation)
            } else {
                squatRepTopHoldFrames = 0
            }
            return false

        case .descending:
            squatRepMaxDepthThisCycle = max(squatRepMaxDepthThisCycle, depth)
            updateSquatRepHipKneeParallelTag(skeleton: skeleton)
            if depth >= repBottomThreshold {
                squatRepBottomHoldFrames += 1
                if squatRepBottomHoldFrames >= framesForBottomConfirmation {
                    squatRepPhase = .bottomReached
                    squatRepBottomHoldFrames = 0
                }
            } else {
                squatRepBottomHoldFrames = 0
            }
            if depth <= repTopThreshold {
                squatRepTopHoldFrames += 1
                if squatRepTopHoldFrames >= framesForTopConfirmation {
                    abandonSquatRepCycle()
                }
            } else {
                squatRepTopHoldFrames = 0
            }
            return false

        case .bottomReached:
            squatRepMaxDepthThisCycle = max(squatRepMaxDepthThisCycle, depth)
            updateSquatRepHipKneeParallelTag(skeleton: skeleton)
            if depth < repBottomThreshold {
                squatRepPhase = .ascending
                squatRepTopHoldFrames = 0
            }
            return false

        case .ascending:
            updateSquatRepHipKneeParallelTag(skeleton: skeleton)
            if depth >= repBottomThreshold {
                squatRepPhase = .bottomReached
                squatRepBottomHoldFrames = 0
                return false
            }
            if depth <= repTopThreshold {
                squatRepTopHoldFrames += 1
                if squatRepTopHoldFrames >= framesForTopConfirmation {
                    if let last = lastRepValidationTime,
                       now.timeIntervalSince(last) < minTimeBetweenReps {
                        return false
                    }
                    lastCountedRepHipKneeDepthQualityMet = squatRepCycleHipKneeParallelMet
                    lastRepValidationTime = now
                    resetSquatRepDepthMachineOnly()
                    return true
                }
            } else {
                squatRepTopHoldFrames = 0
            }
            return false
        }
    }

    
    /// Validates a bench-press rep (regular or close-grip) using elbow-angle depth.
    ///
    /// Movement pattern: Top (lockout) → Bottom (chest touch) → Top (lockout). Both bench
    /// variants use the same press mechanics, so the same state machine works for both;
    /// only the form-scoring thresholds differ between the two analyzers.
    ///
    /// Depth is read from `formAnalysis.depth`, which the bench analyzers populate from
    /// the elbow extension angle (lockout ~170° → 0.0, chest touch ~80° → 1.0). This is
    /// camera-invariant in 3D; the 2D path uses wrist Y as a proxy.
    ///
    /// Also tracks tempo: measures eccentric (top→bottom) and concentric (bottom→top) phases.
    private func validateBenchPressRep(formAnalysis: FormAnalysis, overlay: [String: CGPoint]?, now: Date) -> Bool {
        let depthValue = formAnalysis.depth

        // 3D path: depth is elbow-angle based (0 = lockout, 1 = chest), camera-invariant
        let bottomThreshold: Float = 0.65
        let topThreshold: Float = 0.25

        let wristY = depthValue

        if benchPressEccentricStartTime == nil {
            if wristY <= topThreshold {
                benchPressEccentricStartTime = CACurrentMediaTime()
            }
        }

        let atBottom = wristY >= bottomThreshold
        let atTop = wristY <= topThreshold

        if atBottom {
            consecutiveFramesAtBottomBenchPress += 1
            consecutiveFramesAtTopBenchPress = 0
            if consecutiveFramesAtBottomBenchPress >= consistentFramesForRepTransition && !reachedBottomThisCycleBenchPress {
                reachedBottomThisCycleBenchPress = true
                benchPressBottomWristY = wristY
                if let eccentricStart = benchPressEccentricStartTime {
                    sumEccentricMs += (CACurrentMediaTime() - eccentricStart) * 1000
                }
                benchPressBottomTime = CACurrentMediaTime()
                // Stationary-feet gate: feet are planted on the floor during a real bench press;
                // the user walking toward / away from the camera shifts the ankle Y significantly.
                beginAnkleStabilityCycle(overlay: overlay)
            }
            return false
        }

        if atTop && reachedBottomThisCycleBenchPress {
            consecutiveFramesAtTopBenchPress += 1
            if consecutiveFramesAtTopBenchPress >= consistentFramesForRepTransition {
                if ankleDriftExceedsTolerance() {
                    reachedBottomThisCycleBenchPress = false
                    benchPressBottomWristY = nil
                    consecutiveFramesAtBottomBenchPress = 0
                    consecutiveFramesAtTopBenchPress = 0
                    resetCurrentRepCycleAnkleStability()
                    return false
                }
                if let bt = benchPressBottomTime {
                    sumConcentricMs += (CACurrentMediaTime() - bt) * 1000
                    tempoRepSamples += 1
                }
                lastRepValidationTime = now
                reachedBottomThisCycleBenchPress = false
                benchPressBottomWristY = nil
                benchPressEccentricStartTime = CACurrentMediaTime()
                consecutiveFramesAtBottomBenchPress = 0
                consecutiveFramesAtTopBenchPress = 0
                resetCurrentRepCycleAnkleStability()
                return true
            }
            return false
        }

        consecutiveFramesAtBottomBenchPress = 0
        consecutiveFramesAtTopBenchPress = 0
        return false
    }
    
    /// Handles rep detection: increments rep count and stores form analysis for score calculation.
    /// Bodyweight rep commit (commitBodyweightRepIfNeeded) is done on the analysis queue before this is dispatched.
    private func handleRepDetected() {
        repCount += 1
        consecutiveGoodReps += 1
        lastRepTime = Date()
        inactivityDetector.updateLastRep()
        
        lastRepFormAnalysis = currentFormAnalysis

        if workoutState == .waiting && consecutiveGoodReps >= minRepsForSetStart {
            handleSetStart()
        }
    }

    /// Builds BodyweightRepMetrics from current-rep accumulators, validates, appends only if valid, resets state.
    /// Bug 2 fix: if shoulder state machine completed a full cycle, use a reduced secondary depth floor
    /// (65% of normal min) so angle-dependent 3D depth compression doesn't silently discard valid reps.
    private func commitBodyweightRepIfNeeded() {
        let depthAtBottom = bodyweightCurrentRepPeakDepth
        let backAngleMax = currentRepBackAngleMax ?? 0
        let kneeWorst = currentRepKneeAlignmentWorst ?? 0
        let hipKneeQ = lastCountedRepHipKneeDepthQualityMet
        let p = activeBodyweightRepProfile
        let goodDepth = p.repGoodDepthThreshold
        let primaryMinBottom = max(bodyweightMinDepthForViableBottom, p.repCountDepthThreshold * 0.82)
        // Secondary floor: 60% of primary. The shoulder state machine already validated a full
        // down-up cycle, so we trust the rep happened — just with compressed 3D depth from the angle.
        let secondaryMinBottom = primaryMinBottom * 0.60

        let shallowDepth = depthAtBottom < goodDepth
        let excessiveForwardLean = backAngleMax > CoachingContract.Threshold.forwardLean
        let kneeValgus = kneeWorst < CoachingContract.Threshold.kneeValgus

        let meetsFrameAndSampleGates = bodyweightRepFrameCount >= bodyweightMinFramesInRep
            && bodyweightKneeWindowSampleCount >= 1
        let meetsPrimaryDepth = depthAtBottom >= primaryMinBottom
        let meetsSecondaryDepth = depthAtBottom >= secondaryMinBottom
        let usedSecondaryFloor = !meetsPrimaryDepth && meetsSecondaryDepth
        let valid = (meetsPrimaryDepth || meetsSecondaryDepth) && meetsFrameAndSampleGates

        if usedSecondaryFloor {
            repLog("COMMIT (secondary floor)  depth=\(depthAtBottom) primaryMin=\(primaryMinBottom) secondaryMin=\(secondaryMinBottom)")
        }
        repLog("COMMIT  depth=\(depthAtBottom) minBottom=\(primaryMinBottom) frames=\(bodyweightRepFrameCount) kneeSamples=\(bodyweightKneeWindowSampleCount) valid=\(valid) hipKneeQ=\(hipKneeQ) secondaryUsed=\(usedSecondaryFloor)")

        let metrics = BodyweightRepMetrics(
            depthAtBottom: depthAtBottom,
            backAngleMax: backAngleMax,
            kneeAlignmentWorstNearBottom: kneeWorst,
            shallowDepth: shallowDepth,
            excessiveForwardLean: excessiveForwardLean,
            kneeValgus: kneeValgus,
            hipKneeDepthQualityMet: hipKneeQ,
            reducedDepthConfidence: usedSecondaryFloor,
            valid: valid,
            timestamp: Date().timeIntervalSince1970
        )
        if valid {
            bodyweightRepHistory.append(metrics)
        }

        bodyweightRepPhase = .idle
        currentRepBackAngleMax = nil
        currentRepKneeAlignmentWorst = nil
        bodyweightRepFrameCount = 0
        bodyweightKneeWindowSampleCount = 0
        bodyweightCurrentRepPeakDepth = 0
        lastCountedRepHipKneeDepthQualityMet = false
    }

    /// Per-set reset shared by rep-driven set start and explicit Track set start.
    private func performPerSetAggregationReset() {
        setStartTime = Date()
        viewpointSmoother.reset(keepBucket: .chest_side)
        activeBodyweightRepProfile = SquatRepProfileTable.profile(for: .chest_side)
        squatExtensionFrameStateInternal = .neither
        resetBodyweightSquatRepCycleState()
        DispatchQueue.main.async {
            self.currentCameraHeightCategory = .unknown
            self.currentCameraViewCategory = .unknown
            self.currentSquatViewpointBucket = .chest_side
            self.currentSquatProfileName = SquatViewpointBucket.chest_side.rawValue
            self.currentSquatExtensionFrameState = .neither
        }
        resetSquatRepPhaseState()
        lastRepValidationTime = nil
        issueCounts.removeAll()
        positiveCounts.removeAll()
        sumOverallScore = 0
        overallScoreSamples = 0
        repStartTime = nil
        bottomTime = nil
        lastDepth = 0
        sumEccentricMs = 0
        sumPauseMs = 0
        sumConcentricMs = 0
        tempoRepSamples = 0
        sumBottomDepth = 0
        bottomDepthSamples = 0
        deepFrameCount = 0
        totalDepthSamples = 0
        currentRepBottomDepthMax = 0
        lastCompletedRepDepthAtBottom = nil
        standingHipHeight = nil
        standingLegLength = nil
        standingCalibrationCandidate = nil
        standingCalibrationFrames = 0
        bodyweightRepHistory.removeAll()
        bodyweightRepPhase = .idle
        currentRepBackAngleMax = nil
        currentRepKneeAlignmentWorst = nil
        bodyweightRepFrameCount = 0
        bodyweightKneeWindowSampleCount = 0
        bodyweightCurrentRepPeakDepth = 0
        lastCountedRepHipKneeDepthQualityMet = false
        bwSmoothedKneeAngle = nil
        bwRawKneeAngle = nil
    }

    /// Call when the user explicitly starts a set (e.g. Track “Begin Set”). Forces `.exercising` and full per-set reset.
    func startManualSet() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.startManualSet() }
            return
        }
        workoutState = .exercising
        performPerSetAggregationReset()
    }

    private func handleSetStart() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.handleSetStart() }
            return
        }
        guard workoutState == .waiting else { return }
        workoutState = .exercising
        performPerSetAggregationReset()
    }
    
    private func handleSetEnd() {
        // Ensure we're on main thread for @Published property updates
        DispatchQueue.main.async {
            guard self.workoutState == .exercising else { return }
            
            self.workoutState = .resting
            // Reset rep count for next set (but keep total workout state)
            self.repCount = 0
            self.consecutiveGoodReps = 0
            self.resetSquatRepPhaseState()
            self.lastRepValidationTime = nil
        }
        
        restStartTime = Date()
        
        // State and rest timer only. Do not call API or SpeechManager here — the UI owns when to
        // request feedback and speak (e.g. TrackView speaks only when the user taps "End Set").
        DispatchQueue.main.async {
            DispatchQueue.main.asyncAfter(deadline: .now() + self.restPeriodDuration) {
                self.handleRestPeriodEnd()
            }
        }
    }
    
    private func handleRestPeriodEnd() {
        // Already on main thread (called from DispatchQueue.main.asyncAfter)
        guard workoutState == .resting else { return }
        
        workoutState = .waiting
    }
    
    func checkForNextSetStart() {
        guard workoutState == .waiting else { return }
        // Rep validation runs only in `handleMediaPipeResult`; do not call `validateRep` here (avoids double-advancing the squat state machine).
        if consecutiveGoodReps >= minRepsForSetStart {
            handleSetStart()
        }
    }

    /// Suppress rep counting and abandon the current rep cycle during set transitions
    /// (e.g. between sets). After `suppressDuration`, re-enables counting only if not exercising.
    func beginEndSetTransition(suppressDuration: TimeInterval = 3.0) {
        SharedCameraSessionManager.shared.suppressRepCounting = true
        abandonSquatRepCycle()
        DispatchQueue.main.asyncAfter(deadline: .now() + suppressDuration) {
            if self.workoutState != .exercising {
                SharedCameraSessionManager.shared.suppressRepCounting = false
            }
        }
    }

    /// Remove the last counted rep if it was validated within `window` seconds of now.
    /// Called by the UI when the user presses End Set to strip phantom reps caused by
    /// reaching toward the phone.
    func retroactiveEndSetFilter(window: TimeInterval = 3.0) {
        guard let lastVal = lastRepValidationTime,
              Date().timeIntervalSince(lastVal) < window,
              repCount > 0 else { return }
        DispatchQueue.main.async {
            self.repCount -= 1
            if self.trackedExerciseType == .bodyweight && !self.bodyweightRepHistory.isEmpty {
                self.bodyweightRepHistory.removeLast()
            }
        }
        repLog("RETROACTIVE END-SET FILTER  removed last rep (validated \(Date().timeIntervalSince(lastVal))s ago, window=\(window)s)")
    }

    // Public method to allow UI to force end a set and use aggregated feedback
    func forceEndCurrentSet() {
        // Guard against phantom last rep: if the most recent rep was validated within
        // the last 1 second, it was likely triggered by the end-set motion itself.
        if let lastVal = lastRepValidationTime,
           Date().timeIntervalSince(lastVal) < 1.0,
           repCount > 0 {
            DispatchQueue.main.async {
                self.repCount -= 1
                if self.trackedExerciseType == .bodyweight && !self.bodyweightRepHistory.isEmpty {
                    self.bodyweightRepHistory.removeLast()
                }
            }
        }
        handleSetEnd()
    }

    // MARK: - Aggregation helpers
    private func aggregateFeedback(from analysis: FormAnalysis) {
        for issue in analysis.issues {
            issueCounts[issue, default: 0] += 1
        }
        if analysis.depth >= CoachingContract.PositiveThreshold.goodDepth {
            positiveCounts[.goodDepth, default: 0] += 1
        }
        if abs(analysis.backAngle) <= CoachingContract.PositiveThreshold.chestTall {
            positiveCounts[.chestTall, default: 0] += 1
        }
        if abs(analysis.kneeAlignment) <= CoachingContract.PositiveThreshold.kneesTracking {
            positiveCounts[.kneesOverToes, default: 0] += 1
        }
        sumOverallScore += Double(analysis.overallScore)
        overallScoreSamples += 1
    }

    /// Public snapshot of per-set aggregation for the set-end feedback planner.
    /// Safe to call at set-end from the main thread; returns a value type.
    func aggregatedMetricsSnapshot() -> SetEndAggregatedMetrics {
        let mean: Float? = overallScoreSamples > 0
            ? Float(sumOverallScore / Double(overallScoreSamples))
            : nil
        return SetEndAggregatedMetrics(
            issueCounts: issueCounts,
            positiveCounts: positiveCounts,
            bodyweightRepHistory: bodyweightRepHistory,
            overallScoreMean: mean
        )
    }
    
    private func updateTempoTracking(currentDepth: Float) {
        let now = CACurrentMediaTime()
        
        let bottomThresh = deepDepthThreshold3D
        let topThresh = shallowDepthThreshold3D
        
        totalDepthSamples += 1
        if currentDepth >= bottomThresh { deepFrameCount += 1 }
        if currentDepth > currentRepBottomDepthMax { currentRepBottomDepthMax = currentDepth }
        if repStartTime == nil, currentDepth <= topThresh {
            repStartTime = now
        }
        if lastDepth < bottomThresh && currentDepth >= bottomThresh {
            bottomTime = now
        }
        if let bTime = bottomTime, lastDepth >= bottomThresh && currentDepth < bottomThresh {
            let pauseMs = max(0, (now - bTime) * 1000.0)
            sumPauseMs += pauseMs
        }
        if let start = repStartTime, lastDepth > topThresh && currentDepth <= topThresh {
            if currentRepBottomDepthMax > 0 {
                sumBottomDepth += Double(currentRepBottomDepthMax)
                bottomDepthSamples += 1
            }
            lastCompletedRepDepthAtBottom = currentRepBottomDepthMax > 0 ? currentRepBottomDepthMax : nil
            let totalMs = (now - start) * 1000.0
            var eccMs = totalMs * 0.5
            var conMs = totalMs * 0.5
            if let bTime = bottomTime {
                let ecc = max(0, (bTime - start) * 1000.0)
                let con = max(0, totalMs - ecc)
                eccMs = ecc
                conMs = con
            }
            sumEccentricMs += eccMs
            sumConcentricMs += conMs
            tempoRepSamples += 1
            repStartTime = nil
            bottomTime = nil
            currentRepBottomDepthMax = 0
        }
        lastDepth = currentDepth
    }
}

// MARK: - MediaPipe Livestream Delegate

extension OnDevicePoseManager: PoseLandmarkerLiveStreamDelegate {
    func poseLandmarker(
        _ poseLandmarker: PoseLandmarker,
        didFinishDetection result: PoseLandmarkerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        handleMediaPipeResult(result, timestampMs: timestampInMilliseconds, error: error)
    }
}
