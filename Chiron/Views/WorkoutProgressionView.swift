//
//  WorkoutProgressionView.swift
//  Chiron
//
//  Sheet view displaying the full workout progression with all exercises grouped by phases.
//  Supports inline exercise expansion with video player and action buttons.
//

import SwiftUI

/// Sheet view that displays the complete workout progression with all exercises,
/// grouped by phases (Warm-up, Primers, Supersets, Finisher, Cool Down).
/// 
/// Features:
/// - Phase-based grouping with duration calculations
/// - Round-based sections (e.g., "3 ROUNDS") with expandable/collapsible rounds
/// - Inline exercise expansion showing video player, action buttons (Weight, Reps, Flag, Guide, History, Jump to Here)
/// - Exercise thumbnail placeholders and rest cards
/// - Auto-scrolls to current exercise when opened from active workout (positions current exercise at top of view)
///
/// Presented when the list button is tapped in `WorkoutIntroView` or `WorkoutActiveView`.
struct WorkoutProgressionView: View {
    let workout: PredeterminedWorkout
    @Environment(\.dismiss) private var dismiss
    
    /// Optional callback to jump to a specific exercise index in the main workout view
    var onJumpToExercise: ((Int) -> Void)? = nil
    
    /// Optional current exercise index (to highlight or show current position)
    var currentExerciseIndex: Int? = nil
    
    /// Exercise data tracking: stores weight/reps per exercise index
    var exerciseData: [Int: (weight: Double?, reps: Int?)]? = nil
    
    /// Callback to update exercise data in parent view
    var onUpdateExerciseData: ((Int, Double?, Int?) -> Void)? = nil
    
    /// Workout log ID for Firebase saving (optional - only needed if saving from overview)
    var workoutLogId: String? = nil
    
    /// Callback to save set log to Firebase (takes exerciseIndex, weight, reps)
    var onSaveSetLog: ((Int, Double?, Int?) -> Void)? = nil
    
    /// Local state to track exercise data (updated via callback)
    @State private var localExerciseData: [Int: (weight: Double?, reps: Int?)] = [:]
    
    /// Currently expanded exercise ID for inline expansion
    @State private var expandedExerciseId: UUID?
    
    /// Set of phase names that have been expanded to show all rounds
    @State private var expandedPhases: Set<String> = []
    
    // MARK: - Sheet Presentation State
    
    /// Sheet presentation uses SwiftUI's `item:` binding pattern to prevent race conditions.
    ///
    /// **Problem Fixed:** Previously used `isPresented:` with separate state variables, which caused
    /// sheets to appear blank on first open (especially when workout was paused) because the sheet
    /// closure would evaluate before state variables were set.
    ///
    /// **Solution:** Using `item:` binding ensures the context (containing all required data) is
    /// available atomically when the sheet is presented, eliminating the race condition.
    
    /// Context for weight/reps input sheets - holds both exercise and index together
    struct ExerciseContext: Identifiable {
        let id = UUID()
        let exercise: WorkoutExercise
        let exerciseIndex: Int
    }
    
    /// Context for history sheet - holds exercise name
    struct HistoryContext: Identifiable {
        let id = UUID()
        let exerciseName: String
    }
    
    /// Exercise context for weight input sheet (nil = sheet not shown)
    @State private var weightInputContext: ExerciseContext?
    
    /// Exercise context for reps input sheet (nil = sheet not shown)
    @State private var repsInputContext: ExerciseContext?
    
    /// Exercise context for history sheet (nil = sheet not shown)
    @State private var historyContext: HistoryContext?
    
    /// Sheet presentation state for flag options (doesn't require context since it doesn't persist data)
    @State private var showFlagOptions: Bool = false
    // MARK: - Computed Properties
    
    /// Groups exercises by their phase property, defaulting to "Main Workout" if phase is nil
    private var exercisesByPhase: [String: [WorkoutExercise]] {
        Dictionary(grouping: workout.exercises) { exercise in
            exercise.phase ?? "Main Workout"
        }
    }
    
    /// Returns phases in a specific order: Warm-up, Primers, Supersets, Finisher, Cool Down.
    /// Any phases not in the predefined order are sorted alphabetically and appended.
    private var phaseOrder: [String] {
        let phases = Array(exercisesByPhase.keys)
        let predefinedOrder = [
            "Warm-up",
            "Explosive Tricep Primer",
            "Explosive Bicep Primer",
            "Superset 1",
            "Superset 2",
            "Finisher",
            "Vertical Pull",
            "Horizontal Row",
            "Rear Delt Work",
            "Brachialis Bicep Work",
            "Long Head Bicep Work",
            "Trap Work",
            "Cool Down"
        ]
        let orderedPhases = predefinedOrder.filter { phases.contains($0) }
        let remainingPhases = phases.filter { !predefinedOrder.contains($0) }.sorted()
        return orderedPhases + remainingPhases
    }
    
