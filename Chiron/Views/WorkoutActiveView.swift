//
//  WorkoutActiveView.swift
//  Chiron
//
//  Active workout flow view for predetermined workouts.
//  Displays exercise progression with video, timers, progress bars, and interactive controls.
//
//  Workout Logging:
//  - Creates WorkoutLog in Firestore when workout starts
//  - Logs ExerciseSetLog entries when user logs weight/reps for sets
//  - Ends WorkoutLog when workout completes
//  - Provides buttons for Weight, Reps, Flag, Guide, History, and Restart
//

import SwiftUI
import AVFoundation

/// Active workout view that handles the exercise flow for any predetermined workout.
///
/// Features:
/// - Video background with exercise progression
/// - Top navigation with exit, play/pause, and overview buttons
/// - Dynamic progress bars for workout phases
/// - Exercise intro buffers with spoken guides
/// - Time-based and rep-based exercise handling
/// - Bottom slide-up tab with action buttons (Weight, Reps, Flag, Guide, History, Restart)
/// - Workout logging to Firebase Firestore
struct WorkoutActiveView: View {
    let workout: PredeterminedWorkout
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State Management
    
    /// Current exercise index
    @State private var currentExerciseIndex: Int = 0
    
    /// Whether workout is paused
    @State private var isPaused: Bool = false
    
    /// Whether showing intro buffer
    @State private var isShowingIntro: Bool = true
    
    /// Intro buffer timer
    @State private var introTimer: Timer?
    
    /// Intro buffer time remaining
    @State private var introTimeRemaining: Int = 0
    
    /// Intro buffer total duration
    @State private var introDuration: Int = 0
    
    /// Exercise timer (for time-based exercises)
    @State private var exerciseTimer: Timer?
    
    /// Time remaining for current exercise
    @State private var exerciseTimeRemaining: Int = 0
    
    /// Reminder timer (for rep-based exercises)
    @State private var reminderTimer: Timer?
    
    /// Workout start time
    @State private var workoutStartTime: Date?
    
    /// Pause start time (when workout was paused)
    @State private var pauseStartTime: Date?
    
    /// Total paused duration (seconds)
    @State private var totalPausedDuration: Int = 0
    
    /// Elapsed workout time (seconds)
    @State private var elapsedWorkoutTime: Int = 0
    
    /// Workout elapsed time timer
    @State private var elapsedTimeTimer: Timer?
    
    /// Whether slide-up tab is expanded
    @State private var isSlideUpTabExpanded: Bool = false
    
    /// Drag offset for slide-up tab
    @State private var dragOffset: CGFloat = 0
    
    /// Whether user is currently dragging
    @State private var isDragging: Bool = false
    
    /// Whether showing exit confirmation
    @State private var showExitConfirmation: Bool = false
    
    /// Whether showing overview
    @State private var showOverview: Bool = false
    
    // MARK: - Workout Logging State
    
    /// Sheet presentation states
    @State private var showWeightInput: Bool = false
    @State private var showRepsInput: Bool = false
    @State private var showFlagOptions: Bool = false
    @State private var showHistory: Bool = false
    
    /// Set tracking: current set number resets to 1 when moving to a new exercise
    @State private var currentSetNumber: Int = 1
    
    /// Set numbers per exercise: tracks the current set number for each exercise index
    @State private var setNumbersPerExercise: [Int: Int] = [:]
    
    /// Firestore document ID for the current workout session
    @State private var currentWorkoutLogId: String?
    
    /// Current set data (reset when set is saved or exercise changes)
    @State private var currentSetWeight: Double?
    @State private var currentSetReps: Int?
    @State private var currentSetPainFlag: Bool = false
    @State private var currentSetNotInControlFlag: Bool = false
    
    /// Exercise data tracking: stores weight/reps per exercise index (persists across navigation)
    @State private var exerciseData: [Int: (weight: Double?, reps: Int?)] = [:]
    
    /// Camera setup selection state for the current camera setup exercise.
    /// - `nil`: Show selection UI (user hasn't chosen yet)
    /// - `.rackAttachment`: Show Rack Attachment setup cues
    /// - `.floor`: Show Floor setup cues
    /// - `.tripod`: Show Tripod setup cues
    /// Resets to `nil` when navigating to/from camera setup exercise.
    @State private var cameraSetupSelection: CameraSetupType? = nil
    
    /// Selected exercise for coaching in multi-exercise sections (Superset 1, Superset 2, Finisher).
    /// Set on the exercise selection card; used to display the exercise name in the camera setup title.
    @State private var selectedExerciseForSection: String? = nil
    
    // MARK: - Test View State
    
    /// Whether the test view camera preview is currently active.
    /// When `true`, the video background is replaced with front camera feed and segmentation overlay.
    @State private var isTestViewActive: Bool = false
    
    /// Segmentation processor for test view overlay.
    /// Processes camera frames to generate real-time quality feedback overlay (green/yellow/red)
    /// based on camera position and the selected view type (RACK, FLOOR, or TRIPOD).
    @StateObject private var testViewSegmentationProcessor = SegmentationProcessor()
    
    // MARK: - Close-Grip Bench Press Coaching State
    
    /// Observes pose manager for real-time form analysis and rep count updates.
    /// Used to display form score and determine when to provide coaching feedback.
    @ObservedObject private var poseManager = OnDevicePoseManager.shared
    
    // MARK: - Form Score State
    
    // Form Score Behavior for Close-Grip Bench Press:
    // ===============================================
    // 1. TRACKING STATE (before first score):
    //    - Shown when pose is detected but no rep has completed yet
    //    - Displays pulsing blue ring with "TRACKING" text
    //    - Only active when smoothedFormScore == 0
    //
    // 2. SCORE DISPLAY (after first rep):
    //    - Once a score is calculated, it persists in the UI
    //    - Remains visible even when pose detection is temporarily lost
    //    - Updates with moving average when new reps are detected
    //    - Tracking state is permanently disabled once score exists
    //
    // 3. SCORE CALCULATION:
    //    - Uses exponential moving average (alpha = 0.55)
    //    - First rep: score snaps directly (no averaging)
    //    - Subsequent reps: weighted average of new score and existing smoothed score
    //    - Falls back to lastRepFormAnalysis if currentFormAnalysis is unavailable
    //
    // 4. PERSISTENCE:
    //    - Score only disappears when explicitly reset (e.g., starting new set)
    //    - Never reverts to tracking state once a score exists
    //    - Never reverts to grey state when pose is lost (score remains visible)
    
    /// Exponential moving average of form scores across all reps in the current set.
    /// 
    /// **Behavior:**
    /// - Persists once calculated and remains visible even when pose detection is temporarily lost
    /// - Updated only when a new rep is detected and completes
    /// - Uses exponential moving average (alpha = 0.55) for smooth transitions
    /// - First rep: score snaps directly; subsequent reps: weighted average
    /// 
    /// **Display:** Shown as numeric score (1-100) in the circular progress ring UI
    @State private var smoothedFormScore: Double = 0.0
    
    /// Timer that checks for rep completion every 1 second.
    /// When a new rep is detected, the form score is updated from the current pose analysis.
    @State private var formScoreUpdateTimer: Timer?
    
    /// Last rep count observed - used to detect when a new rep occurs.
    /// When repCount increases, the form score is updated from the current analysis.
    @State private var lastObservedRepCount: Int = 0
    
    /// Tracks whether pose tracking is active (pose detected but waiting for rep completion).
    /// 
    /// **Important:** Only active when `smoothedFormScore == 0`. Once a score exists,
    /// tracking is permanently disabled so the score can persist.
    @State private var isTrackingActive: Bool = false
    
    /// Stores individual rep scores for reference (not used in calculation).
    /// The moving average is calculated directly from `smoothedFormScore`.
    @State private var repScores: [Double] = []
    
    /// Controls pulsing animation for tracking state indicator.
    @State private var trackingPulseScale: CGFloat = 1.0
    
    /// Tracks whether the camera was closed after completing all close-grip bench press sets.
    /// Set to true after the 3rd set, reset to false when navigating back to any close-grip bench press exercise.
    @State private var isCameraClosedAfterThirdSet: Bool = false
    
    /// Tracks the number of completed close-grip bench press sets (excluding camera setup exercises).
    /// Used to determine when to close the camera after the 3rd set.
    @State private var completedCloseGripBenchPressSets: Int = 0
    
    /// View model for managing AI coaching feedback during rest periods
    @StateObject private var restViewModel = RestViewModel()
    
    /// Previous exercise name - used to detect close-grip bench press → rest transition
    @State private var previousExerciseName: String?
    
    /// Start time of the current close-grip bench press set (for duration calculation)
    @State private var closeGripBenchSetStartTime: Date?
    
    /// Whether coaching feedback was just provided (to avoid interrupting with rest announcement)
    @State private var justProvidedCoaching: Bool = false
    
    /// Workout log service (singleton) - accessed via WorkoutLogService.shared
    
    // MARK: - Camera Setup Type
    
    /// Camera setup type selection for live coaching.
    /// Determines which set of setup instructions to display.
    enum CameraSetupType {
        case rackAttachment
        case floor
        case tripod
        
        /// Returns the display name for the camera setup type.
        var displayName: String {
            switch self {
            case .rackAttachment: return "Mount"
            case .floor: return "Floor"
            case .tripod: return "Tripod"
            }
        }
    }
    
    // MARK: - Computed Properties
    
    /// Current exercise
    private var currentExercise: WorkoutExercise? {
        guard currentExerciseIndex < workout.exercises.count else { return nil }
        return workout.exercises[currentExerciseIndex]
    }
    
    /// Whether current exercise is time-based
    private var isTimeBasedExercise: Bool {
        guard let exercise = currentExercise else { return false }
        return exercise.reps.hasPrefix(":") || exercise.reps.lowercased().hasSuffix("s") || exercise.reps.lowercased().hasSuffix("min")
    }
    
    /// Current exercise duration in seconds (for time-based exercises)
    private var currentExerciseDuration: Int {
        guard let exercise = currentExercise else { return 0 }
        return parseTimeFromReps(exercise.reps)
    }
    
    /// Estimated completion time for rep-based exercises
    private var estimatedRepCompletionTime: Int {
        guard let exercise = currentExercise, !isTimeBasedExercise else { return 0 }
        return calculateEstimatedRepTime(exercise.reps)
    }
    
    /// Exercises grouped by phase
    private var exercisesByPhase: [String: [WorkoutExercise]] {
        Dictionary(grouping: workout.exercises) { exercise in
            exercise.phase ?? "Main Workout"
        }
    }
    
    /// Phases in order
    private var phaseOrder: [String] {
        // Keep original order by finding first occurrence in exercises array
        var ordered: [String] = []
        var seen: Set<String> = []
        for exercise in workout.exercises {
            let phase = exercise.phase ?? "Main Workout"
            if !seen.contains(phase) {
                ordered.append(phase)
                seen.insert(phase)
            }
        }
        return ordered
    }
    
    /// Current phase name
    private var currentPhase: String {
        return currentExercise?.phase ?? "Main Workout"
    }
    
    /// Progress for each phase (0.0 to 1.0)
    private var phaseProgress: [String: Double] {
        var progress: [String: Double] = [:]
        
        // Count how many exercises completed in each phase
        for (phase, exercises) in exercisesByPhase {
            var completedInPhase = 0
            
            // Count exercises in this phase that have been completed
            for i in 0..<min(currentExerciseIndex, workout.exercises.count) {
                let exercise = workout.exercises[i]
                let exercisePhase = exercise.phase ?? "Main Workout"
                if exercisePhase == phase {
                    completedInPhase += 1
                }
            }
            
            progress[phase] = Double(completedInPhase) / Double(exercises.count)
        }
        
        return progress
    }
    
    /// Convert phase data to WorkoutPhase array for the header component
    private var workoutPhases: [WorkoutPhase] {
        phaseOrder.map { phaseName in
            let exercises = exercisesByPhase[phaseName] ?? []
            let progress = phaseProgress[phaseName] ?? 0.0
            
            // Phase is complete if all exercises in the phase are completed
            // A phase is complete when we've moved past all exercises in that phase
            // (i.e., the current exercise is in a different phase, or we've completed all exercises)
            var completedInPhase = 0
            for i in 0..<currentExerciseIndex {
                if i < workout.exercises.count {
                    let exercise = workout.exercises[i]
                    let exercisePhase = exercise.phase ?? "Main Workout"
                    if exercisePhase == phaseName {
                        completedInPhase += 1
                    }
                }
            }
            
            // Phase is complete if we've completed all exercises AND we're not currently in this phase
            let isCurrentPhase = phaseName == currentPhase
            let isComplete = completedInPhase >= exercises.count && exercises.count > 0 && !isCurrentPhase
            
            return WorkoutPhase(
                id: phaseName,
                name: phaseName,
                isComplete: isComplete,
                isCurrent: isCurrentPhase,
                phaseProgress: progress
            )
        }
    }
    
