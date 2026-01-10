//
//  WorkoutIntroView.swift
//  Chiron
//
//  Full-screen intro view for a predetermined workout.
//  Displays workout information with video background and navigation options.
//  Transitions seamlessly to active workout view when Start is pressed.
//
//  Workout Logging:
//  - Creates WorkoutLog in Firestore when workout starts
//  - Logs ExerciseSetLog entries when user logs weight/reps for sets
//  - Ends WorkoutLog when workout completes
//  - Provides buttons for Weight, Reps, Flag, Guide, History, and Restart
//

import SwiftUI
import AVKit
import AVFoundation
import AudioToolbox
import UIKit

/// Full-screen intro view for a predetermined workout that seamlessly transitions to active workout.
///
/// Features:
/// - Video background (if available) that continues playing during transition
/// - Intro UI: workout info, description, duration, and equipment list
/// - Active UI: exercise progression with timers, progress bars, and interactive controls
/// - Smooth state-based transitions between intro and active states
/// - Bottom slide-up tab with action buttons (Weight, Reps, Flag, Guide, History, Restart)
/// - Workout logging to Firebase Firestore
struct WorkoutIntroView: View {
    let workout: PredeterminedWorkout
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Intro State
    
    /// Controls presentation of the workout progression (list) sheet
    @State private var showProgression = false
    
    /// Controls presentation of the workout settings sheet
    @State private var showSettings = false
    
    /// Whether workout is active (shows active UI instead of intro UI)
    @State private var isWorkoutActive: Bool = false
    
    // MARK: - Active Workout State
    
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
    
    /// Whether forward arrow should glow (when audio cues user)
    @State private var shouldGlowForwardArrow: Bool = false
    
    /// Whether 30-second reminder has been spoken for current exercise
    @State private var hasSpoken30SecondReminder: Bool = false
    
    /// Whether 10-second reminder has been spoken for current exercise
    @State private var hasSpoken10SecondReminder: Bool = false
    
    // MARK: - Workout Logging State
    
    /// Sheet presentation states
    @State private var showWeightInput: Bool = false
    @State private var showRepsInput: Bool = false
    @State private var showFlagOptions: Bool = false
    @State private var showHistory: Bool = false
    
    /// Set tracking: current set number resets to 1 when moving to a new exercise
    @State private var currentSetNumber: Int = 1
    
    /// Firestore document ID for the current workout session
    @State private var currentWorkoutLogId: String?
    
    /// Current set data (reset when set is saved or exercise changes)
    @State private var currentSetWeight: Double?
    @State private var currentSetReps: Int?
    @State private var currentSetPainFlag: Bool = false
    @State private var currentSetNotInControlFlag: Bool = false
    
    /// Workout log service (singleton)
    @StateObject private var workoutLogService = WorkoutLogService.shared
    
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
    
