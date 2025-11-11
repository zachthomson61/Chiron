//
//  ExerciseLibraryTests.swift
//  ChironTests
//
//  TrainingLog module - Unit tests for exercise library
//

import XCTest
import SwiftData
@testable import Chiron

final class ExerciseLibraryTests: XCTestCase {

    // MARK: - Helpers

    private func makeInMemoryContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Exercise.self, configurations: config)
        return container.mainContext
    }

    // MARK: - Tests

    func testNamesAreUniqueCaseInsensitive() throws {
        let context = try makeInMemoryContext()

        // Insert "Bench Press"
        let exercise1 = Exercise(name: "Bench Press")
        context.insert(exercise1)
        try context.save()

        // Attempt to insert "bench press" (different case)
        let exercise2 = Exercise(name: "bench press")
        context.insert(exercise2)

        // Fetch all exercises
        let descriptor = FetchDescriptor<Exercise>()
        let exercises = try context.fetch(descriptor)

        // Check for duplicates (case-insensitive)
        let uniqueNames = Set(exercises.map { $0.name.lowercased() })

        // Expect dedupe logic in add function to prevent duplicates
        // This test verifies the model allows inserts, but app logic must prevent them
        XCTAssertGreaterThanOrEqual(exercises.count, 1, "At least one exercise should be inserted")
        XCTAssertEqual(exercises.count, uniqueNames.count, "Exercise names should be unique regardless of case")
    }

    func testSeederOnlyRunsOnEmptyStore() throws {
        let context = try makeInMemoryContext()

        // First seed should populate exercises
        try ExerciseSeeder.seedIfNeeded(context: context)
        let descriptor = FetchDescriptor<Exercise>()
        let exercises1 = try context.fetch(descriptor)
        XCTAssertEqual(exercises1.count, ExerciseSeeder.defaults.count, "Seeder should populate default exercises")

        // Second seed should not add more
        try ExerciseSeeder.seedIfNeeded(context: context)
        let exercises2 = try context.fetch(descriptor)
        XCTAssertEqual(exercises2.count, ExerciseSeeder.defaults.count, "Seeder should not run twice")
    }
}

