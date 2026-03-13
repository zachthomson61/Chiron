//
//  WorkoutLibrary.swift
//  Chiron
//
//  Static data source for predetermined workouts in the workout library.
//  Contains workout definitions with exercises organized by phases.
//

import Foundation

/// Provides access to predetermined workouts available in the workout library.
///
/// Workouts are organized into phases:
/// - **Warm-up**: Mobility exercises to prepare for the workout
/// - **Explosive Primers**: Power-focused exercises with short rest periods (45 seconds)
/// - **Supersets**: Paired exercises performed back-to-back with rest between rounds (90 seconds)
/// - **Finisher**: High-intensity final exercises
/// - **Cool Down**: Stretching and mobility exercises
///
/// Each exercise can have a `phase` property that groups it with other exercises.
/// Phases with multiple rounds (e.g., "3 ROUNDS") will show a "Show All Rounds" button
/// to expand and view all rounds in the workout progression view.
struct WorkoutLibrary {
    /// All available predetermined workouts.
    static let workouts: [PredeterminedWorkout] = [
        pythonWrangler,
        carbonPull,
        carbonPush,
        carbonLegs,
        atlasProtocolA
    ]

    /// Carbon Pull - 60-minute High-Intensity Pull
    static let carbonPull = PredeterminedWorkout(
        name: "Carbon Pull",
        description: "High-Intensity Pull •\nFat Loss Focus",
        duration: 60,
        difficulty: .intermediate,
        exercises: carbonPullExercises,
        equipment: [
            "Cable Machine",
            "Dumbbells",
            "Preacher Bench (optional)"
        ],
        videoName: "BarbellRow",
        category: "Back"
    )

    /// Carbon Pull workout: Warm-up, Vertical Pull, Horizontal Row, Rear Delt, Brachialis, Long Head Bicep, Trap Work, Cool Down.
    private static let carbonPullExercises: [WorkoutExercise] = [
        // Warm-up (same 8 as Python Wrangler)
        WorkoutExercise(
            name: "Cross-Body Arm Swings",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Slow Tempo",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Arm Circles",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Slow Tempo",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Thread the Needle",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Thread the Needle",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Overhead Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Overhead Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Warm-up"
        ),
        // Vertical Pull - Camera Setup
        WorkoutExercise(
            name: "Neutral Grip Cable Pulldown",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Vertical Pull"
        ),
        // Vertical Pull - 2 rounds
        WorkoutExercise(
            name: "Neutral Grip Cable Pulldown",
            category: .compound,
            sets: 1,
            reps: "6-8",
            restTime: 0,
            notes: nil,
            phase: "Vertical Pull"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":180",
            restTime: 0,
            notes: nil,
            phase: "Vertical Pull"
        ),
        WorkoutExercise(
            name: "Neutral Grip Cable Pulldown",
            category: .compound,
            sets: 1,
            reps: "6-8",
            restTime: 0,
            notes: nil,
            phase: "Vertical Pull"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":180",
            restTime: 0,
            notes: nil,
            phase: "Vertical Pull"
        ),
        // Horizontal Row - Camera Setup
        WorkoutExercise(
            name: "Close-Grip Cable Row",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Horizontal Row"
        ),
        // Horizontal Row - 2 rounds
        WorkoutExercise(
            name: "Close-Grip Cable Row",
            category: .compound,
            sets: 1,
            reps: "8-10",
            restTime: 0,
            notes: nil,
            phase: "Horizontal Row"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":120",
            restTime: 0,
            notes: nil,
            phase: "Horizontal Row"
        ),
        WorkoutExercise(
            name: "Close-Grip Cable Row",
            category: .compound,
            sets: 1,
            reps: "8-10",
            restTime: 0,
            notes: nil,
            phase: "Horizontal Row"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":120",
            restTime: 0,
            notes: nil,
            phase: "Horizontal Row"
        ),
        // Rear Delt Work - Camera Setup
        WorkoutExercise(
            name: "Reverse Cable Fly",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Rear Delt Work"
        ),
        // Rear Delt Work - 2 rounds
        WorkoutExercise(
            name: "Reverse Cable Fly",
            category: .isolation,
            sets: 1,
            reps: "12-15",
            restTime: 0,
            notes: nil,
            phase: "Rear Delt Work"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":60",
            restTime: 0,
            notes: nil,
            phase: "Rear Delt Work"
        ),
        WorkoutExercise(
            name: "Reverse Cable Fly",
            category: .isolation,
            sets: 1,
            reps: "12-15",
            restTime: 0,
            notes: nil,
            phase: "Rear Delt Work"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":60",
            restTime: 0,
            notes: nil,
            phase: "Rear Delt Work"
        ),
        // Brachialis Bicep Work - Camera Setup
        WorkoutExercise(
            name: "Hammer Preacher Curl",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Brachialis Bicep Work"
        ),
        // Brachialis Bicep Work - 2 rounds
        WorkoutExercise(
            name: "Hammer Preacher Curl",
            category: .isolation,
            sets: 1,
            reps: "8-12",
            restTime: 0,
            notes: nil,
            phase: "Brachialis Bicep Work"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":90",
            restTime: 0,
            notes: nil,
            phase: "Brachialis Bicep Work"
        ),
        WorkoutExercise(
            name: "Hammer Preacher Curl",
            category: .isolation,
            sets: 1,
            reps: "8-12",
            restTime: 0,
            notes: nil,
            phase: "Brachialis Bicep Work"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":90",
            restTime: 0,
            notes: nil,
            phase: "Brachialis Bicep Work"
        ),
        // Long Head Bicep Work - Camera Setup
        WorkoutExercise(
            name: "Incline DB Curl",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Long Head Bicep Work"
        ),
        // Long Head Bicep Work - 2 rounds
        WorkoutExercise(
            name: "Incline DB Curl",
            category: .isolation,
            sets: 1,
            reps: "10-15",
            restTime: 0,
            notes: nil,
            phase: "Long Head Bicep Work"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":60",
            restTime: 0,
            notes: nil,
            phase: "Long Head Bicep Work"
        ),
        WorkoutExercise(
            name: "Incline DB Curl",
            category: .isolation,
            sets: 1,
            reps: "10-15",
            restTime: 0,
            notes: nil,
            phase: "Long Head Bicep Work"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":60",
            restTime: 0,
            notes: nil,
            phase: "Long Head Bicep Work"
        ),
        // Trap Work - Camera Setup
        WorkoutExercise(
            name: "Wide Cable Shrug-In",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Trap Work"
        ),
        // Trap Work - 1 round
        WorkoutExercise(
            name: "Wide Cable Shrug-In",
            category: .compound,
            sets: 1,
            reps: "8-12",
            restTime: 0,
            notes: nil,
            phase: "Trap Work"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":120",
            restTime: 0,
            notes: nil,
            phase: "Trap Work"
        ),
        // Cool Down (same 4 as Python Wrangler)
        WorkoutExercise(
            name: "Cross-body Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Cool Down"
        ),
        WorkoutExercise(
            name: "Cross-body Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Cool Down"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Cool Down"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Cool Down"
        )
    ]

