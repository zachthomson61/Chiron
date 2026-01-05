//
//  WorkoutProgressionView.swift
//  Chiron
//
//  Sheet view displaying the full workout progression with all exercises
//

import SwiftUI

/// Sheet view that displays the complete workout progression with all exercises,
/// sets, reps, and rest times. Presented when the list button is tapped in WorkoutIntroView.
struct WorkoutProgressionView: View {
    let workout: PredeterminedWorkout
    @Environment(\.dismiss) private var dismiss
    @State private var expandedExerciseId: UUID?
    @State private var expandedPhases: Set<String> = []
    
    // Get all exercises in order
    private var allExercises: [WorkoutExercise] {
        workout.exercises
    }
    
    // Group exercises by phase
    private var exercisesByPhase: [String: [WorkoutExercise]] {
        Dictionary(grouping: workout.exercises) { exercise in
            exercise.phase ?? "Main Workout"
        }
    }
    
    // Get index of an exercise in the full workout
    private func exerciseIndex(_ exercise: WorkoutExercise) -> Int {
        allExercises.firstIndex(where: { $0.id == exercise.id }) ?? 0
    }
    
    // Ordered phases (specific order for workout structure)
    private var phaseOrder: [String] {
        let phases = Array(exercisesByPhase.keys)
        let ordered = [
            "Warm-up",
            "Explosive Tricep Primer",
            "Explosive Bicep Primer",
            "Superset 1",
            "Superset 2",
            "Finisher",
            "Cool Down"
        ]
        let orderedPhases = ordered.filter { phases.contains($0) }
        let remainingPhases = phases.filter { !ordered.contains($0) }.sorted()
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
                                            exerciseIndex: exerciseIndex(exercise),
                                            workout: workout,
                                            isExpanded: expandedExerciseId == exercise.id,
                                            onTap: {
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
    
    // Calculate phase duration in minutes from exercises
    private func calculatePhaseDuration(_ exercises: [WorkoutExercise]) -> Int {
        let totalSeconds = exercises.reduce(0) { total, exercise in
            // Estimate work time per set (simplified: ~45 seconds for compound, ~30 for isolation/mobility)
            let workTimePerSet: Int
            switch exercise.category {
            case .compound:
                workTimePerSet = 45
            case .mobility:
                workTimePerSet = 20
            default:
                workTimePerSet = 30
            }
            
            // Calculate total work time
            let totalWorkTime = workTimePerSet * exercise.sets
            
            // Calculate rest time (rest between sets, not after last set)
            let totalRestTime = exercise.restTime * max(0, exercise.sets - 1)
            
            // Add transition time (30 seconds per exercise)
            let transitionTime = 30
            
            return total + totalWorkTime + totalRestTime + transitionTime
        }
        
        // Convert to minutes, rounding up
        return max(1, Int(ceil(Double(totalSeconds) / 60.0)))
    }
    
    // Get number of rounds for a phase (if applicable)
    private func getRoundsForPhase(_ phase: String, exercises: [WorkoutExercise]) -> Int? {
        // Count unique exercise names (excluding Rest) to determine rounds
        let uniqueExercises = Set(exercises.filter { $0.name != "Rest" }.map { $0.name })
        if uniqueExercises.count > 0 {
            let exerciseCount = exercises.filter { $0.name != "Rest" }.count
            return exerciseCount / uniqueExercises.count
        }
        return nil
    }
    
    // Check if phase has rounds structure
    private func hasRounds(_ phase: String, exercises: [WorkoutExercise]) -> Bool {
        if let rounds = getRoundsForPhase(phase, exercises: exercises), rounds > 1 {
            return true
        }
        return false
    }
    
    // Get exercises to show (first round or all rounds)
    private func getExercisesToShow(for phase: String, exercises: [WorkoutExercise]) -> [WorkoutExercise] {
        if hasRounds(phase, exercises: exercises) && !expandedPhases.contains(phase) {
            // Find unique exercise names (excluding Rest) to determine round structure
            let uniqueExerciseNames = Set(exercises.filter { $0.name != "Rest" }.map { $0.name })
            let exercisesPerRound = uniqueExerciseNames.count
            
            // Get all exercises up to and including the first Rest
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
        // Show all exercises
        return exercises
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

/// Bar component displaying phase name and duration, matching the reference design.
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
/// When expanded, shows video player, action buttons, and next exercise preview.
private struct WorkoutProgressionExerciseRow: View {
    let exercise: WorkoutExercise
    let exerciseIndex: Int
    let workout: PredeterminedWorkout
    let isExpanded: Bool
    let onTap: () -> Void
    
    // Get video name for exercise (placeholder for now)
    private var videoName: String {
        return "bodyweight_squat_demo" // Placeholder
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
    
    // Format reps details similar to reference: ":30 • Slow Tempo" or ":30 • Right Side"
    private func formatRepsDetails() -> String {
        // For Rest cards, convert ":45" to "45 seconds"
        if exercise.name == "Rest" {
            if exercise.reps.hasPrefix(":") {
                let seconds = String(exercise.reps.dropFirst())
                return "\(seconds) seconds"
            }
            return exercise.reps
        }
        
        var details: [String] = []
        
        // Format reps - if it starts with ":", it's a duration format like ":30"
        if exercise.reps.hasPrefix(":") {
            details.append(exercise.reps)
        } else if exercise.reps.lowercased().contains("s") || exercise.reps.lowercased().contains("min") {
            // Time-based, show sets × time or just time
            if exercise.sets > 1 {
                details.append("\(exercise.sets) × \(exercise.reps)")
            } else {
                details.append(exercise.reps)
            }
        } else if exercise.reps.contains("-") {
            // Range format like "8-12"
            if exercise.sets > 1 {
                details.append("\(exercise.sets) × \(exercise.reps) reps")
            } else {
                details.append("\(exercise.reps) reps")
            }
        } else {
            // Simple rep count
            if exercise.sets > 1 {
                details.append("\(exercise.sets) × \(exercise.reps) reps")
            } else {
                details.append("\(exercise.reps) reps")
            }
        }
        
        // Add notes information (Slow Tempo, Right Side, Left Side, etc.)
        if let notes = exercise.notes, !notes.isEmpty {
            details.append(notes)
        }
        
        return details.joined(separator: " • ")
    }
}

// MARK: - Video Player Area

private struct VideoPlayerArea: View {
    let videoName: String
    
    var body: some View {
        ZStack {
            // Landscape video player (16:9 aspect ratio) - full width
            if let url = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
                GeometryReader { geometry in
                    LoopingVideoView(url: url)
                        .frame(width: geometry.size.width, height: geometry.size.width * 9 / 16)
                        .clipped()
                }
                .aspectRatio(16/9, contentMode: .fit)
            } else {
                // Placeholder background if video not found
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
