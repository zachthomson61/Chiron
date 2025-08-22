import Foundation
import AVFoundation
import CoreML
import Vision
import UIKit

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
    let kneeAlignment: Float // -1.0 = valgus, 0.0 = aligned, 1.0 = varus
    let overallScore: Float // 0.0-1.0
    let issues: [String]
    let summary: String
    let repCount: Int // Current rep count
    // Average tempo metrics for current set (milliseconds)
    let avgEccentricMs: Float?
    let avgPauseMs: Float?
    let avgConcentricMs: Float?
    // ROM metrics for current set
    let avgBottomDepth: Float?
    let deepRepRatio: Float?
}

// MARK: - Workout State Management
enum WorkoutState {
    case waiting        // Waiting for user to start exercising
    case exercising     // Actively performing reps in a set
    case resting        // Rest period between sets
    case finished       // Workout completed
}

// MARK: - Squat Type
enum SquatType {
    case bodyweight
    case barbell
}

// MARK: - Inactivity Detection
class InactivityDetector {
    private var lastRepTime: Date?
    private var lastValidPoseTime: Date?
    private let inactivityThreshold: TimeInterval = 5.0
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
    static let shared = OnDevicePoseManager()
    
    // MARK: - Pose Detection Properties
    @Published var poseDetected = false
    @Published var currentFormAnalysis: FormAnalysis?
    @Published var repCount: Int = 0
    @Published var workoutState: WorkoutState = .waiting
    @Published var currentSet: Int = 0
    @Published var squatType: SquatType = .bodyweight
    
    // MARK: - Automatic Set Detection Properties
    private var inactivityDetector = InactivityDetector()
    private var consecutiveGoodReps = 0
    private var lastRepTime: Date?
    private var setStartTime: Date?
    private var restStartTime: Date?
    private let restPeriodDuration: TimeInterval = 60.0 // 60 seconds rest
    private let minRepsForSetStart = 2
    private let minTimeBetweenReps: TimeInterval = 0.8  // Minimum 0.8 seconds between reps (MORE SENSITIVE)
    
    // MARK: - Rep Validation Properties
    private var lastRepValidationTime: Date?
    private var repValidationThreshold: TimeInterval = 0.5
    private var movementThreshold: Float = 0.05  // Very sensitive to movement
    private var poseConfidenceThreshold: Float = 0.15  // Even lower confidence threshold for better detection (MORE SENSITIVE)
    // More sensitive depth thresholds for a squat cycle using nose position (normalized 0-1 depth)
    // Relaxed to improve rep detection across different camera crops/heights
    private let deepDepthThreshold: Float = 0.58  // deep when nose >= 0.58
    private let shallowDepthThreshold: Float = 0.48  // top when nose <= 0.48
    // State flag to ensure we saw a deep phase before counting on return to shallow
    private var reachedDeepThisCycle: Bool = false
    
    // MARK: - Audio Feedback Properties
    private var lastSpokenRep: Int = 0
    private var repFeedbackInterval = 5 // Speak every 5 reps
    
    private var poseRequest: VNDetectHumanBodyPoseRequest?
    private var analysisQueue = DispatchQueue(label: "pose.analysis", qos: .userInteractive)
    
    // Cue speaking state
    private var lastCueSpokenAt: Date?
    private var lastCueText: String = ""
    private let cueCooldownSeconds: TimeInterval = 6.0
    private let cueByIssue: [String: String] = [
        "Knee Valgus": "Push your knees out",
        "Knee Varus": "Keep your knees over your toes",
        "Forward Lean": "Lift your chest",
        "Insufficient Depth": "Squat a little deeper"
    ]
    
    // Aggregation for mid-set feedback (collected during the set, spoken between sets)
    private var issueCounts: [String: Int] = [:]
    private var positiveCounts: [String: Int] = [:]
    private let positiveCueByKey: [String: String] = [
        "Good Depth": "Good depth",
        "Chest Tall": "Chest tall",
        "Knees Over Toes": "Knees over toes"
    ]
    