    /// Carbon Push - 60-minute High-Intensity Push
    ///
    /// Workout Structure:
    /// - Warm-up: 8 mobility exercises (same as Carbon Pull)
    /// - 45˚ Smith Incline Bench: 2 rounds with 3-minute rest
    /// - WEIGHTED DIPS (WIDE GRIP): 2 rounds with 3-minute rest
    /// - Machine Shoulder Press: 2 rounds with 2-minute rest
    /// - Pec Deck: 2 rounds with 1-minute rest
    /// - Cuffed BTB Cable Lat Raise: 2 rounds with 1-minute rest
    /// - Triceps: 1 camera setup, then Straight Bar Overhead Cable Tricep Extension, Straight Bar Cable Tricep Pushdown, Rest
    /// - Cool Down: 4 stretches (same as Carbon Pull)
    static let carbonPush = PredeterminedWorkout(
        name: "Carbon Push",
        description: "High-Intensity Push •\nFat Loss Focus",
        duration: 60,
        difficulty: .intermediate,
        exercises: carbonPushExercises,
        equipment: [
            "Smith Machine",
            "Dip Station",
            "Shoulder Press Machine",
            "Cable Machine"
        ],
        videoName: "BarbellRow",
        category: "Chest"
    )

    /// Carbon Push exercises: Warm-up, 45˚ Smith Incline Bench, Weighted Dips, Machine Shoulder Press,
    /// Pec Deck, Cuffed BTB Cable Lat Raise, Triceps, Cool Down.
    private static let carbonPushExercises: [WorkoutExercise] = [
        // Warm-up (same 8 as Carbon Pull)
        WorkoutExercise(
            name: "Cross-Body Arm Swings",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Slow Tempo",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Arm Circles",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Slow Tempo",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Thread the Needle",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Thread the Needle",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Overhead Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Overhead Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Warm-up"
        ),
        // 45˚ Smith Incline Bench - Camera Setup
        WorkoutExercise(
            name: "45˚ Smith Incline Bench",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "45˚ Smith Incline Bench"
        ),
        // 45˚ Smith Incline Bench - 2 rounds
        WorkoutExercise(
            name: "45˚ Smith Incline Bench",
            category: .compound,
            sets: 1,
            reps: "4-6",
            restTime: 0,
            notes: nil,
            phase: "45˚ Smith Incline Bench"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":180",
            restTime: 0,
            notes: nil,
            phase: "45˚ Smith Incline Bench"
        ),
        WorkoutExercise(
            name: "45˚ Smith Incline Bench",
            category: .compound,
            sets: 1,
            reps: "4-6",
            restTime: 0,
            notes: nil,
            phase: "45˚ Smith Incline Bench"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":180",
            restTime: 0,
            notes: nil,
            phase: "45˚ Smith Incline Bench"
        ),
        // WEIGHTED DIPS (WIDE GRIP) - Camera Setup
        WorkoutExercise(
            name: "WEIGHTED DIPS (WIDE GRIP)",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "WEIGHTED DIPS (WIDE GRIP)"
        ),
        // WEIGHTED DIPS (WIDE GRIP) - 2 rounds
        WorkoutExercise(
            name: "WEIGHTED DIPS (WIDE GRIP)",
            category: .compound,
            sets: 1,
            reps: "5-6",
            restTime: 0,
            notes: nil,
            phase: "WEIGHTED DIPS (WIDE GRIP)"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":180",
            restTime: 0,
            notes: nil,
            phase: "WEIGHTED DIPS (WIDE GRIP)"
        ),
        WorkoutExercise(
            name: "WEIGHTED DIPS (WIDE GRIP)",
            category: .compound,
            sets: 1,
            reps: "5-6",
            restTime: 0,
            notes: nil,
            phase: "WEIGHTED DIPS (WIDE GRIP)"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":180",
            restTime: 0,
            notes: nil,
            phase: "WEIGHTED DIPS (WIDE GRIP)"
        ),
        // Machine Shoulder Press - Camera Setup
        WorkoutExercise(
            name: "Machine Shoulder Press",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Machine Shoulder Press"
        ),
        // Machine Shoulder Press - 2 rounds
        WorkoutExercise(
            name: "Machine Shoulder Press",
            category: .compound,
            sets: 1,
            reps: "9-12",
            restTime: 0,
            notes: nil,
            phase: "Machine Shoulder Press"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":120",
            restTime: 0,
            notes: nil,
            phase: "Machine Shoulder Press"
        ),
        WorkoutExercise(
            name: "Machine Shoulder Press",
            category: .compound,
            sets: 1,
            reps: "9-12",
            restTime: 0,
            notes: nil,
            phase: "Machine Shoulder Press"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":120",
            restTime: 0,
            notes: nil,
            phase: "Machine Shoulder Press"
        ),
        // Pec Deck - Camera Setup
        WorkoutExercise(
            name: "Pec Deck",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Pec Deck"
        ),
        // Pec Deck - 2 rounds
        WorkoutExercise(
            name: "Pec Deck",
            category: .isolation,
            sets: 1,
            reps: "12-13",
            restTime: 0,
            notes: nil,
            phase: "Pec Deck"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":60",
            restTime: 0,
            notes: nil,
            phase: "Pec Deck"
        ),
        WorkoutExercise(
            name: "Pec Deck",
            category: .isolation,
            sets: 1,
            reps: "12-13",
            restTime: 0,
            notes: nil,
            phase: "Pec Deck"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":60",
            restTime: 0,
            notes: nil,
            phase: "Pec Deck"
        ),
        // Cuffed BTB Cable Lat Raise - Camera Setup
        WorkoutExercise(
            name: "Cuffed BTB Cable Lat Raise",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Cuffed BTB Cable Lat Raise"
        ),
        // Cuffed BTB Cable Lat Raise - 2 rounds
        WorkoutExercise(
            name: "Cuffed BTB Cable Lat Raise",
            category: .isolation,
            sets: 1,
            reps: "8-13",
            restTime: 0,
            notes: nil,
            phase: "Cuffed BTB Cable Lat Raise"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":60",
            restTime: 0,
            notes: nil,
            phase: "Cuffed BTB Cable Lat Raise"
        ),
        WorkoutExercise(
            name: "Cuffed BTB Cable Lat Raise",
            category: .isolation,
            sets: 1,
            reps: "8-13",
            restTime: 0,
            notes: nil,
            phase: "Cuffed BTB Cable Lat Raise"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":60",
            restTime: 0,
            notes: nil,
            phase: "Cuffed BTB Cable Lat Raise"
        ),
        // Triceps - Camera Setup (single card titled "Triceps")
        WorkoutExercise(
            name: "Triceps",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Triceps"
        ),
        // Triceps - Straight Bar Overhead Cable Tricep Extension, Straight Bar Cable Tricep Pushdown, Rest
        WorkoutExercise(
            name: "Straight Bar Overhead Cable Tricep Extension",
            category: .isolation,
            sets: 1,
            reps: "10-11",
            restTime: 0,
            notes: nil,
            phase: "Triceps"
        ),
        WorkoutExercise(
            name: "Straight Bar Cable Tricep Pushdown",
            category: .isolation,
            sets: 1,
            reps: "8-10",
            restTime: 0,
            notes: nil,
            phase: "Triceps"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":120",
            restTime: 0,
            notes: nil,
            phase: "Triceps"
        ),
        // Cool Down (same 4 as Carbon Pull)
        WorkoutExercise(
            name: "Cross-body Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Cool Down"
        ),
        WorkoutExercise(
            name: "Cross-body Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Cool Down"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Cool Down"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Cool Down"
        )
    ]