    /// Returns the phase name for the current exercise, or nil if not found.
    /// Used to determine which phase should be auto-expanded when the overview menu opens.
    private var currentExercisePhase: String? {
        guard let currentIndex = currentExerciseIndex,
              currentIndex >= 0,
              currentIndex < workout.exercises.count else {
            return nil
        }
        return workout.exercises[currentIndex].phase ?? "Main Workout"
    }
    
    /// Determines if the overview menu was opened from the active workout view.
    /// 
    /// Returns `true` when both `workoutLogId` and `onSaveSetLog` are provided,
    /// which only occurs when opened from `WorkoutActiveView`. This is used to
    /// conditionally show the full set of action buttons matching the active view.
    private var isFromActiveView: Bool {
        return workoutLogId != nil && onSaveSetLog != nil
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                
                // ScrollViewReader enables programmatic scrolling to the current exercise
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: 0) {
                        // Overview header bar (spacer for fixed button)
                        ZStack {
                            Text("Overview")
                                .font(.neueMontrealSemiBold(size: 16))
                                .foregroundColor(.textPrimary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .frame(height: 60)
                        
                        // Exercises grouped by phase
                        VStack(spacing: 0) {
                            ForEach(phaseOrder, id: \.self) { phase in
                                if let exercises = exercisesByPhase[phase] {
                                    // Phase separator
                                    PhaseSeparatorBar(
                                        phaseName: phase,
                                        duration: phase == "Cool Down" ? 2 : calculatePhaseDuration(exercises),
                                        rounds: getRoundsForPhase(phase, exercises: exercises)
                                    )
                                    
                                    // Get exercises to display (first round or all rounds)
                                    let exercisesToShow = getExercisesToShow(for: phase, exercises: exercises)
                                    
                                    // Exercises in this phase
                                    ForEach(exercisesToShow, id: \.id) { exercise in
                                        let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exercise.id }) ?? 0
                                        // For camera setup rows in sections that have exercise selection, "Jump to Here" goes to exercise selection first
                                        let jumpToExerciseIndex: Int = {
                                            guard exercise.notes?.hasPrefix("CAMERA_SETUP") == true, exerciseIndex > 0 else { return exerciseIndex }
                                            let prev = workout.exercises[exerciseIndex - 1]
                                            guard prev.notes?.hasPrefix("EXERCISE_SELECTION") == true, prev.phase == exercise.phase else { return exerciseIndex }
                                            return exerciseIndex - 1
                                        }()
                                        
                                        WorkoutProgressionExerciseRow(
                                            exercise: exercise,
                                            exerciseIndex: exerciseIndex,
                                            exerciseData: localExerciseData,
                                            isExpanded: expandedExerciseId == exercise.id,
                                            isCurrentExercise: currentExerciseIndex == exerciseIndex,
                                            isFromActiveView: isFromActiveView,
                                            onTap: {
                                                if expandedExerciseId == exercise.id {
                                                    expandedExerciseId = nil
                                                } else {
                                                    expandedExerciseId = exercise.id
                                                }
                                            },
                                            onJumpToExercise: {
                                                if let onJumpToExercise = onJumpToExercise {
                                                    onJumpToExercise(jumpToExerciseIndex)
                                                    dismiss()
                                                }
                                            },
                                            onShowWeightInput: {
                                                weightInputContext = ExerciseContext(exercise: exercise, exerciseIndex: exerciseIndex)
                                            },
                                            onShowRepsInput: {
                                                repsInputContext = ExerciseContext(exercise: exercise, exerciseIndex: exerciseIndex)
                                            },
                                            onShowFlagOptions: {
                                                showFlagOptions = true
                                            },
                                            onShowHistory: {
                                                historyContext = HistoryContext(exerciseName: exercise.name)
                                            },
                                            onPlayGuide: {
                                                playExerciseGuide(for: exercise)
                                            }
                                        )
                                        // Unique ID for each exercise row to enable scrolling via ScrollViewReader
                                        .id(exerciseIndex)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 8)
                                    }
                                    
                                    // Show "Show All Rounds" button if phase has rounds and not all shown
                                    // Exclude Cool Down from having an expand button
                                    if hasRounds(phase, exercises: exercises) && !expandedPhases.contains(phase) && phase != "Cool Down" {
                                        Button(action: {
                                            expandedPhases.insert(phase)
                                        }) {
                                            HStack {
                                                Spacer()
                                                Text("Show All Rounds")
                                                    .font(.neueMontrealSemiBold(size: 14))
                                                    .foregroundColor(.primaryPurple)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 12)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 40)
                    }
                    }
                    // Auto-scroll to current exercise when overview menu opens
                    // Positions the current exercise card at the top of the visible view
                    .onAppear {
                        guard let currentIndex = currentExerciseIndex else { return }
                        
                        // Auto-expand the phase containing the current exercise if it has multiple rounds
                        // and is not Warm-up, Cool Down, or Finisher
                        if let phase = currentExercisePhase,
                           phase != "Warm-up",
                           phase != "Cool Down",
                           phase != "Finisher",
                           !expandedPhases.contains(phase),
                           let phaseExercises = exercisesByPhase[phase],
                           hasRounds(phase, exercises: phaseExercises) {
                            expandedPhases.insert(phase)
                        }
                        
                        // Small delay ensures the view hierarchy is fully laid out before scrolling
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                scrollProxy.scrollTo(currentIndex, anchor: .top)
                            }
                        }
                    }
                }
                
                // Fixed dismiss button in top left (always visible)
                VStack {
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        
                        Spacer()
                    }
                    
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            // Initialize local state from passed exerciseData
            if let data = exerciseData {
                localExerciseData = data
            }
        }
        // Weight input sheet - uses `item:` binding to ensure context is available when presented
        .sheet(item: $weightInputContext) { context in
            WeightInputSheet(
                isPresented: Binding(
                    get: { weightInputContext != nil },
                    set: { if !$0 { weightInputContext = nil } }
                ),
                weight: .constant(localExerciseData[context.exerciseIndex]?.weight),
                onSave: { weight in
                    // Update local state
                    let currentData = localExerciseData[context.exerciseIndex] ?? (weight: nil, reps: nil)
                    localExerciseData[context.exerciseIndex] = (weight: weight, reps: currentData.reps)
                    // Update parent via callback
                    if let onUpdate = onUpdateExerciseData {
                        onUpdate(context.exerciseIndex, weight, currentData.reps)
                    }
                    // Save to Firebase if we have reps (weight alone doesn't save a set)
                    if let reps = currentData.reps, let onSave = onSaveSetLog {
                        // Ensure callback executes on main thread
                        DispatchQueue.main.async {
                            onSave(context.exerciseIndex, weight, reps)
                        }
                    }
                    weightInputContext = nil
                }
            )
        }
        // Reps input sheet - uses `item:` binding to ensure context is available when presented
        .sheet(item: $repsInputContext) { context in
            RepsInputSheet(
                isPresented: Binding(
                    get: { repsInputContext != nil },
                    set: { if !$0 { repsInputContext = nil } }
                ),
                reps: .constant(localExerciseData[context.exerciseIndex]?.reps),
                onSave: { reps in
                    // Update local state
                    let currentData = localExerciseData[context.exerciseIndex] ?? (weight: nil, reps: nil)
                    localExerciseData[context.exerciseIndex] = (weight: currentData.weight, reps: reps)
                    // Update parent via callback
                    if let onUpdate = onUpdateExerciseData {
                        onUpdate(context.exerciseIndex, currentData.weight, reps)
                    }
                    // Save to Firebase if we have both weight and reps (or just reps for bodyweight)
                    if let onSave = onSaveSetLog {
                        // Ensure callback executes on main thread
                        DispatchQueue.main.async {
                            onSave(context.exerciseIndex, currentData.weight, reps)
                        }
                    }
                    repsInputContext = nil
                }
            )
        }
        .sheet(isPresented: $showFlagOptions) {
            FlagOptionsSheet(
                isPresented: $showFlagOptions,
                flaggedPain: .constant(false),
                flaggedNotInControl: .constant(false),
                onSave: { _, _ in
                    // Note: Logging from overview is not implemented - users should log from the active workout view
                    // This sheet is shown for UI consistency but doesn't persist data
                }
            )
        }
        // History sheet - uses `item:` binding to ensure exercise name is available when presented
        .sheet(item: $historyContext) { context in
            ExerciseHistorySheet(
                isPresented: Binding(
                    get: { historyContext != nil },
                    set: { if !$0 { historyContext = nil } }
                ),
                exerciseName: context.exerciseName
            )
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Helper Functions
    
    /// Plays exercise guide audio using SpeechManager.
    private func playExerciseGuide(for exercise: WorkoutExercise) {
        let guideText = "\(exercise.name), \(formatRepsTime(exercise))"
        SpeechManager.shared.speakCoachingFeedback(guideText)
    }
    
    /// Formats reps/time string for speech display.
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
    
    /// Calculates the estimated duration of a phase in minutes based on exercise categories,
    /// sets, rest times, and transition times.
    ///
    /// - Parameter exercises: Array of exercises in the phase
    /// - Returns: Estimated duration in minutes (minimum 1 minute)
    ///
    /// Estimation logic:
    /// - Compound exercises: ~45 seconds per set
    /// - Mobility exercises: ~20 seconds per set
    /// - Other exercises: ~30 seconds per set
    /// - Rest time applied between sets (not after last set)
    /// - 30 seconds transition time per exercise
    private func calculatePhaseDuration(_ exercises: [WorkoutExercise]) -> Int {
        let totalSeconds = exercises.reduce(0) { total, exercise in
            // Estimate work time per set based on exercise category
            let workTimePerSet: Int
            switch exercise.category {
            case .compound:
                workTimePerSet = 45
            case .mobility:
                workTimePerSet = 20
            default:
                workTimePerSet = 30
            }
            
            let totalWorkTime = workTimePerSet * exercise.sets
            let totalRestTime = exercise.restTime * max(0, exercise.sets - 1)
            let transitionTime = 30 // seconds between exercises
            
            return total + totalWorkTime + totalRestTime + transitionTime
        }
        
        // Convert to minutes, rounding up
        return max(1, Int(ceil(Double(totalSeconds) / 60.0)))
    }
    
    /// Determines the number of rounds in a phase by counting unique exercise names
    /// and dividing total exercises by unique exercises per round.
    ///
    /// - Parameters:
    ///   - phase: Phase name (for reference)
    ///   - exercises: Array of exercises in the phase
    /// - Returns: Number of rounds if calculable, nil otherwise
    ///
    /// Example: If a phase has ["Bench Press", "Rest", "Bench Press", "Rest", "Bench Press", "Rest"],
    /// unique exercises = 1 (Bench Press), total non-rest exercises = 3, rounds = 3.
    private func getRoundsForPhase(_ phase: String, exercises: [WorkoutExercise]) -> Int? {
        let uniqueExercises = Set(exercises.filter { $0.name != "Rest" }.map { $0.name })
        guard !uniqueExercises.isEmpty else { return nil }
        
        let exerciseCount = exercises.filter { $0.name != "Rest" }.count
        return exerciseCount / uniqueExercises.count
    }
    
    /// Checks if a phase has a multi-round structure (more than 1 round).
    ///
    /// - Parameters:
    ///   - phase: Phase name
    ///   - exercises: Array of exercises in the phase
    /// - Returns: true if phase has more than 1 round, false otherwise
    private func hasRounds(_ phase: String, exercises: [WorkoutExercise]) -> Bool {
        guard let rounds = getRoundsForPhase(phase, exercises: exercises) else { return false }
        return rounds > 1
    }
    
    /// Returns the exercises to display for a phase:
    /// - If phase has rounds and is not expanded: returns first round only (up to first Rest)
    /// - Otherwise: returns all exercises
    /// - Camera setup exercises are filtered out if coaching is disabled for that exercise
    /// - Cool Down always shows all exercises regardless of rounds or expansion state
    ///
    /// - Parameters:
    ///   - phase: Phase name
    ///   - exercises: All exercises in the phase
    /// - Returns: Exercises to display based on expansion state
    private func getExercisesToShow(for phase: String, exercises: [WorkoutExercise]) -> [WorkoutExercise] {
        let filteredExercises = exercises.filter { exercise in
            guard let notes = exercise.notes else { return true }
            // Exclude exercise selection from overview; only camera setup row is shown per section
            if notes.hasPrefix("EXERCISE_SELECTION") { return false }
            if notes.hasPrefix("CAMERA_SETUP") {
                return CameraCoachingPreferencesManager.shared.isCameraCoachingEnabled(for: exercise.name)
            }
            return true
        }
        
        if phase == "Cool Down" {
            return filteredExercises
        }
        
        guard hasRounds(phase, exercises: filteredExercises) && !expandedPhases.contains(phase) else {
            return filteredExercises
        }
        
        let uniqueExerciseNames = Set(filteredExercises.filter { exercise in
            exercise.name != "Rest" && !(exercise.notes?.hasPrefix("CAMERA_SETUP") ?? false)
        }.map { $0.name })
        let exercisesPerRound = uniqueExerciseNames.count
        
        var firstRound: [WorkoutExercise] = []
        var exerciseCount = 0
        
        for exercise in filteredExercises {
            if exercise.name == "Rest" {
                firstRound.append(exercise)
                break
            } else {
                let isCameraSetup = exercise.notes?.hasPrefix("CAMERA_SETUP") ?? false
                if isCameraSetup {
                    firstRound.append(exercise)
                } else if exerciseCount < exercisesPerRound {
                    firstRound.append(exercise)
                    exerciseCount += 1
                }
            }
        }
        
        return firstRound
    }
}