    /// Overall progress based on phases completed (not time or exercises)
    private var phasesCompletedProgress: Double {
        guard !phaseOrder.isEmpty else { return 0.0 }
        let completedCount = workoutPhases.filter { $0.isComplete }.count
        return Double(completedCount) / Double(phaseOrder.count)
    }
    
    /// Total workout duration estimate (seconds)
    private var estimatedTotalDuration: Int {
        workout.duration * 60
    }
    
    /// Estimated time remaining (seconds) based on workout progression (exercises completed), not elapsed time
    private var estimatedTimeRemaining: Int {
        guard workout.exercises.count > 0 else { return 0 }
        
        // Calculate overall workout progress based on exercises completed
        // currentExerciseIndex represents exercises completed (0 = first exercise, 1 = second exercise started, etc.)
        let totalExercises = workout.exercises.count
        let completedExercises = Double(currentExerciseIndex)
        let workoutProgress = completedExercises / Double(totalExercises)
        
        // Calculate remaining time based on workout progression
        let remainingProgress = 1.0 - workoutProgress
        let remainingSeconds = Int(Double(estimatedTotalDuration) * remainingProgress)
        
        return max(0, remainingSeconds)
    }
    
    // MARK: - Close-Grip Bench Press Form Score UI
    
    /// Determines if the current exercise is a close-grip bench press (exact name match, excluding camera setup).
    /// Used to conditionally enable form scoring and coaching features.
    private var isCloseGripBenchPressExercise: Bool {
        guard let exercise = currentExercise else { return false }
        let isExactNameMatch = exercise.name == "Close-Grip Bench Press"
        let isCameraSetup = exercise.notes?.hasPrefix("CAMERA_SETUP") ?? false
        return isExactNameMatch && !isCameraSetup
    }
    
    /// Determines whether to display the form score indicator.
    /// Requirements:
    /// - Exercise must be close-grip bench press (not camera setup)
    /// Shows empty ring when no reps detected yet.
    /// Note: Form score is shown immediately for close-grip bench press since data collection
    /// starts immediately (not gated by intro buffer).
    private var shouldShowFormScore: Bool {
        return isCloseGripBenchPressExercise
    }
    
    /// Raw form score (1-100) calculated from pose manager's analysis.
    /// Returns 0 if no analysis is available.
    /// Form score is calculated locally by OnDevicePoseManager - no OpenAI needed for real-time display.
    /// Raw form score (1-100) from the current or last rep's form analysis.
    /// 
    /// **Fallback Logic:**
    /// - Prefers current form analysis if available
    /// - Falls back to last rep's analysis if current is unavailable
    /// - This ensures score calculation even if pose is temporarily lost after rep completion
    private var rawFormScore: Int {
        let analysis = poseManager.currentFormAnalysis ?? poseManager.lastRepFormAnalysis
        guard let analysis = analysis else {
            return 0
        }
        return max(1, min(100, Int(analysis.overallScore * 100)))
    }
    
    /// Current form score (1-100) displayed in the ring UI.
    /// 
    /// **Source:** Derived from `smoothedFormScore` (exponential moving average)
    /// **Update Frequency:** Only updates when a new rep is detected and completes
    /// **Persistence:** Remains visible once calculated, even when pose detection is lost
    private var currentFormScore: Int {
        return max(0, min(100, Int(smoothedFormScore.rounded())))
    }
    
    /// Color coding for form score ranges:
    /// - 90-100: Emerald green (near perfect execution)
    /// - 75-89: Green (good repeatable form)
    /// - 60-74: Yellow (noticeable breakdown)
    /// - 1-59: Red (unsafe or inefficient)
    private var formScoreColor: Color {
        let score = currentFormScore
        switch score {
        case 90...100:
            return Color(red: 0.0, green: 0.8, blue: 0.4)
        case 75...89:
            return Color.green
        case 60...74:
            return Color.yellow
        default:
            return Color.red
        }
    }
    
    /// Determines if we're in "tracking" state - pose detected but waiting for rep completion.
    /// 
    /// **Tracking State Behavior:**
    /// - Only shown when no form score has been calculated yet (smoothedFormScore == 0)
    /// - Displays pulsing blue ring with "TRACKING" text
    /// - Once a score exists, tracking is permanently disabled so the score can persist
    /// - This ensures the form score remains visible even when pose detection is temporarily lost
    private var isInTrackingState: Bool {
        let hasPose = poseManager.poseDetected && poseManager.currentFormAnalysis != nil
        // Show tracking only if: pose detected AND actively tracking AND no score exists yet
        // Once a score exists, it persists and we don't show tracking anymore
        return hasPose && isTrackingActive && poseManager.repCount == lastObservedRepCount && smoothedFormScore == 0
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background: Video or Test View Camera
                //
                // Test View Mode:
                // - Displays front camera feed in top 65% of screen
                // - Overlays real-time segmentation silhouette (green/yellow/red based on quality)
                // - Quality scoring adapts to selected camera setup view (RACK, FLOOR, TRIPOD)
                // - Activated via "Test View" button on Close-Grip Bench Press camera setup exercises
                if isTestViewActive {
                    // Test View: camera fills available space, card pinned at bottom via safeAreaInset
                    ZStack {
                        TestViewCameraPreview(processor: testViewSegmentationProcessor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        SegmentationOverlayView(processor: testViewSegmentationProcessor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                    }
                    .overlay(alignment: .top) {
                        topNavigationBar
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        // Fixed height in Test View so the inset reserves minimal space; card content fits in ~160pt
                        bottomExerciseCard
                            .frame(height: isTestViewActive ? 160 : nil)
                    }
                    .ignoresSafeArea()
                } else {
                    // Normal video background
                    if let videoName = workout.videoName {
                        CroppedDemoVideoHeader(videoName: videoName)
                            .ignoresSafeArea()
                    } else {
                        Color.background.ignoresSafeArea()
                    }
                    
                    // Normal overlay: top bar + spacer + card
                    VStack(spacing: 0) {
                        topNavigationBar
                        Spacer()
                        bottomExerciseCard
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
        .onAppear {
            startWorkout()
        }
        .onDisappear {
            stopAllTimers()
        }
        .alert("Leave Workout?", isPresented: $showExitConfirmation) {
            Button("Stay", role: .cancel) { }
            Button("Leave", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("Are you sure you want to leave the workout?")
        }
        .sheet(isPresented: $showOverview) {
            WorkoutProgressionView(
                workout: workout,
                onJumpToExercise: { index in
                    jumpToExercise(index: index)
                },
                currentExerciseIndex: currentExerciseIndex,
                exerciseData: exerciseData,
                onUpdateExerciseData: { exerciseIndex, weight, reps in
                    exerciseData[exerciseIndex] = (weight: weight, reps: reps)
                },
                workoutLogId: currentWorkoutLogId,
                onSaveSetLog: { exerciseIndex, weight, reps in
                    saveSetLogForExercise(exerciseIndex: exerciseIndex, weight: weight, reps: reps)
                }
            )
        }
        .sheet(isPresented: $showWeightInput) {
            WeightInputSheet(
                isPresented: $showWeightInput,
                weight: $currentSetWeight,
                onSave: { weight in
                    // Set currentSetWeight AND update exerciseData immediately
                    // Store weight in both places to ensure it's preserved
                    currentSetWeight = weight
                    let currentData = exerciseData[currentExerciseIndex] ?? (weight: nil, reps: nil)
                    exerciseData[currentExerciseIndex] = (weight: weight, reps: currentData.reps)
                    // Save weight even if no reps (user requirement)
                    saveSetLogIfComplete()
                }
            )
        }
        .sheet(isPresented: $showRepsInput) {
            RepsInputSheet(
                isPresented: $showRepsInput,
                reps: $currentSetReps,
                onSave: { reps in
                    currentSetReps = reps
                    // Update exercise data dictionary - use currentSetWeight as source of truth for the current set
                    let currentData = exerciseData[currentExerciseIndex] ?? (weight: nil, reps: nil)
                    // Use currentSetWeight if available (for current set), otherwise fall back to exerciseData weight (for display)
                    exerciseData[currentExerciseIndex] = (weight: currentSetWeight ?? currentData.weight, reps: reps)
                    saveSetLogIfComplete()
                }
            )
        }
        .sheet(isPresented: $showFlagOptions) {
            FlagOptionsSheet(
                isPresented: $showFlagOptions,
                flaggedPain: $currentSetPainFlag,
                flaggedNotInControl: $currentSetNotInControlFlag,
                onSave: { pain, notInControl in
                    currentSetPainFlag = pain
                    currentSetNotInControlFlag = notInControl
                    updateCurrentSetFlags(pain: pain, notInControl: notInControl)
                }
            )
        }
        .sheet(isPresented: $showHistory) {
            if let exercise = currentExercise {
                ExerciseHistorySheet(
                    isPresented: $showHistory,
                    exerciseName: exercise.name
                )
            }
        }
    }
    
    // MARK: - Top Navigation Bar
    
    private var topNavigationBar: some View {
        HStack(alignment: .top) {
            // Exit button
            Button(action: {
                showExitConfirmation = true
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.textPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            // Elapsed time, phase progress header, and time remaining
            HStack(alignment: .center, spacing: 12) {
                // Elapsed time
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatTime(elapsedWorkoutTime))
                        .font(.neueMontrealBold(size: 20))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text("ELAPSED")
                        .font(.neueMontrealRegular(size: 10))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                
                // Workout phase progress header (centered vertically between value and label)
                WorkoutPhaseProgressHeader(
                    phases: workoutPhases,
                    overallProgress: phasesCompletedProgress
                )
                .alignmentGuide(VerticalAlignment.center) { d in d.height / 2 }
                
                // Time remaining
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatTimeRemaining(estimatedTimeRemaining))
                        .font(.neueMontrealBold(size: 20))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text("LEFT")
                        .font(.neueMontrealRegular(size: 10))
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            
            Spacer()
            
            // Play/Pause button and Form Score (if showing)
            VStack(spacing: 8) {
                // Play/Pause button
                Button(action: {
                    togglePause()
                }) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
                
                // Form Score indicator (only for close-grip bench press during active exercise)
                if shouldShowFormScore {
                    formScoreIndicator
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, shouldShowFormScore ? 8 : 16)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(0.6),
                    Color.black.opacity(0.3),
                    Color.clear
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    // MARK: - Form Score Indicator
    
    /// Circular progress ring displaying form score (1-100) for close-grip bench press.
    /// 
    /// **Three Display States:**
    /// 1. **No pose detected**: Grey ring with hyphen "-"
    /// 2. **Tracking (before first score)**: Pulsing blue ring with "TRACKING" text
    ///    - Only shown when no score has been calculated yet
    /// 3. **Score available**: Filled colored ring with numeric score
    ///    - Persists once calculated, even when pose detection is temporarily lost
    ///    - Updates with moving average when new reps are detected
    /// 
    /// **Persistence Logic:**
    /// - Once a score exists, it remains visible regardless of pose detection state
    /// - Score only disappears when explicitly reset (e.g., starting a new set)
    /// - Tracking state is permanently disabled once a score exists
    private var formScoreIndicator: some View {
        let hasPose = poseManager.poseDetected && poseManager.currentFormAnalysis != nil
        // Show score if we have a calculated score (persists even when pose is temporarily lost)
        let showScore = currentFormScore > 0
        // Only show tracking when we have pose, are actively tracking, AND don't have a score yet
        // Once a score exists, it takes priority and persists
        let showTracking = isInTrackingState && hasPose && smoothedFormScore == 0
        
        return ZStack {
            // Background for contrast
            Circle()
                .fill(Color.black.opacity(0.4))
            
            // Background circle (always visible, grey when no pose)
            Circle()
                .stroke(showScore ? Color.gray.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 5)
            
            // Tracking state: pulsing ring
            if showTracking {
                Circle()
                    .stroke(Color.blue.opacity(0.6), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .scaleEffect(trackingPulseScale)
                    .opacity(trackingPulseScale == 1.0 ? 0.8 : 1.0)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                            trackingPulseScale = 1.08
                        }
                    }
                    .onDisappear {
                        trackingPulseScale = 1.0
                    }
            }
            
            // Progress ring (only show when score > 0 and not in tracking state)
            if showScore {
                Circle()
                    .trim(from: 0, to: CGFloat(currentFormScore) / 100.0)
                    .stroke(formScoreColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.15, dampingFraction: 0.8), value: currentFormScore)
            }
            
            // Center content
            VStack(spacing: 2) {
                if showTracking {
                    // Tracking state: show "TRACKING" text
                    Text("...")
                        .font(.neueMontrealBold(size: 14))
                        .foregroundColor(.blue.opacity(0.9))
                } else if showScore {
                    // Score available: show numeric score
                    Text("\(currentFormScore)")
                        .font(.neueMontrealBold(size: 16))
                        .foregroundColor(.textPrimary)
                } else {
                    // No pose detected: show hyphen
                    Text("-")
                        .font(.neueMontrealBold(size: 16))
                        .foregroundColor(.textSecondary.opacity(0.6))
                }
                // Label changes based on state
                Text(showTracking ? "TRACKING" : "FORM")
                    .font(.neueMontrealBold(size: showTracking ? 8 : 10))
                    .foregroundColor(showScore ? .textPrimary.opacity(0.8) : (showTracking ? .blue.opacity(0.8) : .textSecondary.opacity(0.5)))
            }
        }
        .frame(width: 56, height: 56)
        .shadow(color: showScore ? formScoreColor.opacity(0.5) : (showTracking ? Color.blue.opacity(0.3) : Color.black.opacity(0.2)), radius: 4)
    }
    
    /// Overall workout progress (0.0 to 1.0)
    private var overallProgress: Double {
        guard estimatedTotalDuration > 0 else { return 0 }
        return min(1.0, Double(elapsedWorkoutTime) / Double(estimatedTotalDuration))
    }
    
    
    // MARK: - Bottom Exercise Card
    
    private var bottomExerciseCard: some View {
        VStack(spacing: 0) {
            // Slide-up indicator (hidden for camera setup and exercise selection exercises)
            if !isCameraSetupExercise && !isExerciseSelectionExercise {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 40, height: 4)
                    .padding(.vertical, 8)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isSlideUpTabExpanded.toggle()
                            dragOffset = 0
                        }
                    }
            }
            
            // Exercise info card (always visible)
            exerciseInfoCardContent
            
            // Action buttons (shown when expanded, but not for camera setup or exercise selection exercises)
            if isSlideUpTabExpanded && !isCameraSetupExercise && !isExerciseSelectionExercise {
                actionButtonsGrid
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .fixedSize(horizontal: false, vertical: isCameraSetupExercise || isExerciseSelectionExercise)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.7))
                .background(.ultraThinMaterial)
        )
        .clipShape(
            .rect(
                topLeadingRadius: 20,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 20
            )
        )
        .ignoresSafeArea(edges: isTestViewActive ? [] : .bottom)
        .offset(y: dragOffset)
        .gesture(
            // Disable drag gesture for camera setup and exercise selection exercises
            (isCameraSetupExercise || isExerciseSelectionExercise) ? nil : DragGesture()
                .onChanged { value in
                    isDragging = true
                    
                    // Limit drag offset to provide visual feedback without moving too far
                    if !isSlideUpTabExpanded {
                        // When collapsed, only allow dragging up (negative values)
                        if value.translation.height < 0 {
                            // Clamp the offset to prevent too much movement
                            dragOffset = max(value.translation.height, -30)
                        }
                    } else {
                        // When expanded, allow dragging down (positive values) to collapse
                        if value.translation.height > 0 {
                            dragOffset = min(value.translation.height, 30)
                        } else {
                            dragOffset = 0
                        }
                    }
                }
                .onEnded { value in
                    let threshold: CGFloat = 50
                    
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if !isSlideUpTabExpanded {
                            // Currently collapsed - check if should expand
                            if value.translation.height < -threshold {
                                isSlideUpTabExpanded = true
                            }
                        } else {
                            // Currently expanded - check if should collapse
                            if value.translation.height > threshold {
                                isSlideUpTabExpanded = false
                            }
                        }
                        dragOffset = 0
                    }
                    
                    // Delay resetting isDragging to prevent immediate tap gesture
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isDragging = false
                    }
                }
        )
        .onTapGesture {
            // Toggle expansion on tap (buttons will handle their own taps)
            // Disabled for camera setup and exercise selection exercises
            if !isDragging && !isCameraSetupExercise && !isExerciseSelectionExercise {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isSlideUpTabExpanded.toggle()
                    dragOffset = 0
                }
            }
        }
    }
    