    /// Carbon Legs - 60-minute High-Intensity Leg Workout
    ///
    /// Workout Structure:
    /// - Warm-up: 8 mobility exercises (same as Carbon Pull)
    /// - Low Bar Smith Squat (Glute Emphasis): 2 rounds with 3-minute rest
    /// - RDL: 2 rounds with 3-minute rest
    /// - Leg Extensions: 2 rounds with 2-minute rest
    /// - Sitting Leg Curl: 2 rounds with 2-minute rest
    /// - Hip Thrust (A) / Machine Leg Abduction (B) / Goblet Lateral Squat (C): 1 round each (A/B/C rotation per session)
    /// - Standing Calf Raise: 1 round
    /// - Cool Down: 4 stretches (same as Carbon Pull)
    static let carbonLegs = PredeterminedWorkout(
        name: "Carbon Legs",
        description: "High-Intensity Legs •\nFat Loss Focus",
        duration: 60,
        difficulty: .intermediate,
        exercises: carbonLegsExercises,
        equipment: [
            "Smith Machine",
            "Barbell",
            "Leg Extension Machine",
            "Leg Curl Machine",
            "Hip Thrust Setup",
            "Leg Abduction Machine",
            "Calf Raise Machine",
            "Dumbbell"
        ],
        videoName: "BarbellRow",
        category: "Legs"
    )