    /// Whether current exercise is a rest period
    private var isRestPeriod: Bool {
        return currentExercise?.name == "Rest"
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
            // Background video (persists across state changes)
            if let videoName = workout.videoName {
                CroppedDemoVideoHeader(videoName: videoName)
                    .ignoresSafeArea()
            } else {
                Color.background.ignoresSafeArea()
            }
            
            // Gradient overlay for readability (only shown in intro state)
            if !isWorkoutActive {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.2),
                        Color.black.opacity(0.4),
                        Color.black.opacity(0.6)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
            
            // Conditional UI based on state
            if isWorkoutActive {
                // Active workout UI
                activeWorkoutContent
                    .transition(.opacity)
            } else {
                // Intro UI
                introContent
                    .transition(.opacity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
        .onAppear {
            if isWorkoutActive {
                startWorkout()
            }
        }
        .onDisappear {
            if isWorkoutActive {
                stopAllTimers()
            }
        }
        .alert("Leave Workout?", isPresented: $showExitConfirmation) {
            Button("Stay", role: .cancel) { }
            Button("Leave", role: .destructive) {
                // Return to intro state or dismiss
                withAnimation(.easeInOut(duration: 0.3)) {
                    isWorkoutActive = false
                    stopAllTimers()
                }
            }
        } message: {
            Text("Are you sure you want to leave the workout?")
        }
        .sheet(isPresented: $showProgression) {
            WorkoutProgressionView(
                workout: workout,
                onJumpToExercise: { index in
                    // Switch to active workout if not already active
                    if !isWorkoutActive {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isWorkoutActive = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            jumpToExercise(index: index)
                        }
                    } else {
                        jumpToExercise(index: index)
                    }
                },
                currentExerciseIndex: isWorkoutActive ? currentExerciseIndex : nil
            )
        }
        .sheet(isPresented: $showSettings) {
            WorkoutSettingsView()
        }
        .sheet(isPresented: $showOverview) {
            WorkoutProgressionView(
                workout: workout,
                onJumpToExercise: { index in
                    // Switch to active workout if not already active
                    if !isWorkoutActive {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isWorkoutActive = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            jumpToExercise(index: index)
                        }
                    } else {
                        jumpToExercise(index: index)
                    }
                },
                currentExerciseIndex: isWorkoutActive ? currentExerciseIndex : nil
            )
        }
        .sheet(isPresented: $showWeightInput) {
            WeightInputSheet(
                isPresented: $showWeightInput,
                weight: $currentSetWeight,
                onSave: { weight in
                    currentSetWeight = weight
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
    
    // MARK: - Intro Content
    
    private var introContent: some View {
        VStack {
            // Top navigation bar
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                
                Spacer()
                
                // Settings button
                Button(action: {
                    showSettings = true
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            
            Spacer()
            
            // Content overlay
            VStack(alignment: .leading, spacing: 0) {
                // Title and subtitle
                VStack(alignment: .leading, spacing: 8) {
                    Text(workout.name)
                        .font(.neueMontrealBold(size: 36))
                        .foregroundColor(.textPrimary)
                        .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 2)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 14))
                        Text(workout.description)
                            .font(.neueMontrealRegular(size: 16))
                    }
                    .foregroundColor(.textPrimary)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                
                // Info card overlay
                VStack(alignment: .leading, spacing: 12) {
                    // Duration
                    Text("\(workout.duration) min")
                        .font(.neueMontrealBold(size: 18))
                        .foregroundColor(.textPrimary)
                    
                    // Equipment list
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(workout.equipment, id: \.self) { item in
                            Text(item)
                                .font(.neueMontrealRegular(size: 14))
                                .foregroundColor(.textPrimary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.6))
                        .background(.ultraThinMaterial)
                )
                .cornerRadius(16)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                
                // Bottom action bar
                HStack(spacing: 16) {
                    // List button
                    Button(action: {
                        showProgression = true
                    }) {
                        Image(systemName: "list.bullet")
                            .font(.neueMontrealSemiBold(size: 18))
                            .foregroundColor(.textPrimary)
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    
                    // Start button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isWorkoutActive = true
                        }
                        // Start workout after animation begins
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            startWorkout()
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.neueMontrealBold(size: 16))
                            Text("Start")
                                .font(.neueMontrealSemiBold(size: 17))
                        }
                        .foregroundColor(.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.primaryPurple)
                        .cornerRadius(28)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }
    
    // MARK: - Active Workout Content
    
    private var activeWorkoutContent: some View {
        VStack(spacing: 0) {
            // Top navigation bar
            topNavigationBar
            
            Spacer()
            
            // Bottom exercise card
            bottomExerciseCard
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
                Text(formatExerciseNameWithSide(exercise))
                    .font(.neueMontrealBold(size: 24))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                
                // Reps/time display
                Text(formatRepsTime(exercise))
                    .font(.neueMontrealRegular(size: 18))
                    .foregroundColor(.textSecondary)
                
                // Bottom timer/progress
                if isShowingIntro {
                    introBufferProgressView
                } else if isTimeBasedExercise {
                    timeBasedTimerView
                } else {
                    repBasedDisplayView
                }
                
                // Navigation buttons: Overview, Back, and Forward
                HStack {
                    // Overview button (leftmost)
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
                    
                    // Back arrow button (only show when not on first exercise)
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
                    
                    // Next exercise arrow button with purple glow when cued
                    Button(action: {
                        shouldGlowForwardArrow = false
                        
                        // If in intro buffer, skip buffer and start current exercise
                        if isShowingIntro {
                            // Stop intro timer
                            introTimer?.invalidate()
                            introTimer = nil
                            
                            // End intro buffer and start exercise
                            isShowingIntro = false
                            playBeepTone(frequency: 800.0, duration: 0.15) // Higher pitch for start
                            triggerStartHaptic()
                            startExercise()
                        } else {
                            // Normal behavior: move to next exercise
                            moveToNextExercise()
                        }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(shouldGlowForwardArrow ? Color.primaryPurple : Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .shadow(
                        color: shouldGlowForwardArrow ? Color.primaryPurple.opacity(1.0) : Color.clear,
                        radius: shouldGlowForwardArrow ? 20 : 0
                    )
                    .animation(
                        shouldGlowForwardArrow ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                        value: shouldGlowForwardArrow
                    )
                }
            }
        }
        .padding(20)
        .padding(.bottom, isSlideUpTabExpanded ? 8 : 8) // Consistent padding
    }
    
    private var actionButtonsGrid: some View {
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
        // Empty space for rep-based exercises (no progress bar or rep text)
        VStack(spacing: 8) {
            Spacer()
                .frame(height: 6) // Match the height of the progress bar area
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
    
    // MARK: - Helper Functions
    
    /// Trigger haptic feedback for exercise start
    private func triggerStartHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }
    
    /// Trigger haptic feedback for exercise end
    private func triggerEndHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
    }
    
    /// Generate and play a beep tone programmatically
    private func playBeepTone(frequency: Double, duration: Double = 0.15) {
        DispatchQueue.main.async {
            self.configureAudioSession()
            self.generateAndPlayTone(frequency: frequency, duration: duration)
        }
    }
    
    /// Configure audio session for playback
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            print("Failed to activate audio session: \(error)")
        }
    }
    
    /// Generate sine wave audio buffer and play it
    private func generateAndPlayTone(frequency: Double, duration: Double) {
        let sampleRate: Double = 44100.0
        let sampleCount = Int(sampleRate * duration)
        
        // Generate audio samples
        var audioSamples = [Float]()
        for i in 0..<sampleCount {
            let time = Double(i) / sampleRate
            let sample = sin(2.0 * Double.pi * frequency * time)
            audioSamples.append(Float(sample * 0.3))
        }
        
        // Create audio format
        let formatOptions: AVAudioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        
        // Create and fill PCM buffer
        guard let buffer = createAudioBuffer(format: formatOptions, samples: audioSamples, count: sampleCount) else {
            return
        }
        
        // Play the tone
        playAudioBuffer(buffer, format: formatOptions, duration: duration)
    }
    
    /// Create PCM buffer from audio samples
    private func createAudioBuffer(format: AVAudioFormat, samples: [Float], count: Int) -> AVAudioPCMBuffer? {
        let frameCapacity = AVAudioFrameCount(count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }
        
        buffer.frameLength = frameCapacity
        
        guard let channelData = buffer.floatChannelData else {
            return nil
        }
        
        for i in 0..<count {
            channelData[0][i] = samples[i]
        }
        
        return buffer
    }
    
    /// Play the audio buffer using AVAudioEngine
    private func playAudioBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat, duration: Double) {
        let audioEngine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
        
        do {
            try audioEngine.start()
            
            let completionHandler: AVAudioNodeCompletionHandler = {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
                    audioEngine.stop()
                }
            }
            
            playerNode.scheduleBuffer(buffer, completionHandler: completionHandler)
            playerNode.play()
        } catch {
            print("Failed to play beep tone: \(error)")
        }
    }
    
    private func startWorkout() {
        workoutStartTime = Date()
        startElapsedTimeTimer()
        
        // Ensure slide-up tab is collapsed when starting
        isSlideUpTabExpanded = false
        dragOffset = 0
        
        // Create workout log in Firestore
        workoutLogService.createWorkoutLog(workoutName: workout.name) { result in
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
        // Special handling for rest periods: skip buffer, announce and start immediately
        if exercise.name == "Rest" {
            handleRestPeriod(for: exercise)
            return
        }
        
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
        // Add preamble: "First up" for first exercise, "Next up" for others
        let guideText: String
        let exerciseNameWithSide = formatExerciseNameWithSide(exercise)
        if currentExerciseIndex > 0 {
            guideText = "Next up, \(exerciseNameWithSide), \(formatRepsTime(exercise))"
        } else {
            guideText = "First up, \(exerciseNameWithSide), \(formatRepsTime(exercise))"
        }
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
                    // Play beep sound and haptic feedback when exercise starts (buffer period ends)
                    playBeepTone(frequency: 800.0, duration: 0.15) // Higher pitch for start
                    triggerStartHaptic()
                    startExercise()
                }
            }
        }
    }
    
