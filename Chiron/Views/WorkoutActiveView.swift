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
    
    /// Workout log service (singleton) - accessed via WorkoutLogService.shared
    
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
        let phases = Array(exercisesByPhase.keys)
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
    
    var body: some View {
        ZStack {
            // Video background
            if let videoName = workout.videoName {
                CroppedDemoVideoHeader(videoName: videoName)
                    .ignoresSafeArea()
            } else {
                Color.background.ignoresSafeArea()
            }
            
            // Main content overlay
            VStack(spacing: 0) {
                // Top navigation bar
                topNavigationBar
                
                Spacer()
                
                // Bottom exercise card
                bottomExerciseCard
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
        HStack {
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
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
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
    
    /// Overall workout progress (0.0 to 1.0)
    private var overallProgress: Double {
        guard estimatedTotalDuration > 0 else { return 0 }
        return min(1.0, Double(elapsedWorkoutTime) / Double(estimatedTotalDuration))
    }
    
    
    // MARK: - Bottom Exercise Card
    
    private var bottomExerciseCard: some View {
        VStack(spacing: 0) {
            // Slide-up indicator (always visible)
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
            
            // Exercise info card (always visible)
            exerciseInfoCardContent
            
            // Action buttons (shown when expanded)
            if isSlideUpTabExpanded {
                actionButtonsGrid
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
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
        .ignoresSafeArea(edges: .bottom)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
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
            if !isDragging {
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
                        
                        if let weight = data.weight, let reps = data.reps {
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
        .padding(20)
        .padding(.bottom, isSlideUpTabExpanded ? 8 : 8) // Consistent padding
    }
    
    /// Action buttons grid displayed when the slide-up tab is expanded.
    ///
    /// - For rest exercises: Shows only the Restart button (centered)
    /// - For regular exercises: Shows all 6 buttons (Weight, Reps, Flag, Guide, History, Restart) in a 3-column grid
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
            // Regular exercises: Show all buttons in a 3-column grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                // Weight button
                ActionButton(
                    icon: "dumbbell.fill",
                    title: "Weight",
                    isDisabled: isWarmUpExercise,
                    action: {
                        showWeightInput = true
                    }
                )
                
                // Reps button
                ActionButton(
                    icon: "list.number",
                    title: "Reps",
                    isDisabled: false,
                    action: {
                        showRepsInput = true
                    }
                )
                
                // Flag button
                ActionButton(
                    icon: "flag.fill",
                    title: "Flag",
                    isDisabled: false,
                    action: {
                        showFlagOptions = true
                    }
                )
                
                // Guide button
                ActionButton(
                    icon: "speaker.wave.2.fill",
                    title: "Guide",
                    isDisabled: false,
                    action: {
                        playExerciseGuide()
                    }
                )
                
                // History button
                ActionButton(
                    icon: "clock.arrow.circlepath",
                    title: "History",
                    isDisabled: false,
                    action: {
                        showHistory = true
                    }
                )
                
                // Restart button
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
    
    
    private var isWarmUpExercise: Bool {
        currentExercise?.phase == "Warm-up"
    }
    
    /// Whether the current exercise is a rest period.
    /// Rest exercises are identified by checking if the exercise name equals "Rest".
    private var isRestExercise: Bool {
        currentExercise?.name == "Rest"
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
                    print("✅ Workout log created: \(logId)")
                case .failure(let error):
                    print("❌ Failed to create workout log: \(error.localizedDescription)")
                }
            }
        }
        
        // Start with intro buffer
        if let exercise = currentExercise {
            showIntroBuffer(for: exercise)
        }
    }
    
    private func showIntroBuffer(for exercise: WorkoutExercise) {
        // Stop any ongoing speech from previous exercises and clear the queue
        SpeechManager.shared.stopSpeaking()
        SpeechManager.shared.clearSpeechQueue()
        
        isShowingIntro = true
        // Collapse slide-up tab when starting new exercise
        withAnimation {
            isSlideUpTabExpanded = false
            dragOffset = 0
        }
        
        // Play spoken guide for current exercise only
        let guideText = "\(exercise.name), \(formatRepsTime(exercise))"
        SpeechManager.shared.speakCoachingFeedback(guideText)
        
        // Determine intro duration
        let duration: Int
        if exercise.name == "Close-Grip Bench Press" {
            duration = 30
        } else {
            duration = 7
        }
        
        introDuration = duration
        introTimeRemaining = duration
        
        // Start countdown timer for intro buffer
        introTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] timer in
            if !isPaused {
                if introTimeRemaining > 0 {
                    introTimeRemaining -= 1
                } else {
                    timer.invalidate()
                    isShowingIntro = false
                    startExercise()
                }
            }
        }
    }
    
    private func startExercise() {
        guard let exercise = currentExercise else { return }
        
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
        SpeechManager.shared.stopSpeaking()
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
    
    private func moveToNextExercise() {
        // Stop any ongoing speech and clear the queue
        SpeechManager.shared.stopSpeaking()
        SpeechManager.shared.clearSpeechQueue()
        
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
                        print("✅ Workout log ended: \(logId)")
                    case .failure(let error):
                        print("❌ Failed to end workout log: \(error.localizedDescription)")
                    }
                }
            }
            dismiss()
        }
    }
    
    private func playRepReminder(for exercise: WorkoutExercise) {
        let repCount = extractRepCount(from: exercise.reps)
        let reminderText = "When you've completed \(repCount) reps, press the arrow to move on"
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
                    print("✅ Set log saved from overview: \(setLogId)")
                    // Increment set number for this exercise
                    self.setNumbersPerExercise[exerciseIndex] = (self.setNumbersPerExercise[exerciseIndex] ?? 1) + 1
                case .failure(let error):
                    print("❌ Failed to save set log from overview: \(error.localizedDescription)")
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
                        print("✅ Set log saved: \(setLogId)")
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
                    case .failure(let error):
                        print("❌ Failed to save set log: \(error.localizedDescription)")
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
            // Time format ":30" -> "30 seconds"
            if let seconds = Int(exercise.reps.dropFirst()) {
                return "\(seconds) seconds"
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

#Preview {
    WorkoutActiveView(workout: WorkoutLibrary.pythonWrangler)
        .preferredColorScheme(.dark)
}