    /// Carbon Legs exercises: Warm-up, Low Bar Smith Squat, RDL, Leg Extensions, Sitting Leg Curl,
    /// Hip Thrust (A) / Machine Leg Abduction (B) / Goblet Lateral Squat (C), Standing Calf Raise, Cool Down.
    private static let carbonLegsExercises: [WorkoutExercise] = [
        // Warm-up (same 8 as Carbon Pull)
        WorkoutExercise(
            name: "Cross-Body Arm Swings",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Slow Tempo",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Arm Circles",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Slow Tempo",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Thread the Needle",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Thread the Needle",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Overhead Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Overhead Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Warm-up"
        ),
        // Low Bar Smith Squat (Glute Emphasis) - Camera Setup
        WorkoutExercise(
            name: "Low Bar Smith Squat (Glute Emphasis)",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Low Bar Smith Squat"
        ),
        // Low Bar Smith Squat (Glute Emphasis) - 2 rounds
        WorkoutExercise(
            name: "Low Bar Smith Squat (Glute Emphasis)",
            category: .compound,
            sets: 1,
            reps: "10-13",
            restTime: 0,
            notes: nil,
            phase: "Low Bar Smith Squat"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":180",
            restTime: 0,
            notes: nil,
            phase: "Low Bar Smith Squat"
        ),
        WorkoutExercise(
            name: "Low Bar Smith Squat (Glute Emphasis)",
            category: .compound,
            sets: 1,
            reps: "10-13",
            restTime: 0,
            notes: nil,
            phase: "Low Bar Smith Squat"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":180",
            restTime: 0,
            notes: nil,
            phase: "Low Bar Smith Squat"
        ),
        // RDL - Camera Setup
        WorkoutExercise(
            name: "RDL",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "RDL"
        ),
        // RDL - 2 rounds
        WorkoutExercise(
            name: "RDL",
            category: .compound,
            sets: 1,
            reps: "10-13",
            restTime: 0,
            notes: nil,
            phase: "RDL"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":180",
            restTime: 0,
            notes: nil,
            phase: "RDL"
        ),
        WorkoutExercise(
            name: "RDL",
            category: .compound,
            sets: 1,
            reps: "10-13",
            restTime: 0,
            notes: nil,
            phase: "RDL"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":180",
            restTime: 0,
            notes: nil,
            phase: "RDL"
        ),
        // Leg Extensions - Camera Setup
        WorkoutExercise(
            name: "Leg Extensions",
            category: .isolation,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Leg Extensions"
        ),
        // Leg Extensions - 2 rounds
        WorkoutExercise(
            name: "Leg Extensions",
            category: .isolation,
            sets: 1,
            reps: "12-15",
            restTime: 0,
            notes: nil,
            phase: "Leg Extensions"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":120",
            restTime: 0,
            notes: nil,
            phase: "Leg Extensions"
        ),
        WorkoutExercise(
            name: "Leg Extensions",
            category: .isolation,
            sets: 1,
            reps: "12-15",
            restTime: 0,
            notes: nil,
            phase: "Leg Extensions"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":120",
            restTime: 0,
            notes: nil,
            phase: "Leg Extensions"
        ),
        // Sitting Leg Curl - Camera Setup
        WorkoutExercise(
            name: "Sitting Leg Curl",
            category: .isolation,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Sitting Leg Curl"
        ),
        // Sitting Leg Curl - 2 rounds
        WorkoutExercise(
            name: "Sitting Leg Curl",
            category: .isolation,
            sets: 1,
            reps: "10-12",
            restTime: 0,
            notes: nil,
            phase: "Sitting Leg Curl"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":120",
            restTime: 0,
            notes: nil,
            phase: "Sitting Leg Curl"
        ),
        WorkoutExercise(
            name: "Sitting Leg Curl",
            category: .isolation,
            sets: 1,
            reps: "10-12",
            restTime: 0,
            notes: nil,
            phase: "Sitting Leg Curl"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":120",
            restTime: 0,
            notes: nil,
            phase: "Sitting Leg Curl"
        ),
        // Hip Thrust (A) - Camera Setup
        WorkoutExercise(
            name: "Hip Thrust (A)",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Hip Thrust (A)"
        ),
        // Hip Thrust (A) - 1 round
        WorkoutExercise(
            name: "Hip Thrust (A)",
            category: .compound,
            sets: 1,
            reps: "10-12",
            restTime: 0,
            notes: nil,
            phase: "Hip Thrust (A)"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":120",
            restTime: 0,
            notes: nil,
            phase: "Hip Thrust (A)"
        ),
        // Machine Leg Abduction (B) - Camera Setup
        WorkoutExercise(
            name: "Machine Leg Abduction (B)",
            category: .isolation,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Machine Leg Abduction (B)"
        ),
        // Machine Leg Abduction (B) - 1 round
        WorkoutExercise(
            name: "Machine Leg Abduction (B)",
            category: .isolation,
            sets: 1,
            reps: "15-20",
            restTime: 0,
            notes: nil,
            phase: "Machine Leg Abduction (B)"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":90",
            restTime: 0,
            notes: nil,
            phase: "Machine Leg Abduction (B)"
        ),
        // Goblet Lateral Squat (C) - Camera Setup
        WorkoutExercise(
            name: "Goblet Lateral Squat (C)",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Goblet Lateral Squat (C)"
        ),
        // Goblet Lateral Squat (C) - 1 round
        WorkoutExercise(
            name: "Goblet Lateral Squat (C)",
            category: .compound,
            sets: 1,
            reps: "10-12",
            restTime: 0,
            notes: nil,
            phase: "Goblet Lateral Squat (C)"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":120",
            restTime: 0,
            notes: nil,
            phase: "Goblet Lateral Squat (C)"
        ),
        // Standing Calf Raise - Camera Setup
        WorkoutExercise(
            name: "Standing Calf Raise",
            category: .isolation,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Standing Calf Raise"
        ),
        // Standing Calf Raise - 1 round
        WorkoutExercise(
            name: "Standing Calf Raise",
            category: .isolation,
            sets: 1,
            reps: "10-15",
            restTime: 0,
            notes: nil,
            phase: "Standing Calf Raise"
        ),
        // Cool Down (same 4 as Carbon Pull)
        WorkoutExercise(
            name: "Cross-body Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Cool Down"
        ),
        WorkoutExercise(
            name: "Cross-body Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Cool Down"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Cool Down"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Cool Down"
        )
    ]