    private var exerciseInfoCardContent: some View {
        VStack(spacing: 16) {
            // Exercise name
            if let exercise = currentExercise {
                Text(exercise.name)
                    .font(.neueMontrealBold(size: 24))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                
                // Exercise Selection UI (multi-exercise sections: Superset 1, Superset 2, Finisher)
                if isExerciseSelectionExercise {
                    Text("Which exercise would you like coaching on?")
                        .font(.neueMontrealRegular(size: 14))
                        .foregroundColor(.textSecondary)
                        .padding(.top, 4)
                    
                    exerciseSelectionCardView
                    
                    // Navigation buttons: Overview, Back, Forward
                    HStack {
                        Button(action: {
                            showOverview = true
                        }) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        
                        if currentExerciseIndex > 0 {
                            Button(action: {
                                moveToPreviousExercise()
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                    .frame(width: 44, height: 44)
                                    .background(Color.white.opacity(0.2))
                                    .clipShape(Circle())
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            moveToNextExercise()
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                    }
                
                // Camera Setup UI
                } else if isCameraSetupExercise {
                    VStack(spacing: 16) {
                        Text(cameraSetupSelection == nil ? "Camera Setup" : "Camera Setup — \(cameraSetupSelection!.displayName)")
                            .font(.neueMontrealSemiBold(size: 20))
                            .foregroundColor(.textPrimary)
                            .padding(.top, 4)
                        
                        if cameraSetupSelection == nil {
                            VStack(spacing: 12) {
                                Text("Select One")
                                    .font(.neueMontrealRegular(size: 14))
                                    .foregroundColor(.textSecondary)
                                
                                cameraSetupSelectionView
                            }
                        }
                        
                        // Navigation buttons: Overview, Back, Test View / End Test, and Forward
                        HStack {
                        Button(action: {
                            showOverview = true
                        }) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        
                        if currentExerciseIndex > 0 || (isCameraSetupExercise && cameraSetupSelection != nil) {
                            Button(action: {
                                if isTestViewActive {
                                    endTestView()
                                }
                                if isCameraSetupExercise && cameraSetupSelection != nil {
                                    cameraSetupSelection = nil
                                    SpeechManager.shared.stopSpeaking()
                                    SpeechManager.shared.clearSpeechQueue()
                                } else if currentExerciseIndex > 0 {
                                    moveToPreviousExercise()
                                }
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                    .frame(width: 44, height: 44)
                                    .background(Color.white.opacity(0.2))
                                    .clipShape(Circle())
                            }
                        }
                        
                        if cameraSetupSelection != nil {
                            Button(action: {
                                if isTestViewActive {
                                    endTestView()
                                } else {
                                    startTestView()
                                }
                            }) {
                                Text(isTestViewActive ? "End Test" : "Test View")
                                    .font(.neueMontrealSemiBold(size: 14))
                                    .foregroundColor(.textPrimary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(isTestViewActive ? Color.red.opacity(0.6) : Color.primaryPurple.opacity(0.6))
                                    .clipShape(Capsule())
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            if isTestViewActive {
                                endTestView()
                            }
                            
                            if isShowingIntro {
                                introTimer?.invalidate()
                                introTimer = nil
                                isShowingIntro = false
                            } else {
                                moveToNextExercise()
                            }
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                    }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else if isRestExercise && previousExerciseName == "Close-Grip Bench Press" {
                    // Rest card after close-grip bench press - show coaching UI
                    // Reps/time display (rest duration)
                    Text(formatRepsTime(exercise))
                        .font(.neueMontrealRegular(size: 18))
                        .foregroundColor(.textSecondary)
                    
                    // Timer for rest period
                    if isTimeBasedExercise {
                        timeBasedTimerView
                    }
                    
                    // AI Coaching feedback section
                    coachingFeedbackView
                    
                    // Next exercise button and overview
                    HStack {
                        // Overview button
                        Button(action: {
                            showOverview = true
                        }) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        // Next exercise arrow button
                        Button(action: {
                            moveToNextExercise()
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                    }
                } else {
                    // Regular exercise UI
                    // Reps/time display
                    Text(formatRepsTime(exercise))
                        .font(.neueMontrealRegular(size: 18))
                        .foregroundColor(.textSecondary)
                    
                    // Display entered weight/reps values if available
                    if let data = exerciseData[currentExerciseIndex], (data.weight != nil || data.reps != nil) {
                        HStack(spacing: 12) {
                            if let weight = data.weight {
                                HStack(spacing: 4) {
                                    Text(String(format: "%.1f", weight))
                                        .font(.neueMontrealBold(size: 16))
                                        .foregroundColor(.textPrimary)
                                    Text("lbs")
                                        .font(.neueMontrealRegular(size: 14))
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            
                            if data.weight != nil && data.reps != nil {
                                Text("•")
                                    .font(.neueMontrealRegular(size: 14))
                                    .foregroundColor(.textSecondary)
                            }
                            
                            if let reps = data.reps {
                                HStack(spacing: 4) {
                                    Text("\(reps)")
                                        .font(.neueMontrealBold(size: 16))
                                        .foregroundColor(.textPrimary)
                                    Text("reps")
                                        .font(.neueMontrealRegular(size: 14))
                                        .foregroundColor(.textSecondary)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                    
                    // Bottom timer/progress
                    if isShowingIntro {
                        introBufferProgressView
                    } else if isTimeBasedExercise {
                        timeBasedTimerView
                    } else {
                        repBasedDisplayView
                    }
                    
                    // Next exercise button and overview
                    HStack {
                        // Overview button
                        Button(action: {
                            showOverview = true
                        }) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        // Next exercise arrow button
                        Button(action: {
                            moveToNextExercise()
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                    }
                }
            }
        }
        .padding(20)
        .padding(.bottom, isSlideUpTabExpanded && !isCameraSetupExercise ? 8 : 8) // Consistent padding
    }
    
    /// Action buttons grid displayed when the slide-up tab is expanded.
    ///
    /// Button visibility rules:
    /// - Rest exercises: Only Restart button
    /// - Warm-up/Cool-down exercises: Flag, Guide, and Restart buttons (Weight, Reps, History hidden)
    /// - Regular exercises: All buttons (Weight, Reps, Flag, Guide, History, Restart)
    @ViewBuilder
    private var actionButtonsGrid: some View {
        if isRestExercise {
            // Rest exercises: Only show Restart button
            VStack {
                ActionButton(
                    icon: "arrow.counterclockwise",
                    title: "Restart",
                    isDisabled: false,
                    action: {
                        restartCurrentExercise()
                    }
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        } else {
            let shouldHideWeightRepsHistory = isWarmUpExercise || isCoolDownExercise
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                if !shouldHideWeightRepsHistory {
                    ActionButton(
                        icon: "dumbbell.fill",
                        title: "Weight",
                        isDisabled: false,
                        action: { showWeightInput = true }
                    )
                    
                    ActionButton(
                        icon: "list.number",
                        title: "Reps",
                        isDisabled: false,
                        action: { showRepsInput = true }
                    )
                    
                    ActionButton(
                        icon: "clock.arrow.circlepath",
                        title: "History",
                        isDisabled: false,
                        action: { showHistory = true }
                    )
                }
                
                ActionButton(
                    icon: "flag.fill",
                    title: "Flag",
                    isDisabled: false,
                    action: { showFlagOptions = true }
                )
                
                ActionButton(
                    icon: "speaker.wave.2.fill",
                    title: "Guide",
                    isDisabled: false,
                    action: { playExerciseGuide() }
                )
                
                ActionButton(
                    icon: "arrow.counterclockwise",
                    title: "Restart",
                    isDisabled: false,
                    action: { restartCurrentExercise() }
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
    private var timeBasedTimerView: some View {
        VStack(spacing: 8) {
            HStack {
                Text(":\(String(format: "%02d", exerciseTimeRemaining))")
                    .font(.neueMontrealBold(size: 32))
                    .foregroundColor(.textPrimary)
                Spacer()
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 6)
                    
                    Rectangle()
                        .fill(Color.textPrimary)
                        .frame(
                            width: geometry.size.width * exerciseProgress,
                            height: 6
                        )
                        .animation(.easeInOut(duration: 1.0), value: exerciseProgress)
                }
            }
            .frame(height: 6)
        }
    }
    
    private var repBasedDisplayView: some View {
        VStack(spacing: 8) {
            if let exercise = currentExercise {
                Text(exercise.reps)
                    .font(.neueMontrealBold(size: 32))
                    .foregroundColor(.textPrimary)
            }
        }
    }
    
    private var introBufferProgressView: some View {
        VStack(spacing: 8) {
            HStack {
                Text(":\(String(format: "%02d", introTimeRemaining))")
                    .font(.neueMontrealBold(size: 32))
                    .foregroundColor(.textPrimary)
                Spacer()
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 6)
                    
                    Rectangle()
                        .fill(Color.textPrimary)
                        .frame(
                            width: geometry.size.width * introBufferProgress,
                            height: 6
                        )
                        .animation(.easeInOut(duration: 1.0), value: introBufferProgress)
                }
            }
            .frame(height: 6)
        }
    }
    
    private var introBufferProgress: Double {
        guard introDuration > 0 else { return 0 }
        let elapsed = introDuration - introTimeRemaining
        return min(1.0, Double(elapsed) / Double(introDuration))
    }
    
    private var exerciseProgress: Double {
        guard currentExerciseDuration > 0 else { return 0 }
        let elapsed = currentExerciseDuration - exerciseTimeRemaining
        return min(1.0, Double(elapsed) / Double(currentExerciseDuration))
    }
    
    // MARK: - AI Coaching Feedback View
    
    /// Displays AI coaching feedback during rest periods after close-grip bench press.
    /// Shows loading, success, or error states based on RestViewModel.
    @ViewBuilder
    private var coachingFeedbackView: some View {
        VStack(spacing: 12) {
            switch restViewModel.state {
            case .idle:
                // No coaching requested yet
                EmptyView()
                
            case .loading:
                // Loading state
                HStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .textPrimary))
                    Text("Generating coaching...")
                        .font(.neueMontrealRegular(size: 14))
                        .foregroundColor(.textSecondary)
                }
                .padding(.vertical, 8)
                
            case .success(let response):
                // Success state - show coaching card
                VStack(alignment: .leading, spacing: 12) {
                    // Headline
                    Text(response.headline)
                        .font(.neueMontrealBold(size: 18))
                        .foregroundColor(.textPrimary)
                    
                    // What you did well
                    if !response.did_well.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What you did well")
                                .font(.neueMontrealSemiBold(size: 12))
                                .foregroundColor(.textSecondary)
                            
                            ForEach(response.did_well, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.green)
                                    Text(item)
                                        .font(.neueMontrealRegular(size: 14))
                                        .foregroundColor(.textPrimary)
                                }
                            }
                        }
                    }
                    
                    // Focus for next set (only if there are items)
                    if !response.fix_next.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Focus for next set")
                                .font(.neueMontrealSemiBold(size: 12))
                                .foregroundColor(.textSecondary)
                            
                            ForEach(response.fix_next, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.orange)
                                    Text(item)
                                        .font(.neueMontrealRegular(size: 14))
                                        .foregroundColor(.textPrimary)
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                
            case .error(let errorMessage):
                // Error state with retry button
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        Text("Coaching unavailable")
                            .font(.neueMontrealRegular(size: 14))
                            .foregroundColor(.textSecondary)
                    }
                    
                    Text(errorMessage)
                        .font(.neueMontrealRegular(size: 10))
                        .foregroundColor(.textSecondary.opacity(0.7))
                        .lineLimit(2)
                    
                    Button(action: {
                        restViewModel.retry()
                    }) {
                        Text("Retry")
                            .font(.neueMontrealSemiBold(size: 14))
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.top, 8)
    }
    
    /// Whether the current exercise is in the Warm-up phase.
    private var isWarmUpExercise: Bool {
        currentExercise?.phase == "Warm-up"
    }
    
    /// Whether the current exercise is in the Cool Down phase.
    private var isCoolDownExercise: Bool {
        currentExercise?.phase == "Cool Down"
    }
    
    /// Whether the current exercise is a rest period.
    /// Rest exercises are identified by checking if the exercise name equals "Rest".
    private var isRestExercise: Bool {
        currentExercise?.name == "Rest"
    }
    
    /// Whether the current exercise is a camera setup exercise.
    /// Camera setup exercises are identified by checking if notes contains "CAMERA_SETUP".
    private var isCameraSetupExercise: Bool {
        guard let notes = currentExercise?.notes else { return false }
        return notes.hasPrefix("CAMERA_SETUP")
    }
    
    /// Whether the current exercise is an exercise selection step (for multi-exercise sections).
    private var isExerciseSelectionExercise: Bool {
        guard let notes = currentExercise?.notes else { return false }
        return notes.hasPrefix("EXERCISE_SELECTION")
    }
    
    /// Parses exercise options from the EXERCISE_SELECTION notes format.
    /// Notes format: "EXERCISE_SELECTION|Exercise A|Exercise B|..."
    private var exerciseSelectionOptions: [String] {
        guard let notes = currentExercise?.notes, notes.hasPrefix("EXERCISE_SELECTION") else { return [] }
        let components = notes.components(separatedBy: "|")
        return Array(components.dropFirst())
    }
    
    /// Display name for the camera setup title, using selected exercise or the exercise name.
    private var cameraSetupDisplayName: String {
        if let selected = selectedExerciseForSection {
            return selected
        }
        return currentExercise?.name ?? ""
    }
    
    /// Whether to show camera setup for the current exercise.
    /// Returns true if this is a camera setup exercise AND camera coaching is enabled for the target exercise.
    private var shouldShowCameraSetup: Bool {
        guard isCameraSetupExercise else { return false }
        guard let exerciseName = currentExercise?.name else { return false }
        return CameraCoachingPreferencesManager.shared.isCameraCoachingEnabled(for: exerciseName)
    }
    
    /// Parses camera setup instructions from exercise notes based on user's selection.
    ///
    /// Notes format: `"CAMERA_SETUP|RACK|instruction1|instruction2|...|FLOOR|instruction1|instruction2|..."`
    ///
    /// - Returns: Array of instruction strings for the selected setup type, or empty array if:
    ///   - Current exercise is not a camera setup exercise
    ///   - No selection has been made yet (`cameraSetupSelection == nil`)
    ///   - Section marker not found in notes
    private var cameraSetupInstructions: [String] {
        guard let notes = currentExercise?.notes,
              notes.hasPrefix("CAMERA_SETUP"),
              let selection = cameraSetupSelection else {
            return []
        }
        
        let components = notes.components(separatedBy: "|")
        let sectionMarker: String
        switch selection {
        case .rackAttachment:
            sectionMarker = "RACK"
        case .floor:
            sectionMarker = "FLOOR"
        case .tripod:
            sectionMarker = "TRIPOD"
        }
        
        guard let sectionIndex = components.firstIndex(of: sectionMarker) else {
            return []
        }
        
        // Extract instructions after the section marker until next section or end
        var instructions: [String] = []
        for i in (sectionIndex + 1)..<components.count {
            let component = components[i]
            if component == "RACK" || component == "FLOOR" || component == "TRIPOD" {
                break // Stop at next section marker
            }
            instructions.append(component)
        }
        
        return instructions
    }
    
    // MARK: - Helper Functions
    
    private func startWorkout() {
        workoutStartTime = Date()
        startElapsedTimeTimer()
        
        // Ensure slide-up tab is collapsed when starting
        isSlideUpTabExpanded = false
        dragOffset = 0
        
        // Create workout log in Firestore
        let userId = UserManager.shared.getUserId()
        WorkoutLogService.shared.createWorkoutLog(workoutName: workout.name, userId: userId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let logId):
                    currentWorkoutLogId = logId
                case .failure:
                    break
                }
            }
        }
        
        // Start with intro buffer
        if let exercise = currentExercise {
            let isCameraSetup = exercise.notes?.hasPrefix("CAMERA_SETUP") ?? false
            let isExerciseSelection = exercise.notes?.hasPrefix("EXERCISE_SELECTION") ?? false
            if isExerciseSelection {
                selectedExerciseForSection = nil
                showIntroBuffer(for: exercise)
            } else if isCameraSetup {
                cameraSetupSelection = nil
                if !CameraCoachingPreferencesManager.shared.isCameraCoachingEnabled(for: exercise.name) {
                    moveToNextExercise()
                } else {
                    showIntroBuffer(for: exercise)
                }
            } else {
                showIntroBuffer(for: exercise)
            }
        }
    }
    
    private func showIntroBuffer(for exercise: WorkoutExercise) {
        // Special handling for rest periods: use dedicated rest announcement logic
        if exercise.name == "Rest" {
            handleRestPeriod(for: exercise)
            return
        }
        
        // Capture the exercise index to verify we're still on this exercise when audio plays
        let exerciseIndexAtStart = currentExerciseIndex
        
        // Stop any ongoing speech from previous exercises and clear the queue
        SpeechManager.shared.stopSpeaking()
        SpeechManager.shared.clearSpeechQueue()
        
        // Skip intro buffer for exercise selection exercises - show selection UI immediately
        let isExerciseSelection = exercise.notes?.hasPrefix("EXERCISE_SELECTION") ?? false
        if isExerciseSelection {
            isShowingIntro = false
            selectedExerciseForSection = nil
            withAnimation {
                isSlideUpTabExpanded = false
                dragOffset = 0
            }
            let exerciseIndex = exerciseIndexAtStart
            if Thread.isMainThread {
                if currentExerciseIndex == exerciseIndex {
                    SpeechManager.shared.speakCoachingFeedback("Which exercise would you like coaching on?")
                }
            } else {
                DispatchQueue.main.async { [exerciseIndex] in
                    if self.currentExerciseIndex == exerciseIndex {
                        SpeechManager.shared.speakCoachingFeedback("Which exercise would you like coaching on?")
                    }
                }
            }
            return
        }
        
        // Skip intro buffer for camera setup exercises - show selection UI immediately
        let isCameraSetup = exercise.notes?.hasPrefix("CAMERA_SETUP") ?? false
        if isCameraSetup {
            isShowingIntro = false
            withAnimation {
                isSlideUpTabExpanded = false
                dragOffset = 0
            }
            let exerciseIndex = exerciseIndexAtStart
            if Thread.isMainThread {
                if currentExerciseIndex == exerciseIndex {
                    SpeechManager.shared.speakCoachingFeedback("Let's setup your camera for live coaching! Select the view you would like to use.")
                }
            } else {
                DispatchQueue.main.async { [exerciseIndex] in
                    if self.currentExerciseIndex == exerciseIndex {
                        SpeechManager.shared.speakCoachingFeedback("Let's setup your camera for live coaching! Select the view you would like to use.")
                    }
                }
            }
            return
        }
        
        isShowingIntro = true
        // Collapse slide-up tab when starting new exercise
        withAnimation {
            isSlideUpTabExpanded = false
            dragOffset = 0
        }
        
        // MARK: - Start Data Collection Immediately (Close-Grip Bench Press)
        // For close-grip bench press, start data collection immediately when exercise begins.
        // The intro buffer will still play, but it doesn't gate data collection.
        // This ensures form score and coaching work reliably even if user skips the buffer.
        if exercise.name == "Close-Grip Bench Press" {
            startExercise()
        }
        
        // Play spoken guide for current exercise only (verify we're still on this exercise)
        let guideText = "\(exercise.name), \(formatRepsTime(exercise))"
        let exerciseIndex = exerciseIndexAtStart
        if Thread.isMainThread {
            if currentExerciseIndex == exerciseIndex {
                SpeechManager.shared.speakCoachingFeedback(guideText)
            }
        } else {
            DispatchQueue.main.async { [exerciseIndex] in
                if self.currentExerciseIndex == exerciseIndex {
                    SpeechManager.shared.speakCoachingFeedback(guideText)
                }
            }
        }
        
        // Determine intro duration
        let duration: Int
        if exercise.name == "Close-Grip Bench Press" {
            duration = 30
        } else {
            duration = 7
        }
        
        introDuration = duration
        introTimeRemaining = duration
        
        // Start countdown timer for intro buffer.
        // Note: For close-grip bench press, data collection already started above.
        // The buffer plays independently and only controls UI visibility (isShowingIntro).
        introTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] timer in
            if !isPaused {
                if introTimeRemaining > 0 {
                    introTimeRemaining -= 1
                } else {
                    timer.invalidate()
                    isShowingIntro = false
                    // For non-close-grip exercises, start data collection when buffer completes.
                    // For close-grip bench press, data collection already started above.
                    if exercise.name != "Close-Grip Bench Press" {
                        startExercise()
                    }
                }
            }
        }
    }
    
    /// Configures pose detection and starts data collection for the current exercise.
    /// For close-grip bench press: configures exercise type, view type, camera session, and pose analysis.
    /// Called immediately when exercise starts (not gated by intro buffer) to ensure reliable data collection.
    private func startExercise() {
        guard let exercise = currentExercise else { return }
        
        // MARK: - Close-Grip Bench Press Configuration
        
        if exercise.name == "Close-Grip Bench Press" {
            // Configure exercise type for form analysis
            poseManager.trackedExerciseType = .closeGripBenchPress
            
            // Track set start time for duration calculation (used in AI coaching summary)
            closeGripBenchSetStartTime = Date()
            
            // Map camera setup selection to view type for view-specific form analysis adjustments
            if let cameraSetup = cameraSetupSelection {
                switch cameraSetup {
                case .rackAttachment: poseManager.benchPressViewType = .rack
                case .floor: poseManager.benchPressViewType = .floor
                case .tripod: poseManager.benchPressViewType = .tripod
                }
            } else {
                poseManager.benchPressViewType = .tripod // Default fallback
            }
            
            // Reset rep counting and form analysis state for the new set
            poseManager.resetRepCountingState()
            
            // MARK: - Camera Session Setup
            // Ensure camera session is set up and running before starting pose analysis
            if SharedCameraSessionManager.shared.getCaptureSession() == nil {
                SharedCameraSessionManager.shared.setupCameraSession()
            }
            
            // Start camera session if not running
            if let session = SharedCameraSessionManager.shared.getCaptureSession(), !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async {
                    session.startRunning()
                }
            }
            
            // MARK: - Switch to Workout Mode and Start Pose Analysis
            // Switch camera from setup mode to workout mode to enable frame processing.
            // Always switch to workout mode for close-grip bench press (following bodyweight squat pattern).
            // Start pose analysis to begin real-time form assessment.
            // Form score is calculated locally by OnDevicePoseManager - no OpenAI needed for real-time score.
            // Always switch to workout mode for close-grip bench press (similar to bodyweight squat pattern)
            // This ensures camera is in workout mode even if it was in setup mode from camera setup exercise
            SharedCameraSessionManager.shared.switchToWorkoutMode()
            SharedCameraSessionManager.shared.startPoseAnalysis()
            
            // MARK: - Start Form Score Timer
            // Reset smoothed score and rep tracking, start timer (1 Hz, updates on rep detection)
            smoothedFormScore = 0
            lastObservedRepCount = 0
            startFormScoreTimer()
            
        } else if poseManager.trackedExerciseType == .closeGripBenchPress {
            // Reset to bodyweight when moving away from close-grip bench press
            poseManager.trackedExerciseType = .bodyweight
            // Stop pose analysis when leaving close-grip bench press
            if SharedCameraSessionManager.shared.isAnalyzingPose {
                SharedCameraSessionManager.shared.stopPoseAnalysis()
            }
            // Stop form score timer
            stopFormScoreTimer()
            smoothedFormScore = 0
            lastObservedRepCount = 0
        }
        
        if isTimeBasedExercise {
            // Start countdown timer for time-based exercise
            exerciseTimeRemaining = currentExerciseDuration
            startExerciseTimer()
        } else {
            // For rep-based exercises, start reminder timer
            let estimatedTime = estimatedRepCompletionTime
            let reminderTime = estimatedTime + 20
            // Capture the exercise index and name to verify we're still on this exercise when timer fires
            let exerciseIndexAtTimerStart = currentExerciseIndex
            let exerciseNameAtTimerStart = exercise.name
            
            reminderTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(reminderTime), repeats: false) { [self] _ in
                // Only play reminder if we're still on the same exercise
                guard self.currentExerciseIndex == exerciseIndexAtTimerStart,
                      let currentExercise = self.currentExercise,
                      currentExercise.name == exerciseNameAtTimerStart else {
                    return
                }
                self.playRepReminder(for: exercise)
            }
        }
    }
    
    private func startExerciseTimer() {
        stopExerciseTimer()
        
        exerciseTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] timer in
            if !isPaused {
                if exerciseTimeRemaining > 0 {
                    exerciseTimeRemaining -= 1
                } else {
                    // Auto-advance for time-based exercises
                    stopExerciseTimer()
                    moveToNextExercise()
                }
            }
        }
    }
    
    private func stopExerciseTimer() {
        exerciseTimer?.invalidate()
        exerciseTimer = nil
    }
    
    private func startElapsedTimeTimer() {
        stopElapsedTimeTimer()
        
        elapsedTimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] timer in
            if !isPaused, let startTime = workoutStartTime {
                let totalTime = Date().timeIntervalSince(startTime)
                elapsedWorkoutTime = Int(totalTime) - totalPausedDuration
            }
        }
    }
    
    private func stopElapsedTimeTimer() {
        elapsedTimeTimer?.invalidate()
        elapsedTimeTimer = nil
    }
    
    private func stopAllTimers() {
        introTimer?.invalidate()
        introTimer = nil
        stopExerciseTimer()
        reminderTimer?.invalidate()
        reminderTimer = nil
        stopElapsedTimeTimer()
        stopFormScoreTimer()
        SpeechManager.shared.stopSpeaking()
    }
    
    // MARK: - Form Score Timer
    
    /// Starts the form score update timer (1 Hz) to check for rep completion.
    /// Form score only updates when a new rep is detected (repCount changes).
    private func startFormScoreTimer() {
        stopFormScoreTimer()
        
        // Reset rep tracking and form score state
        lastObservedRepCount = poseManager.repCount
        isTrackingActive = false
        repScores = []
        trackingPulseScale = 1.0
        
        
        formScoreUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
            checkForRepAndUpdateScore()
        }
    }
    
    /// Stops the form score update timer.
    private func stopFormScoreTimer() {
        formScoreUpdateTimer?.invalidate()
        formScoreUpdateTimer = nil
        isTrackingActive = false
        trackingPulseScale = 1.0
    }
    
    /// Checks if a new rep was detected and updates the form score accordingly.
    /// 
    /// Monitors rep count changes and updates form score using exponential moving average.
    /// 
    /// **State Management:**
    /// - **Before first score**: Enters "tracking" state when pose is detected (pulsing blue ring)
    /// - **On rep completion**: Calculates score from form analysis, applies moving average, snaps to new score
    /// - **After score exists**: Score persists regardless of pose detection state; tracking is permanently disabled
    /// 
    /// **Score Persistence:**
    /// - Once calculated, the score remains visible even when pose is temporarily lost
    /// - Only updates when a new rep is detected and completes
    /// - Uses `lastRepFormAnalysis` as fallback if `currentFormAnalysis` is unavailable
    ///   (ensures score calculation even if pose is lost immediately after rep completion)
    /// 
    /// **Moving Average:**
    /// - Uses exponential moving average (alpha = 0.55) for smoother set score transitions
    /// - First rep: score snaps directly (no averaging)
    /// - Subsequent reps: weighted average of new rep score and existing smoothed score
    private func checkForRepAndUpdateScore() {
        let currentRepCount = poseManager.repCount
        let poseDetected = poseManager.poseDetected
        let hasValidAnalysis = poseManager.currentFormAnalysis != nil
        
        // Update tracking state based on pose detection
        // Only enter tracking state if we don't have a score yet
        // Once a score exists, it persists and we don't show tracking anymore
        if poseDetected && hasValidAnalysis {
            // Pose detected - enter tracking state only if we don't have a score yet
            if smoothedFormScore == 0 && !isTrackingActive && currentRepCount == lastObservedRepCount {
                isTrackingActive = true
            }
        } else {
            // No pose detected - exit tracking state only if we don't have a score
            // If we have a score, keep it visible (don't reset tracking state)
            if isTrackingActive && smoothedFormScore == 0 {
                isTrackingActive = false
            }
        }
        
        // Check if a new rep was detected
        if currentRepCount > lastObservedRepCount {
            lastObservedRepCount = currentRepCount
            
            // Calculate score from form analysis
            // Use last rep's analysis if current analysis isn't available
            // This ensures we can calculate score even if pose is temporarily lost after rep completion
            let rawScore = Double(rawFormScore)
            
            if rawScore > 0 {
                // Apply exponential moving average for set score
                updateFormScoreWithMovingAverage(newRepScore: rawScore)
                
                // Exit tracking state after score update (score now persists)
                isTrackingActive = false
                
            }
        }
    }
    
    /// Updates the form score using exponential moving average (EMA).
    /// 
    /// **Formula:** `smoothedScore = alpha * newRepScore + (1 - alpha) * smoothedScore`
    /// 
    /// **Parameters:**
    /// - `alpha = 0.55`: Smoothing factor providing faster but still smooth transitions
    ///   - Higher alpha = more responsive to new scores
    ///   - Lower alpha = smoother but slower to reflect changes
    /// 
    /// **Behavior:**
    /// - First rep: Score snaps directly (no averaging)
    /// - Subsequent reps: Score updates with weighted average
    /// 
    /// **Result:** The smoothed score persists and remains visible until the next rep updates it.
    private func updateFormScoreWithMovingAverage(newRepScore: Double) {
        let alpha = 0.55
        
        if smoothedFormScore == 0 || repScores.isEmpty {
            // First rep: set score directly (snap)
            smoothedFormScore = newRepScore
        } else {
            // Apply exponential moving average
            smoothedFormScore = alpha * newRepScore + (1 - alpha) * smoothedFormScore
        }
        
        // Store rep score for reference
        repScores.append(newRepScore)
    }
    
    private func togglePause() {
        isPaused.toggle()
        
        if isPaused {
            // Record pause start time
            pauseStartTime = Date()
        } else {
            // Calculate pause duration and add to total
            if let pauseStart = pauseStartTime {
                let pauseDuration = Int(Date().timeIntervalSince(pauseStart))
                totalPausedDuration += pauseDuration
                pauseStartTime = nil
            }
        }
    }
    
    /// Moves to the next exercise in the workout.
    ///
    /// Handles:
    /// - Stopping current speech and clearing queue
    /// - Tracking previous exercise name for rest card coaching
    /// - Providing coaching feedback when transitioning from close-grip bench press to rest
    /// - Managing camera closure after 3rd set
    /// - Resetting exercise timers and state
    private func moveToNextExercise() {
        // Stop any ongoing speech and clear the queue
        SpeechManager.shared.stopSpeaking()
        SpeechManager.shared.clearSpeechQueue()
        
        // MARK: - Track Previous Exercise Name
        // Save the current exercise name before incrementing index (for rest card coaching detection)
        previousExerciseName = currentExercise?.name
        
        // Reset rest coaching state when leaving a rest exercise
        if isRestExercise {
            restViewModel.reset()
        }
        
        // MARK: - Close-Grip Bench Press: Coaching Feedback
        // Provide coaching feedback when transitioning from close-grip bench press to rest period.
        // IMPORTANT: Only provide coaching if the exercise was actually active (not during intro buffer).
        // The intro buffer period should not trigger coaching since no actual exercise was performed.
        if isCloseGripBenchPressExercise && !isShowingIntro {
            let nextIndex = currentExerciseIndex + 1
            
            if nextIndex < workout.exercises.count {
                let nextExercise = workout.exercises[nextIndex]
                
                // If next exercise is rest, provide coaching feedback
                if nextExercise.name.lowercased() == "rest" {
                    // Set flag to prevent rest announcement from interrupting coaching
                    justProvidedCoaching = true
                    provideCloseGripBenchPressCoachingFeedback()
                    completedCloseGripBenchPressSets += 1
                    
                    // Close camera after 3rd set if no more close-grip bench press exercises remain
                    if completedCloseGripBenchPressSets >= 3 {
                        let afterRestIndex = nextIndex + 1
                        let hasMoreCloseGripBench = afterRestIndex < workout.exercises.count &&
                            workout.exercises[afterRestIndex].name == "Close-Grip Bench Press"
                        
                        if !hasMoreCloseGripBench && !isCameraClosedAfterThirdSet {
                            SharedCameraSessionManager.shared.stopCamera()
                            isCameraClosedAfterThirdSet = true
                        }
                    }
                }
            }
        }
        
        // DON'T reset camera setup selection here - it's needed for the next exercise
        // Only reset it when entering a NEW camera setup exercise (handled below at line 1657)
        
        // Clean up current exercise timers
        introTimer?.invalidate()
        introTimer = nil
        stopExerciseTimer()
        reminderTimer?.invalidate()
        reminderTimer = nil
        
        // Reset set tracking for next exercise
        resetSetTracking()
        
        // Collapse slide-up tab when moving to next exercise
        withAnimation {
            isSlideUpTabExpanded = false
            dragOffset = 0
        }
        
        if currentExerciseIndex < workout.exercises.count - 1 {
            currentExerciseIndex += 1
            
            if let exercise = currentExercise {
                let isCameraSetup = exercise.notes?.hasPrefix("CAMERA_SETUP") ?? false
                let isExerciseSelection = exercise.notes?.hasPrefix("EXERCISE_SELECTION") ?? false
                
                if isExerciseSelection {
                    selectedExerciseForSection = nil
                } else if isCameraSetup {
                    cameraSetupSelection = nil
                    if !CameraCoachingPreferencesManager.shared.isCameraCoachingEnabled(for: exercise.name) {
                        moveToNextExercise()
                        return
                    }
                }
                showIntroBuffer(for: exercise)
            }
        } else {
            // Workout complete - end workout log
            if let logId = currentWorkoutLogId {
                WorkoutLogService.shared.endWorkoutLog(
                    workoutLogId: logId,
                    totalDuration: elapsedWorkoutTime,
                    totalPausedDuration: totalPausedDuration
                ) { result in
                    switch result {
                    case .success:
                        break
                    case .failure:
                        break
                    }
                }
            }
            dismiss()
        }
    }
    
    private func playRepReminder(for exercise: WorkoutExercise) {
        let repCount = extractRepCount(from: exercise.reps)
        // Clamp to pre-generated range (1-20)
        let clampedRepCount = min(max(repCount, 1), 20)
        let reminderText = "When you've completed \(clampedRepCount) reps, press the arrow to move on"
        SpeechManager.shared.speakCoachingFeedback(reminderText)
    }
    
    private func playExerciseGuide() {
        // Only play guide for the current exercise
        guard let exercise = currentExercise else { return }
        
        // Stop any ongoing speech and clear queue before playing new guide
        SpeechManager.shared.stopSpeaking()
        SpeechManager.shared.clearSpeechQueue()
        
        let guideText = "\(exercise.name), \(formatRepsTime(exercise))"
        SpeechManager.shared.speakCoachingFeedback(guideText)
    }
    
    private func restartCurrentExercise() {
        // Clean up timers
        introTimer?.invalidate()
        introTimer = nil
        stopExerciseTimer()
        reminderTimer?.invalidate()
        reminderTimer = nil
        isShowingIntro = false
        
        if let exercise = currentExercise {
            showIntroBuffer(for: exercise)
        }
    }
    
    // MARK: - Workout Logging Functions
    
    /// Saves a set log to Firestore for a specific exercise.
    /// 
    /// Called when weight/reps are saved from the overview menu. Tracks set numbers per exercise
    /// to ensure correct set numbering when logging sets for different exercises.
    ///
    /// - Parameters:
    ///   - exerciseIndex: Index of the exercise in the workout
    ///   - weight: Weight used (optional for bodyweight exercises)
    ///   - reps: Number of reps completed
    private func saveSetLogForExercise(exerciseIndex: Int, weight: Double?, reps: Int?) {
        // Ensure we're on the main thread and validate inputs
        guard Thread.isMainThread else {
            DispatchQueue.main.async(execute: {
                self.saveSetLogForExercise(exerciseIndex: exerciseIndex, weight: weight, reps: reps)
            })
            return
        }
        
        // Validate bounds
        guard exerciseIndex >= 0,
              exerciseIndex < workout.exercises.count else {
            return
        }
        
        guard let workoutLogId = currentWorkoutLogId else {
            return
        }
        
        guard let reps = reps else {
            return
        }
        
        // Safely access exercise
        let exercise = workout.exercises[exerciseIndex]
        let userId = UserManager.shared.getUserId()
        
        // Get or initialize set number for this exercise
        let setNumber = setNumbersPerExercise[exerciseIndex] ?? 1
        
        WorkoutLogService.shared.saveSetLog(
            workoutLogId: workoutLogId,
            userId: userId,
            exerciseName: exercise.name,
            setNumber: setNumber,
            weight: weight,
            reps: reps,
            flaggedPain: false,
            flaggedNotInControl: false
        ) { result in
            DispatchQueue.main.async(execute: {
                switch result {
                case .success(let setLogId):
                    // Increment set number for this exercise
                    self.setNumbersPerExercise[exerciseIndex] = (self.setNumbersPerExercise[exerciseIndex] ?? 1) + 1
                case .failure:
                    break
                }
            })
        }
    }
    
    /// Saves the current set log to Firestore when weight or reps are entered.
    ///
    /// Supports saving weight-only sets (when no reps are entered) or reps-only sets (for bodyweight exercises).
    /// Uses `currentSetWeight` as the primary source, falling back to `exerciseData` weight if needed.
    ///
    /// When a set is saved:
    /// - Creates ExerciseSetLog document in Firestore
    /// - Increments set number for next set
    /// - Resets current set data (weight, reps, flags) only if both weight and reps were saved
    private func saveSetLogIfComplete() {
        guard let workoutLogId = currentWorkoutLogId,
              let exercise = currentExercise else {
            return
        }
        
        // Save if we have either weight OR reps (or both)
        // Allow saving weight-only sets per user requirement
        guard currentSetWeight != nil || currentSetReps != nil else {
            return
        }
        
        // Use currentSetReps if available, otherwise nil (for weight-only saves)
        let reps = currentSetReps
        
        let userId = UserManager.shared.getUserId()
        
        // Use currentSetWeight if available, otherwise fall back to exerciseData weight
        // This ensures weight is preserved even if currentSetWeight gets reset
        let currentData = exerciseData[currentExerciseIndex] ?? (weight: nil, reps: nil)
        let weightToSave = currentSetWeight ?? currentData.weight
        WorkoutLogService.shared.saveSetLog(
                workoutLogId: workoutLogId,
                userId: userId,
                exerciseName: exercise.name,
                setNumber: currentSetNumber,
                weight: weightToSave,
                reps: reps,
                flaggedPain: currentSetPainFlag,
                flaggedNotInControl: currentSetNotInControlFlag
            ) { result in
                DispatchQueue.main.async(execute: {
                    switch result {
                    case .success(let setLogId):
                        // Increment set number for next set
                        currentSetNumber += 1
                        // Also update per-exercise tracking
                        setNumbersPerExercise[currentExerciseIndex] = currentSetNumber
                        // Reset current set data
                        // Only reset weight/reps if both were saved (if only one was saved, keep the other for next save)
                        if currentSetWeight != nil && currentSetReps != nil {
                            // Both were saved, reset both
                            currentSetWeight = nil
                            currentSetReps = nil
                        } else if currentSetWeight != nil {
                            // Only weight was saved, keep it for when reps are added
                            // Don't reset weight yet
                        } else if currentSetReps != nil {
                            // Only reps were saved, keep it for when weight is added
                            // Don't reset reps yet
                        }
                        currentSetPainFlag = false
                        currentSetNotInControlFlag = false
                    case .failure:
                        break
                    }
                })
            }
    }
    
    /// Updates flag states for the current set.
    /// Flags are saved to Firestore when the set is completed (when reps are logged).
    private func updateCurrentSetFlags(pain: Bool, notInControl: Bool) {
        currentSetPainFlag = pain
        currentSetNotInControlFlag = notInControl
    }
    
    /// Resets set tracking when moving to a new exercise.
    /// Called when advancing to the next exercise or jumping to a different exercise.
    private func resetSetTracking() {
        currentSetNumber = 1
        currentSetWeight = nil
        currentSetReps = nil
        currentSetPainFlag = false
        currentSetNotInControlFlag = false
    }
    
    /// Jumps to a specific exercise index (used from WorkoutProgressionView).
    ///
    /// - Parameter index: The exercise index to jump to (0-based)
    ///
    /// Stops current timers, resets set tracking, and starts the intro buffer for the new exercise.
    private func jumpToExercise(index: Int) {
        guard index >= 0 && index < workout.exercises.count else { return }
        
        // Stop any ongoing speech and clear the queue
        SpeechManager.shared.stopSpeaking()
        SpeechManager.shared.clearSpeechQueue()
        
        // MARK: - Camera Management: Reopen for Close-Grip Bench Press
        
        // Reopen camera if navigating back to close-grip bench press after it was closed
        let targetExercise = workout.exercises[index]
        let isTargetCloseGripBench = targetExercise.name == "Close-Grip Bench Press"
        let targetIsCameraSetup = targetExercise.notes?.hasPrefix("CAMERA_SETUP") ?? false
        
        if (isTargetCloseGripBench || targetIsCameraSetup) && isCameraClosedAfterThirdSet {
            reopenCameraForCloseGripBenchPress()
        }
        
        // Clean up current exercise timers
        introTimer?.invalidate()
        introTimer = nil
        stopExerciseTimer()
        reminderTimer?.invalidate()
        reminderTimer = nil
        
        // Reset set tracking for the new exercise
        resetSetTracking()
        
        // Collapse slide-up tab
        withAnimation {
            isSlideUpTabExpanded = false
            dragOffset = 0
        }
        
        // Jump to the specified exercise
        currentExerciseIndex = index
        
        if let exercise = currentExercise {
            showIntroBuffer(for: exercise)
        }
    }
    
    // MARK: - Camera Management
    
    /// Reopens the camera session when navigating back to close-grip bench press after it was closed.
    /// Called automatically from `jumpToExercise()` when the target exercise is close-grip bench press.
    private func reopenCameraForCloseGripBenchPress() {
        SharedCameraSessionManager.shared.setupCameraSession()
        
        if cameraSetupSelection != nil {
            SharedCameraSessionManager.shared.switchToWorkoutMode()
        }
        
        if let session = SharedCameraSessionManager.shared.getCaptureSession(), !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
        
        isCameraClosedAfterThirdSet = false
    }
    
    // MARK: - Close-Grip Bench Press Coaching Feedback
    
    /// Provides AI coaching feedback when transitioning from close-grip bench press to rest period.
    /// Provides coaching feedback for close-grip bench press sets.
    ///
    /// Uses the OpenAI Responses API with structured JSON output for consistent coaching.
    ///
    /// **Feedback Logic:**
    /// - **No reps detected (repCount == 0)**: Provides generic encouragement message
    /// - **Score ≥ 75**: Praise-only mode - no critical feedback, only positive reinforcement
    /// - **Score < 75**: Mixed mode - 1 positive item + 1-2 corrective cues
    ///
    /// Called automatically when user presses forward button to move from close-grip bench press to rest period.
    /// The coaching is fetched asynchronously via `RestViewModel`, which handles loading/success/error states
    /// and speaks the feedback automatically.
    private func provideCloseGripBenchPressCoachingFeedback() {
        // Handle case when no reps were detected - provide generic encouragement
        if poseManager.repCount == 0 {
            let messages = [
                "Let's get ready for the next set!",
                "Take your time and focus on the next set.",
                "Rest up and let's get after it!"
            ]
            let message = messages.randomElement() ?? "Let's get ready!"
            SpeechManager.shared.speakCoachingFeedback(message)
            return
        }
        
        // Get form analysis for the completed set
        guard let formAnalysis = poseManager.currentFormAnalysis else {
            SpeechManager.shared.speakCoachingFeedback("Good effort on that set. Keep focusing on your form.")
            return
        }
        
        // Create compact summary for OpenAI API
        let summary = CloseGripBenchSummary.from(
            formAnalysis: formAnalysis,
            setStartTime: closeGripBenchSetStartTime,
            setEndTime: Date()
        )
        
        // Fetch coaching via RestViewModel (handles loading/success/error states and speech)
        restViewModel.fetchCoaching(summary: summary)
    }
    
    // MARK: - Parsing Functions
    
    /// Parse time from reps string (":30" -> 30, "30s" -> 30, "1min" -> 60)
    private func parseTimeFromReps(_ reps: String) -> Int {
        if reps.hasPrefix(":") {
            // Format ":30"
            if let seconds = Int(reps.dropFirst()) {
                return seconds
            }
        } else if reps.lowercased().hasSuffix("s") {
            // Format "30s"
            if let seconds = Int(reps.dropLast()) {
                return seconds
            }
        } else if reps.lowercased().hasSuffix("min") {
            // Format "1min"
            if let minutes = Int(reps.dropLast(3)) {
                return minutes * 60
            }
        }
        return 30 // Default
    }
    
    /// Calculate estimated completion time for rep-based exercises
    private func calculateEstimatedRepTime(_ reps: String) -> Int {
        let repCount = extractRepCount(from: reps)
        // Estimate: 3.5 seconds per rep
        return Int(Double(repCount) * 3.5)
    }
    
    /// Extract rep count from reps string ("10-12" -> 11, "8" -> 8)
    private func extractRepCount(from reps: String) -> Int {
        if reps.contains("-") {
            // Range format "10-12"
            let components = reps.split(separator: "-")
            if components.count == 2,
               let min = Int(components[0].trimmingCharacters(in: .whitespaces)),
               let max = Int(components[1].trimmingCharacters(in: .whitespaces)) {
                return (min + max) / 2 // Midpoint
            }
        } else if let count = Int(reps) {
            // Single number "8"
            return count
        }
        return 10 // Default
    }
    
    /// Format reps/time string for display
    private func formatRepsTime(_ exercise: WorkoutExercise) -> String {
        if exercise.reps.hasPrefix(":") {
            // Time format ":30" -> "30 Seconds" (capital S to match speech phrase pattern)
            if let seconds = Int(exercise.reps.dropFirst()) {
                return "\(seconds) Seconds"
            }
        } else if exercise.reps.lowercased().hasSuffix("s") || exercise.reps.lowercased().hasSuffix("min") {
            // Time format "30s" or "1min"
            return exercise.reps
        } else {
            // Rep format "10-12" or "8"
            return "\(exercise.reps) reps"
        }
        return exercise.reps
    }
    
    /// Format time as MM:SS
    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    /// Format time remaining as "XX MIN LEFT"
    private func formatTimeRemaining(_ seconds: Int) -> String {
        let minutes = max(1, (seconds + 59) / 60) // Round up
        return "\(minutes) MIN"
    }
    
    /// Returns the SF Symbol icon name for a camera setup instruction based on its content.
    ///
    /// Maps instruction text to appropriate icons for visual clarity:
    /// - Mount: mount/rack → up arrow, angle → down-left arrow, center → square with line, etc.
    /// - Floor: phone placement → iPhone icon, distance → ruler, center → target, frame → rectangle
    ///
    /// - Parameters:
    ///   - instruction: The instruction text to match
    ///   - index: Instruction index (used for special sizing of 3rd bullet)
    /// - Returns: SF Symbol name for the icon
    private func iconForCameraSetupInstruction(_ instruction: String, index: Int) -> String {
        let lowercased = instruction.lowercased()
        
        // Rack Attachment setup icons
        if lowercased.contains("mount") || lowercased.contains("rack") || lowercased.contains("post") {
            return "arrow.up"
        } else if lowercased.contains("angle") || lowercased.contains("down") {
            return "arrow.down.left"
        } else if lowercased.contains("center") || lowercased.contains("frame") {
            return "square.split.2x1"
        } else if lowercased.contains("arm") || lowercased.contains("path") || lowercased.contains("visible") {
            return "arrow.up.and.down"
        } else if lowercased.contains("cropping") || lowercased.contains("avoid") {
            return "crop"
        }
        // Floor setup icons
        else if lowercased.contains("place phone") || lowercased.contains("phone on the floor") {
            return "iphone"
        } else if lowercased.contains("6") || lowercased.contains("8 ft") || lowercased.contains("back") {
            return "ruler"
        } else if lowercased.contains("center it on") || lowercased.contains("barbell") {
            return "target"
        } else if lowercased.contains("hands") || lowercased.contains("elbows") || lowercased.contains("fully in frame") {
            return "rectangle.inset.filled"
        }
        // Tripod setup icons
        else if lowercased.contains("bench") || lowercased.contains("front") {
            return "rectangle"
        } else if lowercased.contains("grip") || lowercased.contains("wrists") {
            return "hand.raised.fill"
        } else if lowercased.contains("height") || lowercased.contains("above") {
            return "arrow.up.and.down"
        }
        
        return "camera.fill" // Default fallback
    }
    
    /// Exercise selection view for multi-exercise sections (Superset 1, Superset 2, Finisher).
    /// Laid out similarly to the camera setup selection: tappable blocks with icon and exercise name.
    private var exerciseSelectionCardView: some View {
        let options = exerciseSelectionOptions
        return HStack(spacing: 16) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, exerciseName in
                VStack(spacing: 8) {
                    Button(action: {
                        selectedExerciseForSection = exerciseName
                        moveToNextExercise()
                    }) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 48, weight: .medium))
                            .foregroundColor(selectedExerciseForSection == exerciseName ? .primaryPurple : .textPrimary)
                            .frame(width: 100, height: 100)
                            .background(selectedExerciseForSection == exerciseName ? Color.primaryPurple.opacity(0.2) : Color.white.opacity(0.1))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedExerciseForSection == exerciseName ? Color.primaryPurple : Color.clear, lineWidth: 2)
                            )
                    }
                    Text(exerciseName)
                        .font(.neueMontrealRegular(size: 14))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
    
