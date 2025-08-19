import SwiftUI
import CoreMedia
import AVFoundation
import FirebaseCore
import Combine

class WorkoutViewModel: ObservableObject {
    @Published var totalReps: Int = 127
    @Published var formScore: Int = 94
    @Published var currentSetReps: Int = 8
    @Published var goodFormReps: Int = 7
    @Published var currentSetScore: Int = 92
    @Published var coachingStyle: String = "Supportive"
    @Published var workoutGoal: String = "Hypertrophy"
    @Published var selectedExercise: String = "Squat"
    @Published var isWorkoutActive: Bool = false
    @Published var currentFeedback: String = ""
    @Published var depthStatus: FormStatus = .good
    @Published var tempoStatus: FormStatus = .perfect
    @Published var postureStatus: FormStatus = .watch
    
    // Feedback storage
    @Published var realTimeFeedback: [FeedbackItem] = []
    @Published var setFeedback: [FeedbackItem] = []
    @Published var workoutFeedback: [FeedbackItem] = []
    @Published var cloudAnalysisFeedback: CloudAnalysisFeedback?
    
    // Camera setup states
    @Published var isFullBodyVisible: Bool = false
    @Published var hasGoodLighting: Bool = false
    @Published var hasStablePosition: Bool = false
    @Published var isDetecting: Bool = false
    
    // Pose detection manager
    // Removed pose detection manager since we simplified the camera setup
    
    // Video recording and Firebase managers
    private let videoRecordingManager = VideoRecordingManager.shared
    private let firebaseManager = FirebaseManager.shared
    
    // Feedback manager
    private let feedbackManager = FeedbackManager.shared
    
    // Speech manager
    private let speechManager = SpeechManager.shared
    