// MARK: - Exercise Thumbnail Placeholder

/// Placeholder thumbnail image for exercises in the workout progression list.
private struct ExerciseThumbnailPlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.1))
            .frame(width: 80, height: 80)
            .overlay(
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 32))
                    .foregroundColor(.textSecondary.opacity(0.5))
            )
    }
}

// MARK: - Rest Thumbnail

/// Rest card thumbnail with clock icon.
private struct RestThumbnail: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.1))
            .frame(width: 80, height: 80)
            .overlay(
                Image(systemName: "clock")
                    .font(.system(size: 32))
                    .foregroundColor(.textSecondary.opacity(0.5))
            )
    }
}

// MARK: - Camera Setup Thumbnail

/// Camera setup card thumbnail with camera icon.
private struct CameraSetupThumbnail: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.1))
            .frame(width: 80, height: 80)
            .overlay(
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 32))
                    .foregroundColor(.textSecondary.opacity(0.5))
            )
    }
}

// MARK: - Exercise Selection Thumbnail

/// Exercise selection card thumbnail with list icon.
private struct ExerciseSelectionThumbnail: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.1))
            .frame(width: 80, height: 80)
            .overlay(
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 32))
                    .foregroundColor(.textSecondary.opacity(0.5))
            )
    }
}

// MARK: - Phase Separator Bar