    // Tempo tracking for hypertrophy (milliseconds)
    private var repStartTime: CFTimeInterval?
    private var bottomTime: CFTimeInterval?
    private var lastDepth: Float = 0
    private var sumEccentricMs: Double = 0
    private var sumPauseMs: Double = 0
    private var sumConcentricMs: Double = 0
    private var tempoRepSamples: Int = 0
    private let bottomDepthThreshold: Float = 0.58 // align with deep threshold
    private let topDepthThreshold: Float = 0.48    // align with shallow threshold

    // ROM tracking (depth-based)
    private var sumBottomDepth: Double = 0
    private var bottomDepthSamples: Int = 0
    private var deepFrameCount: Int = 0
    private var totalDepthSamples: Int = 0
    private var currentRepBottomDepthMax: Float = 0
    
    override init() {
        super.init()
        setupPoseDetection()
    }
    
    private func setupPoseDetection() {
        poseRequest = VNDetectHumanBodyPoseRequest { [weak self] request, error in
            self?.handlePoseDetection(request: request, error: error)
        }
    }
    
    // MARK: - Pose Detection
    func analyzeFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let poseRequest = poseRequest else { return }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        
        do {
            try handler.perform([poseRequest])
            
            if let observations = poseRequest.results, !observations.isEmpty {
                let observation = observations[0]
                
                // Update pose detection status
                DispatchQueue.main.async {
                    self.poseDetected = true
                    self.inactivityDetector.updateLastActivity()
                }
                
                // Analyze form and update current analysis
                let formAnalysis = analyzeForm(observation)
                
                // Update tempo tracking using current depth
                self.updateTempoTracking(currentDepth: formAnalysis.depth)
                
                // (Removed verbose nose/depth debug logging)
                
                // IMPORTANT: Ensure this runs on main thread for UI updates
                DispatchQueue.main.async {
                    self.currentFormAnalysis = formAnalysis
                }
                // Real-time cues disabled; feedback will be spoken at set end only
                
                // Aggregate issues and positives for between-sets feedback
                self.aggregateFeedback(from: formAnalysis)
                
                // Check for rep detection on background thread
                if validateRep() {
                    DispatchQueue.main.async {
                        self.handleRepDetected()
                    }
                }
                
                // Check for set transitions
                checkForSetEnd()
                checkForNextSetStart()
                
            } else {
                DispatchQueue.main.async {
                    self.poseDetected = false
                }
            }
        } catch {
            print("⚠️ Error analyzing frame: \(error)")
        }
    }
    
    private func handlePoseDetection(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNHumanBodyPoseObservation] else {
            poseDetected = false
            return
        }
        
        guard let observation = observations.first else {
            poseDetected = false
            return
        }
        
        poseDetected = true
        
        // Analyze form
        let formAnalysis = analyzeForm(observation)
        
        DispatchQueue.main.async {
            self.currentFormAnalysis = formAnalysis
        }
    }
    
    // MARK: - Form Analysis
    private func analyzeForm(_ observation: VNHumanBodyPoseObservation) -> FormAnalysis {
        // Extract key points
        let points = extractKeyPoints(from: observation)
        
        // Use optimized analysis based on squat type
        switch squatType {
        case .bodyweight:
            return analyzeBodyweightSquatForm(points)
        case .barbell:
            return analyzeBarbellSquatForm(points)
        }
    }
    
    private func analyzeBodyweightSquatForm(_ points: [String: CGPoint]) -> FormAnalysis {
        // Enhanced analysis for bodyweight squats with optimized parameters
        
        // Calculate form metrics with bodyweight-specific thresholds
        let depth = calculateBodyweightDepth(points)
        let backAngle = calculateBodyweightBackAngle(points)
        let kneeAlignment = calculateBodyweightKneeAlignment(points)
        let overallScore = calculateBodyweightOverallScore(depth: depth, backAngle: backAngle, kneeAlignment: kneeAlignment)
        let issues = detectBodyweightIssues(depth: depth, backAngle: backAngle, kneeAlignment: kneeAlignment)
        
        // Generate summary with bodyweight-specific feedback
        let summary = generateBodyweightFormSummary(depth: depth, backAngle: backAngle, overallScore: overallScore)
        
        return FormAnalysis(
            depth: depth,
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
    
    private func analyzeBarbellSquatForm(_ points: [String: CGPoint]) -> FormAnalysis {
        // Standard analysis for barbell squats (placeholder for future implementation)
        let depth = calculateDepth(points)
        let backAngle = calculateBackAngle(points)
        let overallScore = calculateOverallScore(depth: depth, backAngle: backAngle)
        
        let summary = generateFormSummary(depth: depth, backAngle: backAngle, overallScore: overallScore)
        
        return FormAnalysis(
            depth: depth,
            backAngle: backAngle,
            kneeAlignment: 0.0,
            overallScore: overallScore,
            issues: [],
            summary: summary,
            repCount: repCount,
            avgEccentricMs: nil,
            avgPauseMs: nil,
            avgConcentricMs: nil,
            avgBottomDepth: nil,
            deepRepRatio: nil
        )
    }
    
    private func extractKeyPoints(from observation: VNHumanBodyPoseObservation) -> [String: CGPoint] {
        var points: [String: CGPoint] = [:]
        
        // Extract key body points
        let recognizedPoints = try? observation.recognizedPoints(.all)
        
        for (key, point) in recognizedPoints ?? [:] {
            if point.confidence > 0.1 {
                // Map Vision joint names to our expected names
                let jointName = mapVisionJointName(key)
                if !jointName.isEmpty {
                    points[jointName] = point.location
                }
            }
        }
        
        return points
    }
    
    private func mapVisionJointName(_ jointName: VNHumanBodyPoseObservation.JointName) -> String {
        // Map Vision's joint names to our expected names
        switch jointName {
        case .leftHip:
            return "leftHip"
        case .rightHip:
            return "rightHip"
        case .leftKnee:
            return "leftKnee"
        case .rightKnee:
            return "rightKnee"
        case .leftAnkle:
            return "leftAnkle"
        case .rightAnkle:
            return "rightAnkle"
        case .leftShoulder:
            return "leftShoulder"
        case .rightShoulder:
            return "rightShoulder"
        case .leftElbow:
            return "leftElbow"
        case .rightElbow:
            return "rightElbow"
        case .leftWrist:
            return "leftWrist"
        case .rightWrist:
            return "rightWrist"
        case .nose:
            return "nose"
        case .leftEye:
            return "leftEye"
        case .rightEye:
            return "rightEye"
        case .leftEar:
            return "leftEar"
        case .rightEar:
            return "rightEar"
        case .neck:
            return "neck"
        case .root:
            return "root"
        default:
            return ""
        }
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
    
    // MARK: - Bodyweight-Specific Calculations
    
    private func calculateBodyweightDepth(_ points: [String: CGPoint]) -> Float {
        // Use nose position for depth calculation - always visible and reliable
        guard let nose = points["nose"] else {
            return 0.5
        }
        
        // In Vision coordinates: Y=0 is top, Y=1 is bottom
        // When squatting: nose Y increases (moves down)
        // When standing: nose Y decreases (moves up)
        
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
    private func detectBodyweightIssues(depth: Float, backAngle: Float, kneeAlignment: Float) -> [String] {
        var issues: [String] = []
        
        // Depth
        if depth < 0.45 { // shallow
            issues.append("Insufficient Depth")
        }
        
        // Torso angle (forward lean)
        if backAngle > 35.0 { // large lean
            issues.append("Forward Lean")
        }
        
        // Knee tracking
        if kneeAlignment < -0.2 {
            issues.append("Knee Valgus")
        } else if kneeAlignment > 0.2 {
            issues.append("Knee Varus")
        }
        
        // Limit to top two to avoid spamming
        return Array(issues.prefix(2))
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
        repCount = 0
        consecutiveGoodReps = 0
        lastRepTime = nil
        setStartTime = nil
        lastRepValidationTime = nil
        lastSpokenRep = 0
        reachedDeepThisCycle = false // Reset the cycle state
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
        print("🔄 Rep count and state reset")
    }
    
    // Add method to reset rep counting state
    func resetRepCountingState() {
        repCount = 0
        consecutiveGoodReps = 0
        lastRepTime = nil
        setStartTime = nil
        lastRepValidationTime = nil
        lastSpokenRep = 0
        reachedDeepThisCycle = false
        workoutState = .waiting
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
        print("🔄 Rep counting state reset")
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
        currentSet += 1
        workoutState = .waiting
        resetRepCount()
        print("🎯 Starting new set: \(currentSet)")
        
        // Provide audio feedback
        SpeechManager.shared.speak("Starting set \(currentSet)", priority: .normal)
    }
    
    // Enhanced rep validation logic - MORE SENSITIVE
    private func validateRep() -> Bool {
        guard let formAnalysis = currentFormAnalysis else { return false }
        
        // Require minimum confidence in pose detection
        if formAnalysis.overallScore < poseConfidenceThreshold {
            return false
        }
        
        let now = Date()
        
        // Time gating to prevent double counting
        if let lastValidation = lastRepValidationTime,
           now.timeIntervalSince(lastValidation) < minTimeBetweenReps {
            return false
        }
        
        let depth = formAnalysis.depth
        
        // State machine for rep counting - MORE SENSITIVE
        if depth >= deepDepthThreshold {
            if !reachedDeepThisCycle {
                print("🏋️ Deep phase detected: depth=\(depth) (threshold: \(deepDepthThreshold))")
                reachedDeepThisCycle = true
            }
            return false
        }
        
        // Check if we completed a full cycle (deep -> shallow) - MORE SENSITIVE
        if reachedDeepThisCycle && depth <= shallowDepthThreshold {
            print("✅ Rep validated! Deep(\(deepDepthThreshold)) -> Shallow(\(depth)) (threshold: \(shallowDepthThreshold))")
            lastRepValidationTime = now
            reachedDeepThisCycle = false
            return true
        }
        
        // Additional check: if we're in a deep position but haven't marked it yet, mark it
        if depth >= (deepDepthThreshold - 0.03) && !reachedDeepThisCycle {
            print("🏋️ Near-deep phase detected: depth=\(depth) (near threshold: \(deepDepthThreshold - 0.03))")
            reachedDeepThisCycle = true
        }
        
        return false
    }
    
    // Add debug logging to track rep detection
    private func handleRepDetected() {
        repCount += 1
        consecutiveGoodReps += 1
        lastRepTime = Date()
        inactivityDetector.updateLastRep()
        
        print("🎯 Rep \(repCount) detected at depth cycle completion")
        
        // Check if we should start the set (after minimum reps)
        if workoutState == .waiting && consecutiveGoodReps >= minRepsForSetStart {
            handleSetStart()
        }
    }
    
    private func handleSetStart() {
        workoutState = .exercising
        setStartTime = Date()
        // Reset aggregations at the start of a set
        issueCounts.removeAll()
        positiveCounts.removeAll()
        // Reset tempo/ROM aggregations per set
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
        print("🎯 Set started automatically with \(repCount) reps")
    }
    
    private func handleSetEnd() {
        guard workoutState == .exercising else { return }
        
        workoutState = .resting
        restStartTime = Date()
        
        print("🏁 Set ended automatically")
        
        // Build mid-set aggregated two-point feedback and speak it
        let (goodCue, improveCue) = aggregatedTwoPointFeedback()
        if !goodCue.isEmpty { SpeechManager.shared.speak(goodCue, priority: .high) }
        if !improveCue.isEmpty { SpeechManager.shared.speak(improveCue, priority: .high) }
        
        // Optionally: still call OpenAI in background for logging/analytics (no additional speech here)
        if let analysis = currentFormAnalysis {
            OpenAICoachingManager.shared.getTwoPointFeedback(formAnalysis: analysis) { _, _ in }
        }
        
        // Start rest period timer
        DispatchQueue.main.asyncAfter(deadline: .now() + restPeriodDuration) {
            self.handleRestPeriodEnd()
        }
    }
    
    private func handleRestPeriodEnd() {
        guard workoutState == .resting else { return }
        
        workoutState = .waiting
        print("⏰ Rest period ended, ready for next set")
    }
    
    func checkForNextSetStart() {
        guard workoutState == .waiting else { return }
        
        // If we detect a rep while waiting, it might be the start of a new set
        if validateRep() {
            consecutiveGoodReps += 1
            
            if consecutiveGoodReps >= minRepsForSetStart {
                handleSetStart()
            }
        }
    }

    // Public method to allow UI to force end a set and use aggregated feedback
    func forceEndCurrentSet() {
        handleSetEnd()
    }

    // MARK: - Aggregation helpers
    private func aggregateFeedback(from analysis: FormAnalysis) {
        // Count issues
        for issue in analysis.issues {
            issueCounts[issue, default: 0] += 1
        }
        // Positives
        if analysis.depth >= 0.6 { positiveCounts["Good Depth", default: 0] += 1 }
        if abs(analysis.backAngle) <= 25 { positiveCounts["Chest Tall", default: 0] += 1 }
        if abs(analysis.kneeAlignment) <= 0.1 { positiveCounts["Knees Over Toes", default: 0] += 1 }
    }
    
    private func aggregatedTwoPointFeedback() -> (String, String) {
        // Choose most frequent positive
        let topPositiveKey = positiveCounts.max(by: { $0.value < $1.value })?.key
        let good = (topPositiveKey.flatMap { positiveCueByKey[$0] }) ?? {
            if let analysis = currentFormAnalysis {
                if analysis.depth >= 0.6 { return "Good depth" }
                if abs(analysis.backAngle) <= 25 { return "Chest tall" }
            }
            return "Controlled tempo"
        }()
        
        // Choose most frequent issue
        let topIssue = issueCounts.max(by: { $0.value < $1.value })?.key
        let improve: String = {
            if let issue = topIssue, let cue = cueByIssue[issue] { return cue }
            if let analysis = currentFormAnalysis {
                if analysis.issues.contains("Knee Valgus") { return "Push your knees out" }
                if analysis.issues.contains("Knee Varus") { return "Keep your knees over your toes" }
                if analysis.issues.contains("Forward Lean") { return "Lift your chest" }
                if analysis.depth < 0.45 { return "Squat a little deeper" }
            }
            return "Brace your core"
        }()
        
        return (good, improve)
    }
    
    private func updateTempoTracking(currentDepth: Float) {
        let now = CACurrentMediaTime()
        // ROM sampling each frame
        totalDepthSamples += 1
        if currentDepth >= bottomDepthThreshold { deepFrameCount += 1 }
        if currentDepth > currentRepBottomDepthMax { currentRepBottomDepthMax = currentDepth }
        if repStartTime == nil, currentDepth <= topDepthThreshold {
            repStartTime = now
        }
        // Detect arriving at bottom
        if lastDepth < bottomDepthThreshold && currentDepth >= bottomDepthThreshold {
            bottomTime = now
        }
        // Detect leaving bottom (start concentric) and compute pause
        if let bTime = bottomTime, lastDepth >= bottomDepthThreshold && currentDepth < bottomDepthThreshold {
            let pauseMs = max(0, (now - bTime) * 1000.0)
            sumPauseMs += pauseMs
        }
        // Detect rep completion when returning near top
        if let start = repStartTime, lastDepth > topDepthThreshold && currentDepth <= topDepthThreshold {
            let totalMs = (now - start) * 1000.0
            // Approximate split: eccentric until bottom, concentric from leaving bottom to top
            // If bottomTime not available, split evenly as fallback
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
            // Record bottom depth for ROM
            if currentRepBottomDepthMax > 0 {
                sumBottomDepth += Double(currentRepBottomDepthMax)
                bottomDepthSamples += 1
            }
            // Reset markers for next rep
            repStartTime = nil
            bottomTime = nil
            currentRepBottomDepthMax = 0
        }
        lastDepth = currentDepth
    }
}
