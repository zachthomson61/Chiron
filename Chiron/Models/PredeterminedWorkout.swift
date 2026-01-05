//
//  PredeterminedWorkout.swift
//  Chiron
//
//  Model for predetermined/preloaded workouts in the workout library
//

import Foundation

/// Represents a predetermined workout available in the workout library.
/// These are pre-built workouts that users can select and start immediately.
struct PredeterminedWorkout: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let duration: Int // minutes
    let difficulty: DifficultyLevel
    let exercises: [WorkoutExercise]
    let equipment: [String]
    let videoName: String?
    let category: String // e.g., "Arm", "Legs", "Full Body"
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        duration: Int,
        difficulty: DifficultyLevel,
        exercises: [WorkoutExercise],
        equipment: [String],
        videoName: String? = nil,
        category: String
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.duration = duration
        self.difficulty = difficulty
        self.exercises = exercises
        self.equipment = equipment
        self.videoName = videoName
        self.category = category
    }
}