/// Bar component displaying phase name, duration, and round count (if applicable).
///
/// Displays:
/// - Phase name in uppercase (e.g., "EXPLOSIVE TRICEP PRIMER")
/// - Round count for multi-round phases (e.g., "- 3 ROUNDS") - excluded for Warm-up, Cool Down, and Finisher
/// - Estimated duration in minutes (e.g., "5 min")
///
/// Styled with dark background matching the app theme.
private struct PhaseSeparatorBar: View {
    let phaseName: String
    let duration: Int
    let rounds: Int?
    
    var body: some View {
        HStack {
            // Show rounds for multi-round phases and "1 ROUND" for single-round phases (e.g. Trap Work), excluding Warm-up, Cool Down, and Finisher
            if let rounds = rounds,
               rounds >= 1,
               phaseName != "Warm-up",
               phaseName != "Cool Down",
               phaseName != "Finisher" {
                Text("\(phaseName.uppercased()) - \(rounds) ROUND\(rounds == 1 ? "" : "S")")
                    .font(.neueMontrealSemiBold(size: 14))
                    .foregroundColor(.textPrimary)
            } else {
                Text(phaseName.uppercased())
                    .font(.neueMontrealSemiBold(size: 14))
                    .foregroundColor(.textPrimary)
            }
            
            Spacer()
            
            Text("\(duration) min")
                .font(.neueMontrealSemiBold(size: 14))
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.06))
    }
}