    /// Camera setup selection view displaying three setup options: Mount, Floor, and Tripod.
    ///
    /// When the user taps an option, the selection state is updated and audio instructions
    /// are played automatically via the `onChange` handler.
    ///
    /// - Returns: A view with three tappable image buttons
    private var cameraSetupSelectionView: some View {
        HStack(spacing: 16) {
            // Mount option
            VStack(spacing: 8) {
                Button(action: {
                    cameraSetupSelection = .rackAttachment
                    // Play audio immediately when selection is made
                    playCameraSetupInstructions(for: .rackAttachment)
                }) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundColor(.textPrimary)
                        .frame(width: 100, height: 100)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                }
                Text("Mount")
                    .font(.neueMontrealRegular(size: 14))
                    .foregroundColor(.textSecondary)
            }
            
            // Floor option
            VStack(spacing: 8) {
                Button(action: {
                    cameraSetupSelection = .floor
                    // Play audio immediately when selection is made
                    playCameraSetupInstructions(for: .floor)
                }) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundColor(.textPrimary)
                        .frame(width: 100, height: 100)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                }
                Text("Floor")
                    .font(.neueMontrealRegular(size: 14))
                    .foregroundColor(.textSecondary)
            }
            
            // Tripod option
            VStack(spacing: 8) {
                Button(action: {
                    cameraSetupSelection = .tripod
                    // Play audio immediately when selection is made
                    playCameraSetupInstructions(for: .tripod)
                }) {
                    Image(systemName: "camera.metering.multispot")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundColor(.textPrimary)
                        .frame(width: 100, height: 100)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                }
                Text("Tripod")
                    .font(.neueMontrealRegular(size: 14))
                    .foregroundColor(.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .onChange(of: cameraSetupSelection) { oldValue, newValue in
            // Play audio cues when user selects a camera setup option
            // Only play if we're transitioning from nil to a selection (not when resetting)
            if oldValue == nil && newValue != nil {
                let selectedType = newValue!
                // Play immediately - no delay needed
                playCameraSetupInstructions(for: selectedType)
            }
        }
    }
    
    /// Plays exact audio instructions for the selected camera setup type.
    ///
    /// This function is called when the user selects a camera setup option (Mount, Floor, or Tripod).
    /// It uses predefined exact text strings (not formatted from exercise notes) to ensure consistent
    /// audio playback. Stops any ongoing speech before playing new instructions.
    ///
    /// - Parameter setupType: The selected camera setup type (`.rackAttachment`, `.floor`, or `.tripod`)
    private func playCameraSetupInstructions(for setupType: CameraSetupType) {
        // Verify we're on a camera setup exercise
        guard let exercise = currentExercise,
              exercise.notes?.hasPrefix("CAMERA_SETUP") ?? false else {
            return
        }
        
        // Stop any ongoing speech and clear queue before playing new instructions
        SpeechManager.shared.stopSpeaking()
        SpeechManager.shared.clearSpeechQueue()
        
        // Use exact predefined text for each setup type (not formatted from notes)
        let exactText: String
        switch setupType {
        case .rackAttachment:
            exactText = "For a mount setup, mount your phone high up on one of the front rack posts, angled down toward the middle of the bar. Center the frame on the bar and your hands, not your face. Keep your full arm length and bar path visible. Try to avoid cropping at lockout or when you touch your chest."
        case .floor:
            exactText = "For a floor setup, place your phone on the floor, 4 to 6 feet from the bench, angled slightly upwards. Center it on the bar. Make sure to keep your hands, elbows, and bar path in frame."
        case .tripod:
            exactText = "For a tripod setup, place the tripod 2 to 3 feet in front of the bench, centered on the bar. Ensure that the tripod is at the same height as the racked bar or slightly higher. Angle the camera slightly down towards your grip. Ensure your hands, elbows, and bar path are in view."
        }
        
        // Play the exact instructions via SpeechManager
        SpeechManager.shared.speakCoachingFeedback(exactText)
    }
    
    /// Extracts camera setup instructions for a specific setup type from exercise notes.
    ///
    /// Parses the exercise notes which are formatted as:
    /// `"CAMERA_SETUP|RACK|instruction1|instruction2|...|FLOOR|instruction1|instruction2|...|TRIPOD|instruction1|instruction2|..."`
    ///
    /// - Parameter setupType: The camera setup type (`.rackAttachment`, `.floor`, or `.tripod`)
    /// - Returns: Array of instruction strings for the specified setup type, or `nil` if:
    ///   - Current exercise is not a camera setup exercise
    ///   - The specified section marker (RACK, FLOOR, or TRIPOD) is not found in the notes
    private func getCameraSetupInstructions(for setupType: CameraSetupType) -> [String]? {
        guard let notes = currentExercise?.notes, notes.hasPrefix("CAMERA_SETUP") else {
            return nil
        }
        
        let components = notes.components(separatedBy: "|")
        let sectionMarker: String
        switch setupType {
        case .rackAttachment:
            sectionMarker = "RACK"
        case .floor:
            sectionMarker = "FLOOR"
        case .tripod:
            sectionMarker = "TRIPOD"
        }
        
        guard let sectionIndex = components.firstIndex(of: sectionMarker) else {
            return nil
        }
        
        var instructions: [String] = []
        for i in (sectionIndex + 1)..<components.count {
            let component = components[i]
            if component == "RACK" || component == "FLOOR" || component == "TRIPOD" {
                break
            }
            instructions.append(component)
        }
        
        return instructions
    }
    
    /// Formats camera setup instructions into natural, flowing sentences.
    ///
    /// **Note:** This function is no longer used for audio playback. Audio now uses exact predefined
    /// text strings in `playCameraSetupInstructions(for:)`. This function is kept for potential
    /// future use or other display purposes.
    ///
    /// Converts terse instruction strings into natural-sounding speech by:
    /// - Adding proper articles ("the", "your", "a")
    /// - Expanding abbreviations ("6–8 ft" → "6 to 8 feet")
    /// - Converting imperative commands to natural phrases
    /// - Adding proper punctuation
    ///
    /// Example: "Mount high on front rack post" → "Mount your camera high on a front rack post."
    ///
    /// - Parameters:
    ///   - instructions: Array of raw instruction strings from exercise notes
    ///   - setupType: The camera setup type (used for introductory phrase)
    /// - Returns: Formatted sentence string ready for speech synthesis
    private func formatCameraSetupInstructionsAsSentences(_ instructions: [String], setupType: CameraSetupType) -> String {
        guard !instructions.isEmpty else { return "" }
        
        let setupTypeName: String
        switch setupType {
        case .rackAttachment:
            setupTypeName = "mount"
        case .floor:
            setupTypeName = "floor"
        case .tripod:
            setupTypeName = "tripod"
        }
        var sentences: [String] = []
        
        // Add introductory sentence
        sentences.append("For \(setupTypeName) setup,")
        
        // Format each instruction into a natural sentence
        for instruction in instructions {
            var sentence = instruction.trimmingCharacters(in: .whitespaces)
            
            // Capitalize first letter
            if !sentence.isEmpty {
                sentence = sentence.prefix(1).uppercased() + sentence.dropFirst()
            }
            
            // Convert to natural speech patterns
            if sentence.lowercased().hasPrefix("mount") {
                // "Mount high on front rack post" -> "Mount your camera high on a front rack post"
                sentence = sentence.replacingOccurrences(of: "^Mount", with: "Mount your camera", options: .regularExpression)
            } else if sentence.lowercased().hasPrefix("angle") {
                // "Angle down at middle of bar" -> "Angle it down at the middle of the bar"
                sentence = sentence.replacingOccurrences(of: "^Angle", with: "Angle it", options: .regularExpression)
                sentence = sentence.replacingOccurrences(of: " at middle", with: " at the middle", options: .regularExpression)
                sentence = sentence.replacingOccurrences(of: " of bar", with: " of the bar", options: .regularExpression)
            } else if sentence.lowercased().hasPrefix("center") {
                // "Center frame on bar + hands, not face" -> "Center the frame on the bar and your hands, not your face"
                if !sentence.lowercased().contains("center it") {
                    sentence = sentence.replacingOccurrences(of: "^Center", with: "Center the", options: .regularExpression)
                }
                sentence = sentence.replacingOccurrences(of: " on bar", with: " on the bar", options: .regularExpression)
            } else if sentence.lowercased().hasPrefix("keep") {
                // "Keep full arm length and bar path visible" -> "Keep your full arm length and bar path visible"
                sentence = sentence.replacingOccurrences(of: "^Keep", with: "Keep your", options: .regularExpression)
            } else if sentence.lowercased().hasPrefix("avoid") {
                // "Avoid cropping at lockout or chest touch" -> "Avoid cropping at lockout or when the bar touches your chest"
                sentence = sentence.replacingOccurrences(of: " chest touch", with: " when the bar touches your chest", options: .regularExpression)
            } else if sentence.lowercased().hasPrefix("place") {
                // "Place phone on the floor in front of the bench" -> "Place your phone on the floor in front of the bench"
                sentence = sentence.replacingOccurrences(of: "^Place phone", with: "Place your phone", options: .regularExpression)
            } else if sentence.lowercased().hasPrefix("set") {
                // "Set phone 6–8 ft back, angled Slightly upward" -> "Set the phone 6 to 8 feet back, angled slightly upward"
                sentence = sentence.replacingOccurrences(of: "^Set phone", with: "Set the phone", options: .regularExpression)
                sentence = sentence.replacingOccurrences(of: "6–8 ft", with: "6 to 8 feet", options: .regularExpression)
                sentence = sentence.replacingOccurrences(of: "Slightly", with: "slightly", options: .regularExpression)
            } else if sentence.lowercased().hasPrefix("center it") {
                // "Center it on the barbell" -> "Center it on the barbell" (already good)
            }
            
            // Replace "+" with "and" for better speech
            sentence = sentence.replacingOccurrences(of: " + ", with: " and ", options: .regularExpression)
            sentence = sentence.replacingOccurrences(of: "\\+", with: " and ", options: .regularExpression)
            
            // Add articles where needed for natural flow
            sentence = sentence.replacingOccurrences(of: " on bar", with: " on the bar", options: .regularExpression)
            sentence = sentence.replacingOccurrences(of: " on barbell", with: " on the barbell", options: .regularExpression)
            
            // Add period if not present
            if !sentence.hasSuffix(".") && !sentence.hasSuffix("!") && !sentence.hasSuffix("?") {
                sentence += "."
            }
            
            sentences.append(sentence)
        }
        
        // Join with proper spacing and flow
        return sentences.joined(separator: " ")
    }
    
    /// Moves to the previous exercise in the workout.
    private func moveToPreviousExercise() {
        
        // Stop any ongoing speech and clear the queue
        SpeechManager.shared.stopSpeaking()
        SpeechManager.shared.clearSpeechQueue()
        
        // Reset camera setup selection when leaving camera setup exercise
        if isCameraSetupExercise {
            cameraSetupSelection = nil
        }
        
        // Clean up current exercise timers
        introTimer?.invalidate()
        introTimer = nil
        stopExerciseTimer()
        reminderTimer?.invalidate()
        reminderTimer = nil
        
        // Reset set tracking for previous exercise
        resetSetTracking()
        
        // Collapse slide-up tab when moving to previous exercise
        withAnimation {
            isSlideUpTabExpanded = false
            dragOffset = 0
        }
        
        if currentExerciseIndex > 0 {
            currentExerciseIndex -= 1
            
            // Reset camera setup selection when entering camera setup exercise
            if let exercise = currentExercise {
                let isCameraSetup = exercise.notes?.hasPrefix("CAMERA_SETUP") ?? false
                if isCameraSetup {
                    cameraSetupSelection = nil
                }
                showIntroBuffer(for: exercise)
            }
        }
    }
    
    // MARK: - Test View Methods
    
    /// Starts the test view camera preview with segmentation overlay.
    ///
    /// Configures the segmentation processor for bench press with the appropriate view type
    /// based on the user's camera setup selection. The overlay provides real-time color-coded
    /// feedback (green/yellow/red) indicating camera positioning quality.
    private func startTestView() {
        guard let selection = cameraSetupSelection else { return }
        
        // Configure segmentation processor for bench press exercise
        testViewSegmentationProcessor.exerciseMode = .benchPress
        
        // Map camera setup selection to bench press view type
        switch selection {
        case .rackAttachment:
            testViewSegmentationProcessor.benchPressViewType = .rack
        case .floor:
            testViewSegmentationProcessor.benchPressViewType = .floor
        case .tripod:
            testViewSegmentationProcessor.benchPressViewType = .tripod
        }
        
        // Enable segmentation processing
        testViewSegmentationProcessor.setProcessingEnabled(true)
        
        // Ensure camera session is set up and running
        SharedCameraSessionManager.shared.setupCameraSession()
        SharedCameraSessionManager.shared.switchToSetupMode()
        
        // Activate test view with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            isTestViewActive = true
        }
    }
    
