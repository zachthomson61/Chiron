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
/// - Inline exercise expansion showing video player, action buttons (Report Reps, Hear Guide, Exercise History)
/// - Exercise thumbnail placeholders and rest cards
///
/// Presented when the list button is tapped in `WorkoutIntroView`.
struct WorkoutProgressionView: View {
    let workout: PredeterminedWorkout
    @Environment(\.dismiss) private var dismiss
    
    /// Currently expanded exercise ID for inline expansion
    @State private var expandedExerciseId: UUID?
    
    /// Set of phase names that have been expanded to show all rounds
    @State private var expandedPhases: Set<String> = []
    
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
            "Cool Down"
        ]
        let orderedPhases = predefinedOrder.filter { phases.contains($0) }
        let remainingPhases = phases.filter { !predefinedOrder.contains($0) }.sorted()
        return orderedPhases + remainingPhases
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Overview header bar
                        ZStack {
                            HStack {
                                Button(action: { dismiss() }) {
                                    Image(systemName: "xmark")
                                        .font(.neueMontrealSemiBold(size: 16))
                                        .foregroundColor(.textPrimary)
                                }
                                
                                Spacer()
                            }
                            
                            Text("Overview")
                                .font(.neueMontrealSemiBold(size: 16))
                                .foregroundColor(.textPrimary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        
                        // Exercises grouped by phase
                        VStack(spacing: 0) {
                            ForEach(phaseOrder, id: \.self) { phase in
                                if let exercises = exercisesByPhase[phase] {
                                    // Phase separator
                                    PhaseSeparatorBar(
                                        phaseName: phase,
                                        duration: calculatePhaseDuration(exercises),
                                        rounds: getRoundsForPhase(phase, exercises: exercises)
                                    )
                                    
                                    // Get exercises to display (first round or all rounds)
                                    let exercisesToShow = getExercisesToShow(for: phase, exercises: exercises)
                                    
                                    // Exercises in this phase
                                    ForEach(exercisesToShow, id: \.id) { exercise in
                                        WorkoutProgressionExerciseRow(
                                            exercise: exercise,
                                            isExpanded: expandedExerciseId == exercise.id,
                                            onTap: {
                                                // Toggle expansion: if already expanded, collapse; otherwise expand
                                                if expandedExerciseId == exercise.id {
                                                    expandedExerciseId = nil
                                                } else {
                                                    expandedExerciseId = exercise.id
                                                }
                                            }
                                        )
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 8)
                                    }
                                    
                                    // Show "Show All Rounds" button if phase has rounds and not all shown
                                    if hasRounds(phase, exercises: exercises) && !expandedPhases.contains(phase) {
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
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Helper Functions
    
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
    ///
    /// - Parameters:
    ///   - phase: Phase name
    ///   - exercises: All exercises in the phase
    /// - Returns: Exercises to display based on expansion state
    private func getExercisesToShow(for phase: String, exercises: [WorkoutExercise]) -> [WorkoutExercise] {
        // If phase has rounds and hasn't been expanded, show only first round
        guard hasRounds(phase, exercises: exercises) && !expandedPhases.contains(phase) else {
            return exercises
        }
        
        // Find unique exercise names (excluding Rest) to determine round structure
        let uniqueExerciseNames = Set(exercises.filter { $0.name != "Rest" }.map { $0.name })
        let exercisesPerRound = uniqueExerciseNames.count
        
        // Collect exercises up to and including the first Rest
        var firstRound: [WorkoutExercise] = []
        var exerciseCount = 0
        
        for exercise in exercises {
            if exercise.name == "Rest" {
                firstRound.append(exercise)
                break // Stop after first Rest
            } else if exerciseCount < exercisesPerRound {
                firstRound.append(exercise)
                exerciseCount += 1
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

// MARK: - Phase Separator Bar

/// Bar component displaying phase name, duration, and round count (if applicable).
///
/// Displays:
/// - Phase name in uppercase (e.g., "EXPLOSIVE TRICEP PRIMER")
/// - Round count for multi-round phases (e.g., "- 3 ROUNDS") - excluded for Warm-up
/// - Estimated duration in minutes (e.g., "5 min")
///
/// Styled with dark background matching the app theme.
private struct PhaseSeparatorBar: View {
    let phaseName: String
    let duration: Int
    let rounds: Int?
    
    var body: some View {
        HStack {
            // Don't show rounds for Warm-up section
            if let rounds = rounds, phaseName != "Warm-up" {
                Text("\(phaseName.uppercased()) - \(rounds) ROUNDS")
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
/// - Tappable entire row (except Rest cards) to expand/collapse
/// - Shows exercise thumbnail placeholder or rest icon
/// - When expanded: displays landscape video player and action buttons
/// - Formats exercise details (reps, sets, notes) with proper styling
///
/// Note: Rest cards are not expandable and use a clock icon instead of exercise thumbnail.
private struct WorkoutProgressionExerciseRow: View {
    let exercise: WorkoutExercise
    let isExpanded: Bool
    let onTap: () -> Void
    
    /// Video name for exercise demonstration (currently placeholder).
    /// TODO: Map exercise names to actual video resources.
    private var videoName: String {
        return "bodyweight_squat_demo"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Exercise header (always visible) - entire row is tappable
            HStack(alignment: .center, spacing: 12) {
                // Exercise thumbnail placeholder (or Rest icon)
                if exercise.name == "Rest" {
                    RestThumbnail()
                } else {
                    ExerciseThumbnailPlaceholder()
                }
                
                // Exercise details
                VStack(alignment: .leading, spacing: 6) {
                    Text(exercise.name)
                        .font(.neueMontrealBold(size: 18))
                        .foregroundColor(.textPrimary)
                    
                    // Reps and side details
                    HStack(spacing: 4) {
                        Text(formatRepsDetails())
                            .font(.neueMontrealRegular(size: 14))
                            .foregroundColor(.textSecondary)
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                // Rest cards are not expandable
                if exercise.name != "Rest" {
                    onTap()
                }
            }
            
            // Expanded content (shown when isExpanded is true)
            if isExpanded {
                VStack(spacing: 24) {
                    // Landscape video player - full width, edge-to-edge, no rounded corners
                    VideoPlayerArea(videoName: videoName)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                        .padding(.horizontal, -20) // Extend beyond parent padding to screen edges
                    
                    // Action buttons row - equal size
                    HStack(spacing: 20) {
                        ActionButton(
                            icon: "doc.text",
                            title: "REPORT REPS",
                            action: {}
                        )
                        
                        ActionButton(
                            icon: "speaker.wave.2",
                            title: "HEAR GUIDE",
                            action: {}
                        )
                        
                        ActionButton(
                            icon: "clock.arrow.circlepath",
                            title: "EXERCISE HISTORY",
                            action: {}
                        )
                    }
                    .frame(maxWidth: .infinity)
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
                let seconds = String(exercise.reps.dropFirst())
                return "\(seconds) seconds"
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

// MARK: - Action Button

/// Action button displayed in expanded exercise view.
/// Used for "REPORT REPS", "HEAR GUIDE", and "EXERCISE HISTORY" actions.
///
/// Features:
/// - Equal width and height (minHeight: 80) for consistent sizing
/// - Icon and two-line title with proper text wrapping
/// - Dark background matching app theme
private struct ActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.textPrimary)
                
                Text(title)
                    .font(.neueMontrealSemiBold(size: 11))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.06))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    WorkoutProgressionView(workout: WorkoutLibrary.pythonWrangler)
        .preferredColorScheme(.dark)
}
