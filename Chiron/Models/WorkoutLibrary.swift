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
        carbonPull
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