// MARK: - Exercise Row

/// Row component displaying a single exercise in the workout progression.
///
/// Features:
/// - Tappable row to expand/collapse (Rest and Camera Setup expandable when from active view)
/// - Shows exercise thumbnail placeholder, rest icon, or camera setup icon
/// - When expanded from active view:
///   - Rest/Camera Setup: "Jump to Here" button only
///   - Warm-up/Cool-down: Flag, Guide, Jump to Here buttons (3-column grid)
///   - Regular exercises: Weight, Reps, Flag, Guide, History, Jump to Here buttons (3-column grid) + video player
/// - When expanded from intro view:
///   - Warm-up/Cool-down: Guide button only
///   - Regular exercises: Guide and History buttons (2-column grid) + video player
/// - Formats exercise details (reps, sets, notes) with proper styling
private struct WorkoutProgressionExerciseRow: View {
    let exercise: WorkoutExercise
    let exerciseIndex: Int
    let exerciseData: [Int: (weight: Double?, reps: Int?)]?
    let isExpanded: Bool
    let isCurrentExercise: Bool
    let isFromActiveView: Bool
    let onTap: () -> Void
    let onJumpToExercise: () -> Void
    let onShowWeightInput: () -> Void
    let onShowRepsInput: () -> Void
    let onShowFlagOptions: () -> Void
    let onShowHistory: () -> Void
    let onPlayGuide: () -> Void
    