    /// Ends the test view camera preview.
    ///
    /// Stops segmentation processing but keeps the camera session running for future
    /// OpenAI coaching features. The video background is restored.
    private func endTestView() {
        // Stop segmentation processing (camera session remains active)
        testViewSegmentationProcessor.stopProcessing()
        
        // If on a close-grip bench press exercise, ensure we're in workout mode (not setup mode)
        // The camera was switched to setup mode for test view, but we need workout mode for form analysis
        if isCloseGripBenchPressExercise && SharedCameraSessionManager.shared.isInSetupMode {
            SharedCameraSessionManager.shared.switchToWorkoutMode()
            // Ensure pose analysis is running
            if !SharedCameraSessionManager.shared.isAnalyzingPose {
                SharedCameraSessionManager.shared.startPoseAnalysis()
            }
        }
        
        // Deactivate test view with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            isTestViewActive = false
        }
    }
    
    // MARK: - Rest Period Handling
    
    /// Handles rest period exercises with proper speech announcements.
    ///
    /// Rest periods skip the intro buffer and immediately start with a spoken announcement.
    /// Uses `generateRestAnnouncement()` to ensure duration matches the card exactly.
    ///
    /// **Speech Coordination:**
    /// If coaching was just provided (via `justProvidedCoaching` flag), the rest announcement
    /// is queued instead of interrupting the ongoing coaching speech. This ensures smooth
    /// audio flow: coaching finishes first, then rest announcement plays.
    private func handleRestPeriod(for exercise: WorkoutExercise) {
        // If coaching was just provided, queue the rest announcement instead of interrupting
        if justProvidedCoaching {
            // Reset the flag
            justProvidedCoaching = false
            
            // Queue rest announcement to play after coaching finishes
            // Parse rest duration from exercise.reps (format: ":45" -> 45 seconds)
            let restDuration = parseTimeFromReps(exercise.reps)
            let announcement = generateRestAnnouncement(duration: restDuration)
            
            // Queue the rest announcement (will play after current speech)
            SpeechManager.shared.speakCoachingFeedback(announcement)
        } else {
            // Normal rest period (not after close-grip bench) - stop and speak immediately
            SpeechManager.shared.stopSpeaking()
            SpeechManager.shared.clearSpeechQueue()
            
            // Parse rest duration from exercise.reps (format: ":45" -> 45 seconds)
            let restDuration = parseTimeFromReps(exercise.reps)
            let announcement = generateRestAnnouncement(duration: restDuration)
            SpeechManager.shared.speakCoachingFeedback(announcement)
        }
        
        // No intro buffer for rest periods
        isShowingIntro = false
        
        // Collapse slide-up tab
        withAnimation {
            isSlideUpTabExpanded = false
            dragOffset = 0
        }
        
        // Start rest timer immediately (no buffer)
        startExercise()
    }
    
    /// Generate rest period announcement with weighted random variations.
    ///
    /// - 70% chance: Basic announcement ("Rest, X Seconds")
    /// - 30% chance: Motivational variation (with "You deserve it!", "Stretch out", etc.)
    ///
    /// Duration is rounded to nearest 5 seconds to match pre-generated audio files
    /// (phrases are generated in 5-second increments: 5, 10, 15, 20, 25, 30, 35, 40, 45, etc.)
    private func generateRestAnnouncement(duration: Int) -> String {
        // Clamp duration to valid range
        let clampedDuration = min(max(duration, 5), 300)
        
        // Round to nearest 5 seconds (matching phrase generation in 5-second increments)
        // This ensures we match pre-generated audio files while being closer to actual duration
        let roundedDuration = ((clampedDuration + 2) / 5) * 5
        
        let basicAnnouncement = "Rest, \(roundedDuration) Seconds"
        
        // 70% chance of basic announcement, 30% chance of variation
        let useVariation = Int.random(in: 1...100) <= 30
        
        guard useVariation else {
            return basicAnnouncement
        }
        
        // Variations (each has equal chance when variation is selected)
        let variations = [
            "\(basicAnnouncement). You deserve it!",
            "\(basicAnnouncement). Stretch out a bit.",
            "\(basicAnnouncement). Take a drink of water if you're thirsty.",
            "\(basicAnnouncement). Recover and then let's get this next set!"
        ]
        
        return variations.randomElement() ?? basicAnnouncement
    }
}