    /// Exercise names used for A/B/C rotation filtering in Carbon Legs.
    /// Session A = Hip Thrust, Session B = Machine Leg Abduction, Session C = Goblet Lateral Squat.
    static let carbonLegsRotationExercises: [String: [String]] = [
        "A": ["Machine Leg Abduction (B)", "Goblet Lateral Squat (C)"],
        "B": ["Hip Thrust (A)", "Goblet Lateral Squat (C)"],
        "C": ["Hip Thrust (A)", "Machine Leg Abduction (B)"]
    ]
    
    /// Returns the exercise name for display on cards, stripping the " (A)", " (B)", " (C)" suffix
    /// so section titles keep the letter but card titles do not.
    static func exerciseDisplayName(_ name: String) -> String {
        if name.hasSuffix(" (A)") { return String(name.dropLast(4)) }
        if name.hasSuffix(" (B)") { return String(name.dropLast(4)) }
        if name.hasSuffix(" (C)") { return String(name.dropLast(4)) }
        return name
    }

    /// Shared exercise list for arm-focused predetermined workouts (Python Wrangler only).
    private static let armWorkoutExercises: [WorkoutExercise] = [
        // Warm-up exercises
        WorkoutExercise(
            name: "Cross-Body Arm Swings",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Slow Tempo",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Arm Circles",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Slow Tempo",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Thread the Needle",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Thread the Needle",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Overhead Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Overhead Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Warm-up"
        ),
        // Explosive Tricep Primer - Camera Setup for Close-Grip Bench Press
        WorkoutExercise(
            name: "Close-Grip Bench Press",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Explosive Tricep Primer"
        ),
        WorkoutExercise(
            name: "Close-Grip Bench Press",
            category: .compound,
            sets: 1,
            reps: "6-8",
            restTime: 120,
            notes: "Explosive tempo",
            phase: "Explosive Tricep Primer"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":45",
            restTime: 0,
            notes: nil,
            phase: "Explosive Tricep Primer"
        ),
        WorkoutExercise(
            name: "Close-Grip Bench Press",
            category: .compound,
            sets: 1,
            reps: "6-8",
            restTime: 120,
            notes: "Explosive tempo",
            phase: "Explosive Tricep Primer"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":45",
            restTime: 0,
            notes: nil,
            phase: "Explosive Tricep Primer"
        ),
        WorkoutExercise(
            name: "Close-Grip Bench Press",
            category: .compound,
            sets: 1,
            reps: "6-8",
            restTime: 120,
            notes: "Explosive tempo",
            phase: "Explosive Tricep Primer"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":45",
            restTime: 0,
            notes: nil,
            phase: "Explosive Tricep Primer"
        ),
        // Explosive Bicep Primer - Camera Setup for Alternating DB Curls
        WorkoutExercise(
            name: "Alternating DB Curls",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Explosive Bicep Primer"
        ),
        WorkoutExercise(
            name: "Alternating DB Curls",
            category: .isolation,
            sets: 1,
            reps: "6-8",
            restTime: 90,
            notes: "Explosive tempo",
            phase: "Explosive Bicep Primer"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":45",
            restTime: 0,
            notes: nil,
            phase: "Explosive Bicep Primer"
        ),
        WorkoutExercise(
            name: "Alternating DB Curls",
            category: .isolation,
            sets: 1,
            reps: "6-8",
            restTime: 90,
            notes: "Explosive tempo",
            phase: "Explosive Bicep Primer"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":45",
            restTime: 0,
            notes: nil,
            phase: "Explosive Bicep Primer"
        ),
        WorkoutExercise(
            name: "Alternating DB Curls",
            category: .isolation,
            sets: 1,
            reps: "6-8",
            restTime: 90,
            notes: "Explosive tempo",
            phase: "Explosive Bicep Primer"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":45",
            restTime: 0,
            notes: nil,
            phase: "Explosive Bicep Primer"
        ),
        // Superset 1 - Exercise Selection + Camera Setup
        WorkoutExercise(
            name: "Superset 1",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "EXERCISE_SELECTION|Incline DB Curl|Rope Tricep Pushdown",
            phase: "Superset 1"
        ),
        WorkoutExercise(
            name: "Superset 1",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Superset 1"
        ),
        WorkoutExercise(
            name: "Incline DB Curl",
            category: .isolation,
            sets: 1,
            reps: "10-12",
            restTime: 0,
            notes: nil,
            phase: "Superset 1"
        ),
        WorkoutExercise(
            name: "Rope Tricep Pushdown",
            category: .isolation,
            sets: 1,
            reps: "10-12",
            restTime: 0,
            notes: nil,
            phase: "Superset 1"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":90",
            restTime: 0,
            notes: nil,
            phase: "Superset 1"
        ),
        WorkoutExercise(
            name: "Incline DB Curl",
            category: .isolation,
            sets: 1,
            reps: "10-12",
            restTime: 0,
            notes: nil,
            phase: "Superset 1"
        ),
        WorkoutExercise(
            name: "Rope Tricep Pushdown",
            category: .isolation,
            sets: 1,
            reps: "10-12",
            restTime: 0,
            notes: nil,
            phase: "Superset 1"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":90",
            restTime: 0,
            notes: nil,
            phase: "Superset 1"
        ),
        WorkoutExercise(
            name: "Incline DB Curl",
            category: .isolation,
            sets: 1,
            reps: "10-12",
            restTime: 0,
            notes: nil,
            phase: "Superset 1"
        ),
        WorkoutExercise(
            name: "Rope Tricep Pushdown",
            category: .isolation,
            sets: 1,
            reps: "10-12",
            restTime: 0,
            notes: nil,
            phase: "Superset 1"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":90",
            restTime: 0,
            notes: nil,
            phase: "Superset 1"
        ),
        // Superset 2 - Exercise Selection + Camera Setup
        WorkoutExercise(
            name: "Superset 2",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "EXERCISE_SELECTION|EZ-Bar Drag Curl|Overhead Rope Extension",
            phase: "Superset 2"
        ),
        WorkoutExercise(
            name: "Superset 2",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Superset 2"
        ),
        WorkoutExercise(
            name: "EZ-Bar Drag Curl",
            category: .isolation,
            sets: 1,
            reps: "10-12",
            restTime: 0,
            notes: nil,
            phase: "Superset 2"
        ),
        WorkoutExercise(
            name: "Overhead Rope Extension",
            category: .isolation,
            sets: 1,
            reps: "10-12",
            restTime: 0,
            notes: nil,
            phase: "Superset 2"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":90",
            restTime: 0,
            notes: nil,
            phase: "Superset 2"
        ),
        WorkoutExercise(
            name: "EZ-Bar Drag Curl",
            category: .isolation,
            sets: 1,
            reps: "10-12",
            restTime: 0,
            notes: nil,
            phase: "Superset 2"
        ),
        WorkoutExercise(
            name: "Overhead Rope Extension",
            category: .isolation,
            sets: 1,
            reps: "10-12",
            restTime: 0,
            notes: nil,
            phase: "Superset 2"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":90",
            restTime: 0,
            notes: nil,
            phase: "Superset 2"
        ),
        WorkoutExercise(
            name: "EZ-Bar Drag Curl",
            category: .isolation,
            sets: 1,
            reps: "10-12",
            restTime: 0,
            notes: nil,
            phase: "Superset 2"
        ),
        WorkoutExercise(
            name: "Overhead Rope Extension",
            category: .isolation,
            sets: 1,
            reps: "10-12",
            restTime: 0,
            notes: nil,
            phase: "Superset 2"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":90",
            restTime: 0,
            notes: nil,
            phase: "Superset 2"
        ),
        // Finisher - Exercise Selection + Camera Setup
        WorkoutExercise(
            name: "Finisher",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "EXERCISE_SELECTION|Barbell Bicep Curl|Bench Dip|Hammer Curl Hold",
            phase: "Finisher"
        ),
        WorkoutExercise(
            name: "Finisher",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Finisher"
        ),
        WorkoutExercise(
            name: "Barbell Bicep Curl",
            category: .isolation,
            sets: 1,
            reps: ":21",
            restTime: 0,
            notes: nil,
            phase: "Finisher"
        ),
        WorkoutExercise(
            name: "Bench Dip",
            category: .isolation,
            sets: 1,
            reps: "10-12",
            restTime: 0,
            notes: nil,
            phase: "Finisher"
        ),
        WorkoutExercise(
            name: "Hammer Curl Hold",
            category: .isolation,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: nil,
            phase: "Finisher"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":90",
            restTime: 0,
            notes: nil,
            phase: "Finisher"
        ),
        // Cool Down
        WorkoutExercise(
            name: "Cross-body Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Cool Down"
        ),
        WorkoutExercise(
            name: "Cross-body Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Cool Down"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Cool Down"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Cool Down"
        )
    ]
    
