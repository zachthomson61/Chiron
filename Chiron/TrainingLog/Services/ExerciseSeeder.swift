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
        let primaryTargets: [MuscleGroup]
        let secondaryTargets: [MuscleGroup]
        let difficulty: Difficulty
        let imageName: String
    }
    
    static let defaults: [ExerciseData] = [
        ExerciseData(
            name: "Barbell Back Squat",
            primaryTargets: [.quadriceps, .glutes],
            secondaryTargets: [.hamstrings, .core],
            difficulty: .intermediate,
            imageName: "figure.strengthtraining.traditional"
        ),
        ExerciseData(
            name: "Bench Press",
            primaryTargets: [.chest],
            secondaryTargets: [.triceps, .frontDelts],
            difficulty: .beginner,
            imageName: "figure.strengthtraining.traditional"
        ),
        ExerciseData(
            name: "Barbell Row",
            primaryTargets: [.back, .lats],
            secondaryTargets: [.rearDelts, .biceps],
            difficulty: .intermediate,
            imageName: "figure.strengthtraining.traditional"
        ),
        ExerciseData(
            name: "Romanian Deadlift",
            primaryTargets: [.hamstrings],
            secondaryTargets: [.glutes, .erectors],
            difficulty: .intermediate,
            imageName: "figure.strengthtraining.traditional"
        ),
        ExerciseData(
            name: "Pull-up",
            primaryTargets: [.lats],
            secondaryTargets: [.biceps, .forearms],
            difficulty: .advanced,
            imageName: "figure.strengthtraining.traditional"
        ),
        ExerciseData(
            name: "Overhead Press",
            primaryTargets: [.frontDelts, .shoulders],
            secondaryTargets: [.triceps, .core],
            difficulty: .intermediate,
            imageName: "figure.strengthtraining.traditional"
        ),
        ExerciseData(
            name: "Hip Thrust",
            primaryTargets: [.glutes],
            secondaryTargets: [.hamstrings],
            difficulty: .beginner,
            imageName: "figure.strengthtraining.traditional"
        ),
        ExerciseData(
            name: "Lat Pulldown",
            primaryTargets: [.lats],
            secondaryTargets: [.rearDelts, .biceps],
            difficulty: .beginner,
            imageName: "figure.strengthtraining.traditional"
        ),
        ExerciseData(
            name: "Plank",
            primaryTargets: [.core],
            secondaryTargets: [.obliques, .erectors],
            difficulty: .beginner,
            imageName: "figure.core.training"
        ),
        ExerciseData(
            name: "Dumbbell Lateral Raise",
            primaryTargets: [.shoulders],
            secondaryTargets: [.rearDelts],
            difficulty: .beginner,
            imageName: "figure.arms.open"
        )
    ]

    static func seedIfNeeded(context: ModelContext) throws {
        let count = try context.fetchCount(FetchDescriptor<Exercise>())
        guard count == 0 else { return }
        for data in defaults {
            context.insert(Exercise(
                name: data.name,
                primaryTargets: data.primaryTargets,
                secondaryTargets: data.secondaryTargets,
                difficulty: data.difficulty,
                imageName: data.imageName
            ))
        }
        try context.save()
    }
}