    private func handleRestPeriod(for exercise: WorkoutExercise) {
        // Stop any ongoing speech
        SpeechManager.shared.stopSpeaking()
        SpeechManager.shared.clearSpeechQueue()
        
        // No intro buffer for rest periods
        isShowingIntro = false
        
        // Collapse slide-up tab
        withAnimation {
            isSlideUpTabExpanded = false
            dragOffset = 0
        }
        
        // Parse rest duration from exercise.reps (format: ":30" -> 30 seconds)
        let restDuration = parseTimeFromReps(exercise.reps)
        
        // Generate rest announcement with weighted random variation
        let announcement = generateRestAnnouncement(duration: restDuration)
        SpeechManager.shared.speakCoachingFeedback(announcement)
        
        // Start rest timer immediately (no buffer)
        startExercise()
    }
    
    /// Generate rest period announcement with weighted random variations
    /// Majority of time (70%) uses basic "Rest, x Seconds"
    /// Occasionally (30%) uses one of the motivational variations
    private func generateRestAnnouncement(duration: Int) -> String {
        let basicAnnouncement = "Rest, \(duration) Seconds"
        
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
    
    private func startExercise() {
        guard let exercise = currentExercise else { return }
        
        if isTimeBasedExercise {
            // Reset reminder flags for new exercise
            hasSpoken30SecondReminder = false
            hasSpoken10SecondReminder = false
            
            // Start countdown timer for time-based exercise
            exerciseTimeRemaining = currentExerciseDuration
            startExerciseTimer()
        } else {
            // For rep-based exercises, calculate time based on HIGH end of rep range
            let highEndRepCount = extractHighEndRepCount(from: exercise.reps)
            // Estimate: 3.5 seconds per rep (using high end)
            let estimatedTimeForHighEnd = Int(Double(highEndRepCount) * 3.5)
            let reminderTime = estimatedTimeForHighEnd + 20
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
                // Play different tone and haptic feedback when exercise time is up (for rep-based exercises)
                self.playBeepTone(frequency: 400.0, duration: 0.15) // Lower pitch for end
                self.triggerEndHaptic()
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
                    
                    // Check for 30-second reminder (only for exercises >= 60 seconds)
                    if currentExerciseDuration >= 60 && exerciseTimeRemaining == 30 && !hasSpoken30SecondReminder {
                        hasSpoken30SecondReminder = true
                        SpeechManager.shared.speakCoachingFeedback("30 Seconds Left")
                    }
                    
                    // Check for 10-second reminder (all timed exercises)
                    if exerciseTimeRemaining == 10 && !hasSpoken10SecondReminder {
                        hasSpoken10SecondReminder = true
                        SpeechManager.shared.speakCoachingFeedback("10 Seconds Left")
                    }
                } else {
                    // Auto-advance for time-based exercises
                    stopExerciseTimer()
                    // Play different tone and haptic feedback when exercise ends
                    playBeepTone(frequency: 400.0, duration: 0.15) // Lower pitch for end
                    triggerEndHaptic()
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
        
        // Reset glow effect
        shouldGlowForwardArrow = false
        
        // Play finish beep tone and haptic feedback when manually advancing
        // (only if not in intro buffer - buffer skip is handled separately)
        if !isShowingIntro {
            playBeepTone(frequency: 400.0, duration: 0.15) // Lower pitch for end
            triggerEndHaptic()
        }
        
        // Clean up current exercise timers
        introTimer?.invalidate()
        introTimer = nil
        stopExerciseTimer()
        reminderTimer?.invalidate()
        reminderTimer = nil
        
        // Collapse slide-up tab when moving to next exercise
        withAnimation {
            isSlideUpTabExpanded = false
            dragOffset = 0
        }
        
        if currentExerciseIndex < workout.exercises.count - 1 {
            // Reset reminder flags for new exercise
            hasSpoken30SecondReminder = false
            hasSpoken10SecondReminder = false
            
            // Reset set tracking for next exercise
            resetSetTracking()
            
            currentExerciseIndex += 1
            
            if let exercise = currentExercise {
                showIntroBuffer(for: exercise)
            }
        } else {
            // Workout complete - end workout log
            if let logId = currentWorkoutLogId {
                workoutLogService.endWorkoutLog(workoutLogId: logId) { result in
                    switch result {
                    case .success:
                        print("✅ Workout log ended: \(logId)")
                    case .failure(let error):
                        print("❌ Failed to end workout log: \(error.localizedDescription)")
                    }
                }
            }
            // Return to intro state
            withAnimation(.easeInOut(duration: 0.3)) {
                isWorkoutActive = false
                stopAllTimers()
            }
        }
    }
    
    private func moveToPreviousExercise() {
        // Stop any ongoing speech and clear the queue
        SpeechManager.shared.stopSpeaking()
        SpeechManager.shared.clearSpeechQueue()
        
        // Reset glow effect
        shouldGlowForwardArrow = false
        
        // Clean up current exercise timers
        introTimer?.invalidate()
        introTimer = nil
        stopExerciseTimer()
        reminderTimer?.invalidate()
        reminderTimer = nil
        
        // Collapse slide-up tab when moving to previous exercise
        withAnimation {
            isSlideUpTabExpanded = false
            dragOffset = 0
        }
        
        if currentExerciseIndex > 0 {
            // Reset reminder flags for previous exercise
            hasSpoken30SecondReminder = false
            hasSpoken10SecondReminder = false
            
            currentExerciseIndex -= 1
            
            if let exercise = currentExercise {
                showIntroBuffer(for: exercise)
            }
        }
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
        
        // Reset glow effect
        shouldGlowForwardArrow = false
        
        // Clean up current exercise timers
        introTimer?.invalidate()
        introTimer = nil
        stopExerciseTimer()
        reminderTimer?.invalidate()
        reminderTimer = nil
        
        // Reset reminder flags
        hasSpoken30SecondReminder = false
        hasSpoken10SecondReminder = false
        
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
    
    private func playRepReminder(for exercise: WorkoutExercise) {
        let repRange = formatRepRangeForSpeech(exercise.reps)
        let reminderText = "When you've completed \(repRange), press the arrow to move on"
        SpeechManager.shared.speakCoachingFeedback(reminderText)
        // Activate glow effect on forward arrow
        shouldGlowForwardArrow = true
    }
    
    private func playExerciseGuide() {
        // Only play guide for the current exercise
        guard let exercise = currentExercise else { return }
        
        // Stop any ongoing speech and clear queue before playing new guide
        SpeechManager.shared.stopSpeaking()
        SpeechManager.shared.clearSpeechQueue()
        
        let exerciseNameWithSide = formatExerciseNameWithSide(exercise)
        let guideText = "\(exerciseNameWithSide), \(formatRepsTime(exercise))"
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
    
    /// Saves the current set log to Firestore if reps are logged.
    ///
    /// Weight is optional (nil for bodyweight exercises). When a set is saved:
    /// - Creates ExerciseSetLog document in Firestore
    /// - Increments set number for next set
    /// - Resets current set data (weight, reps, flags)
    private func saveSetLogIfComplete() {
        guard let workoutLogId = currentWorkoutLogId,
              let exercise = currentExercise else {
            return
        }
        
        // Save if we have reps (weight is optional for bodyweight exercises)
        guard let reps = currentSetReps else {
            return
        }
        
        workoutLogService.saveSetLog(
                workoutLogId: workoutLogId,
                exerciseName: exercise.name,
                setNumber: currentSetNumber,
                weight: currentSetWeight,
                reps: reps,
                flaggedPain: currentSetPainFlag,
                flaggedNotInControl: currentSetNotInControlFlag
            ) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let setLogId):
                        print("✅ Set log saved: \(setLogId)")
                        // Increment set number for next set
                        currentSetNumber += 1
                        // Reset current set data
                        currentSetWeight = nil
                        currentSetReps = nil
                        currentSetPainFlag = false
                        currentSetNotInControlFlag = false
                    case .failure(let error):
                        print("❌ Failed to save set log: \(error.localizedDescription)")
                    }
                }
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
    /// Used for general calculations (returns midpoint for ranges)
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
    
    /// Extract HIGH end of rep range from reps string ("10-12" -> 12, "8" -> 8)
    /// Used for reminder timer calculations
    private func extractHighEndRepCount(from reps: String) -> Int {
        if reps.contains("-") {
            // Range format "10-12" - return the max (high end)
            let components = reps.split(separator: "-")
            if components.count == 2,
               let max = Int(components[1].trimmingCharacters(in: .whitespaces)) {
                return max
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
    
    /// Extract side information from exercise notes (e.g., "Right Side", "Left Side")
    /// Returns the side string if found, nil otherwise
    private func extractSideFromNotes(_ notes: String?) -> String? {
        guard let notes = notes?.trimmingCharacters(in: .whitespaces), !notes.isEmpty else {
            return nil
        }
        
        // Check for common side patterns (case-insensitive)
        let lowercased = notes.lowercased()
        if lowercased.contains("right side") || lowercased == "right side" {
            return "Right Side"
        } else if lowercased.contains("left side") || lowercased == "left side" {
            return "Left Side"
        }
        
        return nil
    }
    
    /// Format exercise name with side information if present
    /// Returns "Exercise Name - Right Side" or just "Exercise Name"
    private func formatExerciseNameWithSide(_ exercise: WorkoutExercise) -> String {
        let baseName = exercise.name
        
        if let side = extractSideFromNotes(exercise.notes) {
            return "\(baseName) - \(side)"
        }
        
        return baseName
    }
    
    /// Format rep range for speech (e.g., "10-12" -> "10 to 12 reps", "8" -> "8 reps")
    private func formatRepRangeForSpeech(_ reps: String) -> String {
        if reps.contains("-") {
            // Range format "10-12"
            let components = reps.split(separator: "-")
            if components.count == 2,
               let min = Int(components[0].trimmingCharacters(in: .whitespaces)),
               let max = Int(components[1].trimmingCharacters(in: .whitespaces)) {
                return "\(min) to \(max) reps"
            }
        } else if let count = Int(reps) {
            // Single number "8"
            return "\(count) reps"
        }
        // Fallback for any other format
        return "\(reps) reps"
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
    WorkoutIntroView(workout: WorkoutLibrary.pythonWrangler)
        .preferredColorScheme(.dark)
}
