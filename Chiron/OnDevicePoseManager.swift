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
    private let inactivityThreshold: TimeInterval = 8.0
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
    private let deepDepthThreshold: Float = 0.60  // Nose Y must be >= 0.60 (lower in frame) - deeper squat (MORE SENSITIVE)
    private let shallowDepthThreshold: Float = 0.40  // Nose Y must be <= 0.40 (higher in frame) - standing position (MORE SENSITIVE)
    // State flag to ensure we saw a deep phase before counting on return to shallow
    private var reachedDeepThisCycle: Bool = false
    
    // MARK: - Audio Feedback Properties
    private var lastSpokenRep: Int = 0
    private var repFeedbackInterval = 5 // Speak every 5 reps
    
    private var poseRequest: VNDetectHumanBodyPoseRequest?
    private var analysisQueue = DispatchQueue(label: "pose.analysis", qos: .userInteractive)
    
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
                
                // Debug: Log depth values periodically
                if Int.random(in: 0..<30) == 0 {  // Reduced frequency for cleaner logs
                    print("🎯 Nose-based Depth: \(formAnalysis.depth), Score: \(formAnalysis.overallScore), DeepCycle: \(reachedDeepThisCycle), DeepThresh: \(deepDepthThreshold), ShallowThresh: \(shallowDepthThreshold)")
                }
                
                // IMPORTANT: Ensure this runs on main thread for UI updates
                DispatchQueue.main.async {
                    self.currentFormAnalysis = formAnalysis
                }
                
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
        
        // Generate summary with bodyweight-specific feedback
        let summary = generateBodyweightFormSummary(depth: depth, backAngle: backAngle, overallScore: overallScore)
        
        return FormAnalysis(
            depth: depth,
            backAngle: backAngle,
            kneeAlignment: kneeAlignment,
            overallScore: overallScore,
            issues: [], // Not used in simplified version
            summary: summary,
            repCount: repCount
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
            repCount: repCount
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
            print("⚠️ Nose landmark not found! Available points: \(Array(points.keys))")
            return 0.5
        }
        
        print("✅ Nose landmark found! Position: \(nose)")
        
        // Debug: Log nose detection for troubleshooting
        if Int.random(in: 0..<30) == 0 {
            print("🔍 NOSE: \(nose)")
            print("📏 Nose Y: \(nose.y), Calculated Depth: \(nose.y)")
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
        if depth >= (deepDepthThreshold - 0.05) && !reachedDeepThisCycle {
            print("🏋️ Near-deep phase detected: depth=\(depth) (near threshold: \(deepDepthThreshold - 0.05))")
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
        print("🎯 Set started automatically with \(repCount) reps")
    }
    
    private func handleSetEnd() {
        guard workoutState == .exercising else { return }
        
        workoutState = .resting
        restStartTime = Date()
        
        let formScore = currentFormAnalysis?.overallScore ?? 0.0
        let scorePercentage = Int(formScore * 100)
        
        print("🏁 Set ended automatically: \(repCount) reps, \(scorePercentage)% form score")
        
        // Provide audio feedback with set summary
        let feedback = "Set complete! \(repCount) reps, form score \(scorePercentage) percent"
        SpeechManager.shared.speak(feedback, priority: .high)
        
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
}
