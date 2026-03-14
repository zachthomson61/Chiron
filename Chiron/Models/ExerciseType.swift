//
//  ExerciseType.swift
//  Chiron
//
//  Exercise type enum for identifying which exercise the user is performing.
//  Used to adapt camera setup views, active workout views, and exercise-specific logic.
//
//  This enum provides a unified way to identify exercises across the app, allowing
//  the same camera setup and active workout views to adapt their behavior based on
//  the selected exercise type.
//

import Foundation

/// Exercise type identifier for adapting UI, pose detection, and coaching feedback.
/// 
/// Each exercise type provides:
/// - Display name for UI
/// - Button text for start/finish actions
/// - Audio cues for setup and workout start
/// - Mapping to TrackedExerciseType for pose detection
enum ExerciseType: String, CaseIterable {
    case bodyweightSquat = "bodyweight_squat"
    case barbellBackSquat = "barbell_back_squat"
    case barbellRow = "barbell_row"
    case deadlift = "deadlift"
    case romanianDeadlift = "romanian_deadlift"
    case barbellBenchPress = "barbell_bench_press"
    
    /// Maps to `TrackedExerciseType` for pose detection.
    var trackedExerciseType: TrackedExerciseType {
        switch self {
        case .bodyweightSquat:
            return .bodyweight
        case .barbellBackSquat:
            return .barbell
        case .barbellRow, .deadlift, .romanianDeadlift, .barbellBenchPress:
            return .bodyweight
        }
    }
    
    /// Display name for the exercise
    var displayName: String {
        switch self {
        case .bodyweightSquat:
            return "Bodyweight Squat"
        case .barbellBackSquat:
            return "Barbell Back Squat"
        case .barbellRow:
            return "Barbell Row"
        case .deadlift:
            return "Deadlift"
        case .romanianDeadlift:
            return "Romanian Deadlift"
        case .barbellBenchPress:
            return "Barbell Bench Press"
        }
    }
    
    /// Button text for starting the workout
    var startButtonText: String {
        switch self {
        case .bodyweightSquat:
            return "Start Bodyweight Squat"
        case .barbellBackSquat:
            return "Start Barbell Back Squat"
        case .barbellRow:
            return "Start Barbell Row"
        case .deadlift:
            return "Start Deadlift"
        case .romanianDeadlift:
            return "Start Romanian Deadlift"
        case .barbellBenchPress:
            return "Start Barbell Bench Press"
        }
    }
    
    /// Button text for finishing the workout
    var finishButtonText: String {
        switch self {
        case .bodyweightSquat:
            return "Finish Bodyweight Squat"
        case .barbellBackSquat:
            return "Finish Barbell Back Squat"
        case .barbellRow:
            return "Finish Barbell Row"
        case .deadlift:
            return "Finish Deadlift"
        case .romanianDeadlift:
            return "Finish Romanian Deadlift"
        case .barbellBenchPress:
            return "Finish Barbell Bench Press"
        }
    }
    
    /// Setup audio cue to play when camera setup view appears
    var setupAudioCue: String {
        switch self {
        case .bodyweightSquat:
            return "Go slow and controlled on the way down. Keep your chest tall and core tight"
        case .barbellBackSquat:
            return "Position the barbell across your upper traps. Keep the bar path vertical over mid foot. Brace your core before each descent"
        case .barbellRow:
            return "Position yourself with feet hip-width apart. Hinge at the hips and keep your spine neutral"
        case .deadlift:
            return "Position the bar over mid foot. Keep your chest up and spine neutral throughout the movement"
        case .romanianDeadlift:
            return "Stand tall with feet hip-width. Keep your knees slightly bent and maintain a neutral spine"
        case .barbellBenchPress:
            return "Position yourself on the bench with feet flat on the floor. Keep your shoulder blades retracted"
        }
    }
    
    /// Audio cue to play when starting the workout
    var startWorkoutAudioCue: String {
        return "Let's get it!"
    }
}