// MARK: - Action Button

private struct ActionButton: View {
    let icon: String
    let title: String
    let isDisabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(isDisabled ? .textSecondary.opacity(0.5) : .textPrimary)
                
                Text(title)
                    .font(.neueMontrealSemiBold(size: 12))
                    .foregroundColor(isDisabled ? .textSecondary.opacity(0.5) : .textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(isDisabled ? Color.white.opacity(0.05) : Color.white.opacity(0.1))
            .cornerRadius(12)
        }
        .disabled(isDisabled)
    }
}

// MARK: - Test View Camera Preview

/// SwiftUI wrapper for the camera preview used in test view mode.
///
/// Displays the front camera feed and connects it to the segmentation processor
/// for real-time quality overlay generation.
struct TestViewCameraPreview: UIViewRepresentable {
    @ObservedObject var processor: SegmentationProcessor
    
    func makeUIView(context: Context) -> TestViewCameraPreviewUIView {
        TestViewCameraPreviewUIView(processor: processor)
    }
    
    func updateUIView(_ uiView: TestViewCameraPreviewUIView, context: Context) {
        uiView.updateProcessor(processor)
    }
}

/// UIKit view that manages the camera preview layer and segmentation processing for test view.
///
/// Handles:
/// - Camera preview layer setup and display
/// - Video output delegate binding for segmentation processing
/// - Portrait orientation configuration
final class TestViewCameraPreviewUIView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var processor: SegmentationProcessor?
    private var videoDelegate: TestViewVideoDelegate?
    private var processingQueue: DispatchQueue?
    
    init(processor: SegmentationProcessor) {
        self.processor = processor
        super.init(frame: .zero)
        setup()
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        setupPreviewLayer()
    }
    
    private func setupPreviewLayer() {
        guard let session = SharedCameraSessionManager.shared.getCaptureSession() else {
            // Retry if session isn't ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.setupPreviewLayer()
            }
            return
        }
        
        // Create preview layer
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.automaticallyAdjustsVideoMirroring = false
        layer.connection?.isVideoMirrored = true
        previewLayer = layer
        self.layer.addSublayer(layer)
        layer.frame = bounds
        
        // Bind video delegate for segmentation
        bindVideoDelegate()
        
        // Start session if not running
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
    }
    
    /// Binds the video output delegate to process frames through the segmentation processor.
    ///
    /// Configures the video connection for portrait orientation and sets up the delegate
    /// to process each camera frame for segmentation overlay generation.
    private func bindVideoDelegate() {
        guard let videoOutput = SharedCameraSessionManager.shared.getVideoDataOutput() else { return }
        
        // Create processing queue if needed
        if processingQueue == nil {
            processingQueue = DispatchQueue(label: "testViewSegmentationQueue")
        }
        
        // Create or update video delegate
        if videoDelegate == nil {
            videoDelegate = TestViewVideoDelegate(processor: processor)
        } else {
            videoDelegate?.processor = processor
        }
        
        // Set delegate to receive camera frames
        videoOutput.setSampleBufferDelegate(videoDelegate, queue: processingQueue)
        
        // Configure video connection for portrait orientation
        if let connection = videoOutput.connection(with: .video) {
            if #available(iOS 17.0, *) {
                connection.videoRotationAngle = 90.0
            } else {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
    
    func updateProcessor(_ processor: SegmentationProcessor) {
        self.processor = processor
        videoDelegate?.processor = processor
    }
    
    deinit {
        // Don't nil out the delegate - let the SharedCameraSessionManager manage it
    }
}

/// Video output delegate that processes camera frames for segmentation overlay.
///
/// Receives each camera frame and passes it to the segmentation processor with
/// appropriate transformations (mirrored for front camera, rotated for portrait orientation).
private final class TestViewVideoDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var processor: SegmentationProcessor?
    
    init(processor: SegmentationProcessor?) {
        self.processor = processor
        super.init()
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Process frame with mirroring (front camera) and rotation (portrait orientation)
        processor?.process(sampleBuffer: sampleBuffer, mirrored: true, rotated: true)
    }
}


#Preview {
    WorkoutActiveView(workout: WorkoutLibrary.pythonWrangler)
        .preferredColorScheme(.dark)
}