    // MARK: - Atlas Protocol α

    /// Atlas Protocol α - Superset-based Push/Pull + Deadlift
    ///
    /// Workout Structure:
    /// - Warm-up: 8 mobility exercises (same as Carbon Pull)
    /// - Pec Deck: 1 set x 6-10 reps superset with Incline Smith Machine Press: 1 set x 6-10 reps
    /// - Machine Pullovers: 1 set x 6-10 reps superset with Close Grip Underhand Lat Pulldown: 1 set x 6-10 reps
    /// - Deadlift: 1 set x 6-10 reps
    /// - Cool Down: 4 stretches (same as Carbon Pull)
    static let atlasProtocolA = PredeterminedWorkout(
        name: "Atlas Protocol α",
        description: "High Intensity Full Body •\nMuscle building Focus",
        duration: 45,
        difficulty: .intermediate,
        exercises: atlasProtocolAExercises,
        equipment: [
            "Pec Deck Machine",
            "Smith Machine",
            "Pullover Machine",
            "Lat Pulldown Machine",
            "Barbell"
        ],
        videoName: "BarbellRow",
        category: "Full Body"
    )

    private static let atlasProtocolAExercises: [WorkoutExercise] = [
        // Warm-up (same 8 as Carbon Pull)
        WorkoutExercise(
            name: "Cross-Body Arm Swings",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Slow Tempo",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Arm Circles",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Slow Tempo",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Thread the Needle",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Thread the Needle",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Overhead Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Overhead Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Warm-up"
        ),
        WorkoutExercise(
            name: "Incline Smith Machine Press",
            category: .compound,
            sets: 1,
            reps: "5-8",
            restTime: 0,
            notes: nil,
            phase: "Warm-up"
        ),
        // Superset 1 - Exercise Selection + Camera Setup (Pec Deck / Incline Smith Machine Press)
        WorkoutExercise(
            name: "Superset 1",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "EXERCISE_SELECTION|Pec Deck|Incline Smith Machine Press",
            phase: "Superset 1"
        ),
        WorkoutExercise(
            name: "Superset 1",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Superset 1"
        ),
        WorkoutExercise(
            name: "Pec Deck",
            category: .isolation,
            sets: 1,
            reps: "6-10",
            restTime: 0,
            notes: nil,
            phase: "Superset 1"
        ),
        WorkoutExercise(
            name: "Incline Smith Machine Press",
            category: .compound,
            sets: 1,
            reps: "6-10",
            restTime: 0,
            notes: nil,
            phase: "Superset 1"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":90",
            restTime: 0,
            notes: nil,
            phase: "Superset 1"
        ),
        // Superset 2 - Exercise Selection + Camera Setup (Machine Pullovers / Close Grip Underhand Lat Pulldown)
        WorkoutExercise(
            name: "Superset 2",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "EXERCISE_SELECTION|Machine Pullovers|Close Grip Underhand Lat Pulldown",
            phase: "Superset 2"
        ),
        WorkoutExercise(
            name: "Superset 2",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Superset 2"
        ),
        WorkoutExercise(
            name: "Machine Pullovers",
            category: .compound,
            sets: 1,
            reps: "6-10",
            restTime: 0,
            notes: nil,
            phase: "Superset 2"
        ),
        WorkoutExercise(
            name: "Close Grip Underhand Lat Pulldown",
            category: .compound,
            sets: 1,
            reps: "6-10",
            restTime: 0,
            notes: nil,
            phase: "Superset 2"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":90",
            restTime: 0,
            notes: nil,
            phase: "Superset 2"
        ),
        // Deadlift - Camera Setup
        WorkoutExercise(
            name: "Deadlift",
            category: .compound,
            sets: 1,
            reps: "",
            restTime: 0,
            notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on floor 4-6 ft in front of bench|Angle slightly upwards|Center it on bar|Keep hands, elbows, and bar path in frame|TRIPOD|Place 2-3 ft in front of bench|Center on bar|Height at bar level or slightly above|Angle slightly down at grip|Ensure hands, elbows, and bar in view",
            phase: "Deadlift"
        ),
        // Deadlift - 1 set
        WorkoutExercise(
            name: "Deadlift",
            category: .compound,
            sets: 1,
            reps: "6-10",
            restTime: 0,
            notes: nil,
            phase: "Deadlift"
        ),
        WorkoutExercise(
            name: "Rest",
            category: .mobility,
            sets: 1,
            reps: ":120",
            restTime: 0,
            notes: nil,
            phase: "Deadlift"
        ),
        // Cool Down (same 4 as Carbon Pull)
        WorkoutExercise(
            name: "Cross-body Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Cool Down"
        ),
        WorkoutExercise(
            name: "Cross-body Tricep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Cool Down"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Right Side",
            phase: "Cool Down"
        ),
        WorkoutExercise(
            name: "Standing Wall Bicep Stretch",
            category: .mobility,
            sets: 1,
            reps: ":30",
            restTime: 0,
            notes: "Left Side",
            phase: "Cool Down"
        )
    ]