    // Workout tracking
    private var workoutId: String = ""
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0.0
    @Published var isAnalyzing = false
    @Published var analysisResults: [String: Any]?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupPoseDetection()
        setupVideoFrameObserver()
    }
    
    deinit {
        // Clean up delegate
    }
    
    // MARK: - Video Frame Processing
    private func setupVideoFrameObserver() {
        // No longer needed since we removed pose detection
    }
    
    func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        // No longer needed since we removed pose detection
    }
    
    func startCameraDetection() {
        isDetecting = true
        // No longer needed since we removed pose detection
    }
    
    func stopCameraDetection() {
        isDetecting = false
        // No longer needed since we removed pose detection
    }
    
    // MARK: - Workout Control
    func startWorkout() {
        print("🏋️ Starting workout: \(selectedExercise)")
        
        isWorkoutActive = true
        isDetecting = true
        currentSetReps = 0
        goodFormReps = 0
        // Removed pose detection setup
        
        // Generate unique workout ID and start recording
        workoutId = UUID().uuidString
        print("🆔 Generated workout ID: \(workoutId)")
        
        videoRecordingManager.startRecording(workoutId: workoutId)
        
        // Add workout feedback
        addWorkoutFeedback(
            title: "Workout Started",
            message: "Started \(selectedExercise) workout",
            severity: .success
        )
        
        // Removed intro speech - no longer needed
        
        print("✅ Workout started successfully")
    }
    
    func finishSet() {
        print("🏁 Finishing set")
        
        isDetecting = false
        // Removed pose detection stop
        
        // Stop video recording
        videoRecordingManager.stopRecording()
        
        // Wait a moment for video file to be properly saved
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Upload video and trigger analysis
            self.uploadWorkoutVideo()
        }
        
        // Add set feedback
        let setScore = Double(currentSetScore) / 100.0
        addSetFeedback(
            title: "Set Complete",
            message: "Completed \(currentSetReps) reps with \(goodFormReps) good form reps",
            severity: currentSetScore >= 80 ? .success : .warning,
            formScore: setScore
        )
        
        // Removed default set completion speech - now handled by OpenAI coaching
        
        print("✅ Set finished successfully")
    }
    
    func startNextSet() {
        currentSetReps = 0
        goodFormReps = 0
        currentSetScore = 0
        isDetecting = true
        // Removed pose detection start
        
        // Add set feedback
        addSetFeedback(
            title: "Next Set Started",
            message: "Starting next set of \(selectedExercise)",
            severity: .info
        )
    }
    
    // MARK: - Private Setup
    private func setupPoseDetection() {
        // Removed pose detection setup
    }
    
    private func updateCurrentSetScore() {
        guard currentSetReps > 0 else {
            currentSetScore = 0
            return
        }
        
        let formPercentage = Float(goodFormReps) / Float(currentSetReps)
        currentSetScore = Int(formPercentage * 100)
    }
    
    // MARK: - Video Upload
    private func uploadWorkoutVideo() {
        print("📤 Starting video upload for workout: \(workoutId)")
        
        guard let videoURL = videoRecordingManager.getCurrentVideoURL() else {
            print("❌ No video URL available for upload")
            return
        }
        
        // Check if file actually exists
        let fileExists = FileManager.default.fileExists(atPath: videoURL.path)
        print("📁 Video file exists: \(fileExists)")
        
        if !fileExists {
            print("❌ Video file does not exist at path: \(videoURL.path)")
            // Try to get file size to see if it's a valid file
            if let fileSize = try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int64 {
                print("📊 File size: \(fileSize) bytes")
            } else {
                print("📊 File size: nil bytes")
            }
            return
        }
        
        // Get file size
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int64 {
            print("📊 File size: \(fileSize) bytes")
        }
        
        isUploading = true
        uploadProgress = 0.0
        
        firebaseManager.uploadWorkoutVideo(videoURL: videoURL, workoutId: workoutId) { [weak self] result in
            DispatchQueue.main.async {
                self?.isUploading = false
                
                switch result {
                case .success(let downloadURL):
                    print("✅ Video uploaded successfully: \(downloadURL)")
                    self?.uploadWorkoutData(downloadURL: downloadURL)
                case .failure(let error):
                    print("❌ Video upload failed: \(error.localizedDescription)")
                    self?.uploadProgress = 0.0
                }
            }
        }
        
        // Monitor upload progress
        firebaseManager.$uploadProgress
            .receive(on: DispatchQueue.main)
            .assign(to: \.uploadProgress, on: self)
            .store(in: &cancellables)
    }
    
    private func uploadWorkoutData(downloadURL: String?) {
        let workoutData: [String: Any] = [
            "workoutId": workoutId,
            "exercise": selectedExercise,
            "totalReps": totalReps,
            "formScore": formScore,
            "currentSetReps": currentSetReps,
            "goodFormReps": goodFormReps,
            "currentSetScore": currentSetScore,
            "coachingStyle": coachingStyle,
            "workoutGoal": workoutGoal,
            "videoURL": downloadURL ?? "no_video_available",
            "timestamp": Date().timeIntervalSince1970,
            "duration": videoRecordingManager.recordingDuration
        ]
        
        firebaseManager.uploadWorkoutData(workoutData: workoutData, workoutId: workoutId) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("Workout data uploaded successfully")
                    self?.videoRecordingManager.clearRecording()
                    // Start polling for analysis results
                    self?.startAnalysisPolling()
                case .failure(let error):
                    print("Workout data upload failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // On-device analysis - no polling needed
    private func startAnalysisPolling() {
        // This method is no longer needed with on-device analysis
        print("🎯 Using on-device pose analysis - no polling required")
    }
    
    func getAnalysisResults() -> [String: Any]? {
        return firebaseManager.getAnalysisResults(workoutId: workoutId)
    }
    
    // MARK: - Feedback Management
    func addRealTimeFeedback(title: String, message: String, severity: FeedbackSeverity = .info, repNumber: Int? = nil) {
        let feedback = FeedbackItem(
            type: .realTime,
            severity: severity,
            title: title,
            message: message,
            repNumber: repNumber,
            exerciseType: selectedExercise
        )
        feedbackManager.addFeedback(feedback)
        realTimeFeedback.append(feedback)
    }
    
    func addSetFeedback(title: String, message: String, severity: FeedbackSeverity = .info, formScore: Double? = nil) {
        let feedback = FeedbackItem(
            type: .set,
            severity: severity,
            title: title,
            message: message,
            exerciseType: selectedExercise,
            formScore: formScore
        )
        feedbackManager.addFeedback(feedback)
        setFeedback.append(feedback)
    }
    
    func addWorkoutFeedback(title: String, message: String, severity: FeedbackSeverity = .info) {
        let feedback = FeedbackItem(
            type: .workout,
            severity: severity,
            title: title,
            message: message,
            exerciseType: selectedExercise
        )
        feedbackManager.addFeedback(feedback)
        workoutFeedback.append(feedback)
    }
    
    func addCloudAnalysisFeedback(from analysisResults: [String: Any]) {
        let cloudFeedback = CloudAnalysisFeedback(from: analysisResults)
        cloudAnalysisFeedback = cloudFeedback
        
        // Trigger speech for analysis results
        speechManager.speakAnalysisResults(cloudFeedback)
        
        // Add overall feedback
        for feedback in cloudFeedback.overallFeedback {
            let feedbackItem = FeedbackItem(
                type: .cloudAnalysis,
                severity: .success,
                title: "AI Analysis",
                message: feedback,
                exerciseType: selectedExercise,
                formScore: cloudFeedback.averageFormScore
            )
            feedbackManager.addFeedback(feedbackItem)
        }
        
        // Add recommendations
        for recommendation in cloudFeedback.recommendations {
            let feedbackItem = FeedbackItem(
                type: .cloudAnalysis,
                severity: .info,
                title: "Recommendation",
                message: recommendation,
                exerciseType: selectedExercise,
                recommendations: [recommendation]
            )
            feedbackManager.addFeedback(feedbackItem)
        }
        
        // Add rep-specific feedback
        for repAnalysis in cloudFeedback.repAnalyses {
            for issue in repAnalysis.issues {
                let feedbackItem = FeedbackItem(
                    type: .cloudAnalysis,
                    severity: .warning,
                    title: "Rep \(repAnalysis.repNumber) Issue",
                    message: issue,
                    repNumber: repAnalysis.repNumber,
                    exerciseType: selectedExercise,
                    formScore: repAnalysis.overallScore
                )
                feedbackManager.addFeedback(feedbackItem)
            }
        }
    }
    
    // MARK: - New Architecture Analysis Results
    func addNewArchitectureFeedback(from analysisResults: [String: Any]) {
        // Extract OpenAI feedback from the new architecture (try both field names)
        var feedbackText: String?
        
        if let openAIFeedback = analysisResults["openai_feedback"] as? String {
            feedbackText = openAIFeedback
        } else if let feedback = analysisResults["feedback"] as? String {
            feedbackText = feedback
        }
        
        if let feedbackText = feedbackText {
            // Parse the OpenAI feedback into structured feedback items
            let feedbackItems = parseOpenAIFeedback(feedbackText)
            
            for feedbackItem in feedbackItems {
                feedbackManager.addFeedback(feedbackItem)
            }
            
            // Trigger speech for the OpenAI feedback
            speechManager.speakOpenAIFeedback(analysisResults)
        }
        
        // Store the analysis results for later reference
        cloudAnalysisFeedback = CloudAnalysisFeedback(from: analysisResults)
    }
    
    private func parseOpenAIFeedback(_ feedback: String) -> [FeedbackItem] {
        var feedbackItems: [FeedbackItem] = []
        
        // Split feedback into sections based on common patterns
        let sections = feedback.components(separatedBy: "\n\n")
        
        for section in sections {
            let trimmedSection = section.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSection.isEmpty {
                let feedbackItem = FeedbackItem(
                    type: .cloudAnalysis,
                    severity: .success,
                    title: "AI Coach Feedback",
                    message: trimmedSection,
                    exerciseType: selectedExercise,
                    formScore: 0.8 // Default score for OpenAI feedback
                )
                feedbackItems.append(feedbackItem)
            }
        }
        
        // If no sections found, create a single feedback item
        if feedbackItems.isEmpty {
            let feedbackItem = FeedbackItem(
                type: .cloudAnalysis,
                severity: .success,
                title: "AI Coach Feedback",
                message: feedback,
                exerciseType: selectedExercise,
                formScore: 0.8
            )
            feedbackItems.append(feedbackItem)
        }
        
        return feedbackItems
    }
    
    func clearFeedback(for type: FeedbackType? = nil) {
        if let type = type {
            switch type {
            case .realTime:
                realTimeFeedback.removeAll()
            case .set:
                setFeedback.removeAll()
            case .workout:
                workoutFeedback.removeAll()
            case .cloudAnalysis:
                cloudAnalysisFeedback = nil
            }
        } else {
            realTimeFeedback.removeAll()
            setFeedback.removeAll()
            workoutFeedback.removeAll()
            cloudAnalysisFeedback = nil
        }
        feedbackManager.clearFeedback(for: type)
    }
    
    func getFeedbackSummary() -> FeedbackSummary {
        return feedbackManager.getFeedbackSummary()
    }
    
    func getAllFeedback() -> [FeedbackItem] {
        return feedbackManager.allFeedback
    }
    
    func getFeedback(for type: FeedbackType) -> [FeedbackItem] {
        return feedbackManager.getFeedback(for: type)
    }
}

// MARK: - PoseDetectionDelegate
extension WorkoutViewModel: PoseDetectionDelegate {
    func poseDetectionUpdated(_ results: PoseDetectionResults) {
        // Update any raw pose data if needed
        // This is where you could store keypoints for visualization
    }
    
    func cameraSetupStatusUpdated(_ status: CameraSetupStatus) {
        isFullBodyVisible = status.isFullBodyVisible
        hasGoodLighting = status.hasGoodLighting
        hasStablePosition = status.hasStablePosition
    }
    
    func squatRepCompleted(isGoodForm: Bool) {
        currentSetReps += 1
        
        if isGoodForm {
            goodFormReps += 1
        }
        
        updateCurrentSetScore()
        
        // Update total reps (this might be across all sets)
        totalReps += 1
        
        // Add rep feedback
        addRealTimeFeedback(
            title: "Rep \(currentSetReps) Complete",
            message: isGoodForm ? "Good form rep!" : "Form needs improvement",
            severity: isGoodForm ? .success : .warning,
            repNumber: currentSetReps
        )
        
        // Trigger speech for rep completion
        let repMessage = isGoodForm ? "Good form rep \(currentSetReps)" : "Rep \(currentSetReps) needs improvement"
        speechManager.speakWorkoutEvent(repMessage)
    }
    
    func formFeedbackUpdated(_ feedback: FormFeedback) {
        currentFeedback = feedback.message
        
        // Use FormStatus directly from PoseDetectionManager
        depthStatus = feedback.depthStatus
        postureStatus = feedback.postureStatus
        tempoStatus = feedback.tempoStatus
        
        // Trigger speech for form feedback
        speechManager.speakFormFeedback(feedback)
        
        // Store real-time feedback
        let severity: FeedbackSeverity
        switch feedback.depthStatus {
        case .perfect, .good:
            severity = .success
        case .watch:
            severity = .warning
        case .poor:
            severity = .error
        }
        
        addRealTimeFeedback(
            title: "Form Feedback",
            message: feedback.message,
            severity: severity,
            repNumber: currentSetReps
        )
    }
}