    /// Video name for exercise demonstration (currently placeholder).
    /// TODO: Map exercise names to actual video resources.
    private var videoName: String {
        return "bodyweight_squat_demo"
    }
    
    /// Whether this exercise is a camera setup exercise.
    private var isCameraSetupExercise: Bool {
        guard let notes = exercise.notes else { return false }
        return notes.hasPrefix("CAMERA_SETUP")
    }
    
    /// Whether this exercise is an exercise selection step.
    private var isExerciseSelectionExercise: Bool {
        guard let notes = exercise.notes else { return false }
        return notes.hasPrefix("EXERCISE_SELECTION")
    }
    
    /// Parse camera setup instructions from notes.
    /// Notes format: "CAMERA_SETUP|instruction1|instruction2|..."
    private var cameraSetupInstructions: [String] {
        guard let notes = exercise.notes, notes.hasPrefix("CAMERA_SETUP") else { return [] }
        let components = notes.components(separatedBy: "|")
        // Skip the first component ("CAMERA_SETUP") and return the rest
        return Array(components.dropFirst())
    }
    
    /// Returns the appropriate icon for a camera setup instruction based on its content.
    private func iconForCameraSetupInstruction(_ instruction: String, index: Int) -> String {
        let lowercased = instruction.lowercased()
        
        // Match icons based on instruction content and index
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
        
        // Default icon
        return "camera.fill"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Exercise header (always visible) - entire row is tappable
            HStack(alignment: .center, spacing: 12) {
                if exercise.name == "Rest" {
                    RestThumbnail()
                } else if isExerciseSelectionExercise {
                    ExerciseSelectionThumbnail()
                } else if isCameraSetupExercise {
                    CameraSetupThumbnail()
                } else {
                    ExerciseThumbnailPlaceholder()
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.name)
                        .font(.neueMontrealBold(size: 18))
                        .foregroundColor(.textPrimary)
                    
                    if isExerciseSelectionExercise {
                        Text("Exercise Selection")
                            .font(.neueMontrealRegular(size: 14))
                            .foregroundColor(.textSecondary)
                    } else if isCameraSetupExercise {
                        Text("Camera Setup")
                            .font(.neueMontrealRegular(size: 14))
                            .foregroundColor(.textSecondary)
                    } else {
                        // Reps and side details
                        HStack(spacing: 4) {
                            Text(formatRepsDetails())
                                .font(.neueMontrealRegular(size: 14))
                                .foregroundColor(.textSecondary)
                        }
                        
                        // Display entered weight/reps values if available
                        if let data = exerciseData?[exerciseIndex], (data.weight != nil || data.reps != nil) {
                            HStack(spacing: 8) {
                                if let weight = data.weight {
                                    HStack(spacing: 4) {
                                        Text(String(format: "%.1f", weight))
                                            .font(.neueMontrealBold(size: 13))
                                            .foregroundColor(.textPrimary)
                                        Text("lbs")
                                            .font(.neueMontrealRegular(size: 12))
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                                
                                if data.weight != nil && data.reps != nil {
                                    Text("•")
                                        .font(.neueMontrealRegular(size: 12))
                                        .foregroundColor(.textSecondary)
                                }
                                
                                if let reps = data.reps {
                                    HStack(spacing: 4) {
                                        Text("\(reps)")
                                            .font(.neueMontrealBold(size: 13))
                                            .foregroundColor(.textPrimary)
                                        Text("reps")
                                            .font(.neueMontrealRegular(size: 12))
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                if !isFromActiveView {
                    guard exercise.name != "Rest", !isCameraSetupExercise, !isExerciseSelectionExercise else { return }
                }
                onTap()
            }
            
            // Expanded content section
            //
            // Action button visibility rules:
            //
            // When opened from active view (isFromActiveView == true):
            //   - Rest/Camera Setup: "Jump to Here" button only
            //   - Warm-up/Cool-down: Flag, Guide, Jump to Here (3-column grid)
            //   - Regular exercises: Weight, Reps, Flag, Guide, History, Jump to Here (3-column grid)
            //
            // When opened from intro view (isFromActiveView == false):
            //   - Rest/Camera Setup: Not expandable (no buttons)
            //   - Warm-up/Cool-down: Guide button only
            //   - Regular exercises: Guide and History buttons (2-column grid)
            if isExpanded {
                VStack(spacing: 24) {
                    if (exercise.name == "Rest" || isCameraSetupExercise || isExerciseSelectionExercise) && isFromActiveView {
                        OverviewActionButton(
                            icon: "arrow.right.circle.fill",
                            title: "Jump to Here",
                            isDisabled: false,
                            action: onJumpToExercise
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    } else if exercise.name == "Rest" || isCameraSetupExercise || isExerciseSelectionExercise {
                        EmptyView()
                    } else {
                        // Video player for regular exercises
                        VideoPlayerArea(videoName: videoName)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 16)
                            .padding(.horizontal, -20) // Extend beyond parent padding to screen edges
                        
                        // Regular exercise buttons: Different sets based on context and phase
                        let isWarmUpOrCoolDown = exercise.phase == "Warm-up" || exercise.phase == "Cool Down"
                        
                        if isFromActiveView {
                            // Active view: Full button set matching WorkoutActiveView
                            if isWarmUpOrCoolDown {
                                // Warm-up/Cool-down: Flag, Guide, Jump to Here (3-column grid)
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 12) {
                                    OverviewActionButton(
                                        icon: "flag.fill",
                                        title: "Flag",
                                        isDisabled: false,
                                        action: onShowFlagOptions
                                    )
                                    
                                    OverviewActionButton(
                                        icon: "speaker.wave.2.fill",
                                        title: "Guide",
                                        isDisabled: false,
                                        action: onPlayGuide
                                    )
                                    
                                    OverviewActionButton(
                                        icon: "arrow.right.circle.fill",
                                        title: "Jump to Here",
                                        isDisabled: false,
                                        action: onJumpToExercise
                                    )
                                }
                                .padding(.horizontal, 20)
                            } else {
                                // Regular exercises: Weight, Reps, Flag, Guide, History, Jump to Here (3-column grid)
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 12) {
                                    OverviewActionButton(
                                        icon: "dumbbell.fill",
                                        title: "Weight",
                                        isDisabled: false,
                                        action: onShowWeightInput
                                    )
                                    
                                    OverviewActionButton(
                                        icon: "list.number",
                                        title: "Reps",
                                        isDisabled: false,
                                        action: onShowRepsInput
                                    )
                                    
                                    OverviewActionButton(
                                        icon: "flag.fill",
                                        title: "Flag",
                                        isDisabled: false,
                                        action: onShowFlagOptions
                                    )
                                    
                                    OverviewActionButton(
                                        icon: "speaker.wave.2.fill",
                                        title: "Guide",
                                        isDisabled: false,
                                        action: onPlayGuide
                                    )
                                    
                                    OverviewActionButton(
                                        icon: "clock.arrow.circlepath",
                                        title: "History",
                                        isDisabled: false,
                                        action: onShowHistory
                                    )
                                    
                                    OverviewActionButton(
                                        icon: "arrow.right.circle.fill",
                                        title: "Jump to Here",
                                        isDisabled: false,
                                        action: onJumpToExercise
                                    )
                                }
                                .padding(.horizontal, 20)
                            }
                        } else {
                            // Intro view: Limited button set
                            if isWarmUpOrCoolDown {
                                // Warm-up/Cool-down: Guide button only
                                OverviewActionButton(
                                    icon: "speaker.wave.2.fill",
                                    title: "Guide",
                                    isDisabled: false,
                                    action: onPlayGuide
                                )
                                .padding(.horizontal, 20)
                            } else {
                                // Regular exercises: Guide and History buttons in 2-column grid
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 12) {
                                    OverviewActionButton(
                                        icon: "speaker.wave.2.fill",
                                        title: "Guide",
                                        isDisabled: false,
                                        action: onPlayGuide
                                    )
                                    
                                    OverviewActionButton(
                                        icon: "clock.arrow.circlepath",
                                        title: "History",
                                        isDisabled: false,
                                        action: onShowHistory
                                    )
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: 0.3), value: isExpanded)
            }
        }
    }
    
    /// Formats exercise repetition and set details for display.
    ///
    /// Formats:
    /// - Rest cards: ":45" → "45 seconds"
    /// - Duration format: ":30" → ":30"
    /// - Time-based: "30s" or "1min" → "30s" or "1 × 30s" (if multiple sets)
    /// - Range format: "8-12" → "8-12 reps" or "3 × 8-12 reps"
    /// - Simple count: "10" → "10 reps" or "3 × 10 reps"
    /// - Notes: Appended with " • " separator (e.g., "10 reps • Right Side")
    ///
    /// - Returns: Formatted string combining reps, sets, and notes
    private func formatRepsDetails() -> String {
        // Special handling for Rest cards
        if exercise.name == "Rest" {
            if exercise.reps.hasPrefix(":") {
                let secondsString = String(exercise.reps.dropFirst())
                if let seconds = Int(secondsString), seconds >= 60 {
                    let minutes = seconds / 60
                    return minutes == 1 ? "1 min" : "\(minutes) min"
                }
                return "\(secondsString) seconds"
            }
            return exercise.reps
        }
        
        var details: [String] = []
        
        // Handle duration format (starts with ":")
        if exercise.reps.hasPrefix(":") {
            details.append(exercise.reps)
        }
        // Handle time-based format (contains "s" or "min")
        else if exercise.reps.lowercased().contains("s") || exercise.reps.lowercased().contains("min") {
            if exercise.sets > 1 {
                details.append("\(exercise.sets) × \(exercise.reps)")
            } else {
                details.append(exercise.reps)
            }
        }
        // Handle range format (contains "-")
        else if exercise.reps.contains("-") {
            if exercise.sets > 1 {
                details.append("\(exercise.sets) × \(exercise.reps) reps")
            } else {
                details.append("\(exercise.reps) reps")
            }
        }
        // Handle simple rep count
        else {
            if exercise.sets > 1 {
                details.append("\(exercise.sets) × \(exercise.reps) reps")
            } else {
                details.append("\(exercise.reps) reps")
            }
        }
        
        // Append notes if available
        if let notes = exercise.notes, !notes.isEmpty {
            details.append(notes)
        }
        
        return details.joined(separator: " • ")
    }
}

// MARK: - Video Player Area

/// Landscape video player area (16:9 aspect ratio) displayed when an exercise is expanded.
/// Extends edge-to-edge across the screen width with no rounded corners.
///
/// - If video resource exists: plays looping video
/// - If video not found: displays placeholder with icon and text
private struct VideoPlayerArea: View {
    let videoName: String
    
    var body: some View {
        ZStack {
            if let url = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
                GeometryReader { geometry in
                    LoopingVideoView(url: url)
                        .frame(width: geometry.size.width, height: geometry.size.width * 9 / 16)
                        .clipped()
                }
                .aspectRatio(16/9, contentMode: .fit)
            } else {
                // Placeholder if video resource not found
                ZStack {
                    Color.white.opacity(0.1)
                    VStack(spacing: 12) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.textSecondary)
                        Text("Video Placeholder")
                            .font(.neueMontrealRegular(size: 14))
                            .foregroundColor(.textSecondary)
                    }
                }
                .aspectRatio(16/9, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Overview Action Button

/// Action button for expanded exercises in WorkoutProgressionView.
///
/// Matches the visual style of ActionButton used in the exercise title box
/// (WorkoutActiveView and WorkoutIntroView) for consistency.
private struct OverviewActionButton: View {
    let icon: String
    let title: String
    let isDisabled: Bool
    let isHighlighted: Bool
    let action: () -> Void
    
    init(icon: String, title: String, isDisabled: Bool = false, isHighlighted: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.isDisabled = isDisabled
        self.isHighlighted = isHighlighted
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(isDisabled ? .textSecondary.opacity(0.5) : (isHighlighted ? .primaryPurple : .textPrimary))
                
                Text(title)
                    .font(.neueMontrealSemiBold(size: 12))
                    .foregroundColor(isDisabled ? .textSecondary.opacity(0.5) : .textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(isDisabled ? Color.white.opacity(0.05) : (isHighlighted ? Color.primaryPurple.opacity(0.2) : Color.white.opacity(0.1)))
            .cornerRadius(12)
        }
        .disabled(isDisabled)
    }
}

#Preview {
    WorkoutProgressionView(workout: WorkoutLibrary.pythonWrangler)
        .preferredColorScheme(.dark)
}
