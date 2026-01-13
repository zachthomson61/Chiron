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
        pythonWrangler
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
        exercises: [
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
                notes: "CAMERA_SETUP|RACK|Mount high on front rack post|Angle down at middle of bar|Center frame on bar + hands, not face|Keep full arm length and bar path visible|Avoid cropping at lockout or chest touch|FLOOR|Place phone on the floor in front of the bench|Set phone 6–8 ft back, angled Slightly upward|Center it on the barbell|Keep hands, elbows, and bar path fully in frame",
                phase: "Explosive Tricep Primer"
            ),
            // Explosive Tricep Primer - Round 1
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
            // Explosive Tricep Primer - Round 2
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
            // Explosive Tricep Primer - Round 3
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
            // Explosive Bicep Primer - Round 1
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
            // Explosive Bicep Primer - Round 2
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
            // Explosive Bicep Primer - Round 3
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
            // Superset 1 - Round 1
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
            // Superset 1 - Round 2
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
            // Superset 1 - Round 3
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
            // Superset 2 - Round 1
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
            // Superset 2 - Round 2
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
            // Superset 2 - Round 3
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
            // Finisher
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
        ],
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
