//
//  ExerciseSeeder.swift
//  Chiron
//
//  TrainingLog module - Exercise seeding service
//

import SwiftData

enum ExerciseSeeder {
    struct ExerciseData {
        let name: String
        let targetMuscles: String
        let difficulty: String
        let imageName: String
    }
    
    static let defaults: [ExerciseData] = [
        ExerciseData(name: "Back Squat", targetMuscles: "Quads, Glutes, Core", difficulty: "Intermediate", imageName: "figure.strengthtraining.traditional"),
        ExerciseData(name: "Bench Press", targetMuscles: "Chest, Triceps, Shoulders", difficulty: "Intermediate", imageName: "figure.strengthtraining.traditional"),
        ExerciseData(name: "Deadlift", targetMuscles: "Back, Glutes, Hamstrings", difficulty: "Advanced", imageName: "figure.strengthtraining.traditional"),
        ExerciseData(name: "Overhead Press", targetMuscles: "Shoulders, Triceps, Core", difficulty: "Intermediate", imageName: "figure.strengthtraining.traditional"),
        ExerciseData(name: "Barbell Row", targetMuscles: "Back, Biceps, Lats", difficulty: "Intermediate", imageName: "figure.strengthtraining.traditional"),
        ExerciseData(name: "Pull-up", targetMuscles: "Lats, Biceps, Back", difficulty: "Advanced", imageName: "figure.strengthtraining.traditional"),
        ExerciseData(name: "Dumbbell Bench", targetMuscles: "Chest, Triceps, Shoulders", difficulty: "Beginner", imageName: "dumbbell.fill"),
        ExerciseData(name: "Romanian Deadlift", targetMuscles: "Hamstrings, Glutes, Lower Back", difficulty: "Intermediate", imageName: "figure.strengthtraining.traditional"),
        ExerciseData(name: "Hip Thrust", targetMuscles: "Glutes, Hamstrings", difficulty: "Beginner", imageName: "figure.strengthtraining.traditional"),
        ExerciseData(name: "Lat Pulldown", targetMuscles: "Lats, Biceps, Back", difficulty: "Beginner", imageName: "figure.strengthtraining.traditional")
    ]

    static func seedIfNeeded(context: ModelContext) throws {
        let count = try context.fetchCount(FetchDescriptor<Exercise>())
        guard count == 0 else { return }
        for data in defaults {
            context.insert(Exercise(
                name: data.name,
                targetMuscles: data.targetMuscles,
                difficulty: data.difficulty,
                imageName: data.imageName
            ))
        }
        try context.save()
    }
}