    /// Python Wrangler - 45-minute Explosive Hypertrophy Arm Workout
    ///
    /// Workout Structure:
    /// - Warm-up: 8 mobility exercises (30 seconds each)
    /// - Explosive Tricep Primer: 3 rounds of Close-Grip Bench Press with 45-second rest
    /// - Explosive Bicep Primer: 3 rounds of Alternating DB Curls with 45-second rest
    /// - Superset 1: 3 rounds of Incline DB Curl + Rope Tricep Pushdown with 90-second rest
    /// - Superset 2: 3 rounds of EZ-Bar Drag Curl + Overhead Rope Extension with 90-second rest
    /// - Finisher: Single round of Barbell Bicep Curl (21s), Bench Dip, Hammer Curl Hold, with 90-second rest
    /// - Cool Down: 4 stretches (Cross-body Tricep Stretch and Standing Wall Bicep Stretch, each side)
    static let pythonWrangler = PredeterminedWorkout(
        name: "Python Wrangler",
        description: "Explosive Muscle Building Arm Workout",
        duration: 45,
        difficulty: .intermediate,
        exercises: armWorkoutExercises,
        equipment: [
            "Barbell",
            "Dumbbells",
            "Cable Machine",
            "Bench",
            "Pull-Up Bar (optional)"
        ],
        videoName: "BarbellRow",
        category: "Arm"
    )
}
