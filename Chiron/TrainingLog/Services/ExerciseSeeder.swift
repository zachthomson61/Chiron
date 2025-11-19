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
    
    /// Lightweight seed data that mirrors the samples used in previews and acceptance criteria.
    static let defaults: [ExerciseData] = [
        ExerciseData(
            name: "Bodyweight Squat",
            primaryTargets: [.quadriceps, .glutes, .adductors],
            secondaryTargets: [],
            difficulty: .beginner,
            imageName: "figure.strengthtraining.traditional"
        ),
        ExerciseData(
            name: "Barbell Back Squat",
            primaryTargets: [.quadriceps, .glutes, .adductors],
            secondaryTargets: [],
            difficulty: .intermediate,
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
            name: "Barbell Bench Press",
            primaryTargets: [.chest, .frontDelts, .triceps],
            secondaryTargets: [],
            difficulty: .intermediate,
            imageName: "figure.strengthtraining.traditional"
        ),
        // Deadlift: Expert-level compound movement targeting posterior chain
        ExerciseData(
            name: "Deadlift",
            primaryTargets: [.glutes, .hamstrings, .lowerBack],
            secondaryTargets: [],
            difficulty: .expert,
            imageName: "figure.strengthtraining.traditional"
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

