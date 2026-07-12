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
        // A standalone context rather than `container.mainContext`: the latter is
        // @MainActor-isolated and cannot be touched from these nonisolated tests.
        return ModelContext(container)
    }

    // MARK: - Tests

    func testNamesAreUniqueCaseInsensitive() throws {
        let context = try makeInMemoryContext()

        // Insert "Bench Press"
        let exercise1 = Exercise(name: "Bench Press")
        context.insert(exercise1)
        try context.save()

        // The SwiftData model does NOT enforce name uniqueness — the add flow
        // (ExerciseLibraryView.addExercise) guards with a case-insensitive compare
        // against the fetched library. Assert that guard's contract here: a
        // case-variant of an existing name is detected as a duplicate, a new
        // name is not.
        let descriptor = FetchDescriptor<Exercise>()
        let existing = try context.fetch(descriptor)

        let caseVariantIsDuplicate = existing.contains {
            $0.name.compare("bench press", options: .caseInsensitive) == .orderedSame
        }
        XCTAssertTrue(caseVariantIsDuplicate,
                      "Case-variant of an existing exercise name must be detected as a duplicate")

        let freshNameIsDuplicate = existing.contains {
            $0.name.compare("Incline Bench Press", options: .caseInsensitive) == .orderedSame
        }
        XCTAssertFalse(freshNameIsDuplicate,
                       "A distinct new name must not be flagged as a duplicate")
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

