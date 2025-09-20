import XCTest
@testable import Chiron

final class PlannerEngineTests: XCTestCase {
    
    var engine: PlannerEngine!
    
    override func setUp() {
        super.setUp()
        engine = PlannerEngine()
    }
    
    override func tearDown() {
        engine = nil
        super.tearDown()
    }
    
    // MARK: - Basic Plan Generation Tests
    
    func testGeneratePlanWithValidInput() {
        // Given
        var input = PlanBuilderInput()
        input.name = "Test Plan"
        input.goals = [.strength]
        input.sessionMinutes = 45
        input.daysPerWeek = 3
        input.programDuration = 4
        input.split = .fullBody
        input.varietyLevel = .medium
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        XCTAssertEqual(plan.name, "Test Plan")
        XCTAssertEqual(plan.weeks.count, 4)
        XCTAssertEqual(plan.daysPerWeek, 3)
        XCTAssertEqual(plan.split, .fullBody)
    }
    
    func testPlanHasCorrectNumberOfWeeks() {
        // Given
        var input = PlanBuilderInput()
        input.name = "8 Week Plan"
        input.goals = [.hypertrophy]
        input.programDuration = 8
        input.daysPerWeek = 4
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        XCTAssertEqual(plan.weeks.count, 8)
        XCTAssertEqual(plan.duration, 8)
    }
    
    func testEachWeekHasCorrectNumberOfDays() {
        // Given
        var input = PlanBuilderInput()
        input.name = "5 Day Plan"
        input.goals = [.strength, .power]
        input.daysPerWeek = 5
        input.programDuration = 4
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        for week in plan.weeks {
            XCTAssertEqual(week.days.count, 5)
        }
    }
    
    // MARK: - Split Tests
    
    func testFullBodySplit() {
        // Given
        var input = PlanBuilderInput()
        input.goals = [.strength]
        input.split = .fullBody
        input.daysPerWeek = 3
        input.programDuration = 1
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        let firstWeek = plan.weeks.first!
        for day in firstWeek.days {
            XCTAssertTrue(day.name.contains("Full Body"))
        }
    }
    
    func testUpperLowerSplit() {
        // Given
        var input = PlanBuilderInput()
        input.goals = [.hypertrophy]
        input.split = .upperLower
        input.daysPerWeek = 4
        input.programDuration = 1
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        let firstWeek = plan.weeks.first!
        let dayNames = firstWeek.days.map { $0.name }
        XCTAssertTrue(dayNames.contains("Upper Body"))
        XCTAssertTrue(dayNames.contains("Lower Body"))
    }
    
    func testPushPullLegsSplit() {
        // Given
        var input = PlanBuilderInput()
        input.goals = [.strength]
        input.split = .pushPullLegs
        input.daysPerWeek = 6
        input.programDuration = 1
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        let firstWeek = plan.weeks.first!
        let dayNames = firstWeek.days.map { $0.name }
        XCTAssertTrue(dayNames.contains(where: { $0 == "Push" }))
        XCTAssertTrue(dayNames.contains(where: { $0 == "Pull" }))
        XCTAssertTrue(dayNames.contains(where: { $0 == "Legs" }))
    }
    
    // MARK: - Variety Level Tests
    
    func testLowVarietyHasFewerExercises() {
        // Given
        var input = PlanBuilderInput()
        input.goals = [.strength]
        input.varietyLevel = .low
        input.daysPerWeek = 3
        input.programDuration = 1
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        let firstDay = plan.weeks.first!.days.first!
        // Low variety should have ~6 exercises (4 main + warmup + cooldown)
        XCTAssertLessThanOrEqual(firstDay.exercises.count, 7)
    }
    
    func testHighVarietyHasMoreExercises() {
        // Given
        var input = PlanBuilderInput()
        input.goals = [.strength]
        input.varietyLevel = .high
        input.daysPerWeek = 3
        input.programDuration = 1
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        let firstDay = plan.weeks.first!.days.first!
        // High variety should have ~8 exercises (6 main + warmup + cooldown)
        XCTAssertGreaterThanOrEqual(firstDay.exercises.count, 7)
    }
    
    // MARK: - Injury Tests
    
    func testInjuryExcludesRestrictedExercises() {
        // Given
        var input = PlanBuilderInput()
        input.goals = [.strength]
        input.injuries = [.knee]
        input.daysPerWeek = 3
        input.programDuration = 1
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        let restrictedExercises = ["Jump Squats", "Box Jumps", "Split Jumps", "Tuck Jumps"]
        for week in plan.weeks {
            for day in week.days {
                for exercise in day.exercises {
                    XCTAssertFalse(restrictedExercises.contains(exercise.name))
                }
            }
        }
    }
    
    func testMultipleInjuriesExcludeAllRestrictedExercises() {
        // Given
        var input = PlanBuilderInput()
        input.goals = [.strength]
        input.injuries = [.knee, .shoulder]
        input.daysPerWeek = 3
        input.programDuration = 1
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        let kneeRestricted = ["Jump Squats", "Box Jumps"]
        let shoulderRestricted = ["Overhead Press", "Dips"]
        let allRestricted = kneeRestricted + shoulderRestricted
        
        for week in plan.weeks {
            for day in week.days {
                for exercise in day.exercises {
                    XCTAssertFalse(allRestricted.contains(exercise.name))
                }
            }
        }
    }
    
    // MARK: - Superset Tests
    
    func testSupersetsGroupExercises() {
        // Given
        var input = PlanBuilderInput()
        input.goals = [.hypertrophy]
        input.supersets = true
        input.varietyContinuum = 1.0 // High variety to ensure supersets are created
        input.daysPerWeek = 3
        input.programDuration = 1
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        let firstDay = plan.weeks.first!.days.first!
        let supersetExercises = firstDay.exercises.filter { $0.isSuperset }
        XCTAssertGreaterThan(supersetExercises.count, 0)
        
        // Check that supersets have group numbers
        let hasGroupNumbers = supersetExercises.allSatisfy { $0.supersetGroup != nil }
        XCTAssertTrue(hasGroupNumbers)
    }
    
    // MARK: - Duration Tests
    
    func testSessionDurationCalculation() {
        // Given
        var input = PlanBuilderInput()
        input.goals = [.strength]
        input.sessionMinutes = 60
        input.daysPerWeek = 3
        input.programDuration = 1
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        let firstDay = plan.weeks.first!.days.first!
        XCTAssertGreaterThan(firstDay.duration, 0)
        XCTAssertLessThanOrEqual(firstDay.duration, 90)
    }
    
    // MARK: - Progression Tests
    
    func testDifficultyProgressesOverWeeks() {
        // Given
        var input = PlanBuilderInput()
        input.goals = [.strength]
        input.programDuration = 12
        input.daysPerWeek = 3
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        let firstWeekDifficulty = plan.weeks.first!.days.first!.difficulty
        let lastWeekDifficulty = plan.weeks.last!.days.first!.difficulty
        
        // Later weeks should have higher difficulty
        XCTAssertEqual(firstWeekDifficulty, .beginner)
        XCTAssertEqual(lastWeekDifficulty, .advanced)
    }
    
    // MARK: - Exercise Content Tests
    
    func testEveryDayHasWarmupAndCooldown() {
        // Given
        var input = PlanBuilderInput()
        input.goals = [.strength]
        input.daysPerWeek = 3
        input.programDuration = 2
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        for week in plan.weeks {
            for day in week.days {
                let hasWarmup = day.exercises.contains { $0.name.contains("Warm-up") }
                let hasCooldown = day.exercises.contains { $0.name.contains("Cool-down") }
                XCTAssertTrue(hasWarmup, "Day should have warmup")
                XCTAssertTrue(hasCooldown, "Day should have cooldown")
            }
        }
    }
    
    // MARK: - Injury Notes Tests
    
    func testMultipleInjuryEntriesParsesAllConstraints() {
        // Given
        let notes = [
            InjuryNote(raw: "shoulder impingement"),
            InjuryNote(raw: "low back tightness"),
            InjuryNote(raw: "sore knee")
        ]
        
        // When
        let profile = InjuryParser.parse("shoulder impingement low back tightness sore knee", notes: notes)
        
        // Then
        XCTAssertTrue(profile.constraints.contains(.shoulder))
        XCTAssertTrue(profile.constraints.contains(.lowBack))
        XCTAssertTrue(profile.constraints.contains(.knee))
        XCTAssertEqual(profile.notes.count, 3)
    }
    
    func testAddingAndRemovingInjuryNotesUpdatesProfile() {
        // Given
        var notes: [InjuryNote] = []
        
        // When - Add notes
        let note1 = InjuryNote(raw: "shoulder pain")
        let note2 = InjuryNote(raw: "knee stiffness")
        notes.append(note1)
        notes.append(note2)
        
        let profile1 = InjuryParser.parse("shoulder pain knee stiffness", notes: notes)
        
        // Then
        XCTAssertTrue(profile1.constraints.contains(.shoulder))
        XCTAssertTrue(profile1.constraints.contains(.knee))
        XCTAssertEqual(profile1.notes.count, 2)
        
        // When - Remove one note
        notes.removeAll { $0.id == note1.id }
        let profile2 = InjuryParser.parse("knee stiffness", notes: notes)
        
        // Then
        XCTAssertFalse(profile2.constraints.contains(.shoulder))
        XCTAssertTrue(profile2.constraints.contains(.knee))
        XCTAssertEqual(profile2.notes.count, 1)
    }
    
    func testGeneralPainDetectedWhenAmbiguous() {
        // Given
        let notes = [InjuryNote(raw: "my arm hurts")]
        
        // When
        let profile = InjuryParser.parse("my arm hurts", notes: notes)
        
        // Then
        XCTAssertTrue(profile.constraints.contains(.generalPain))
        XCTAssertEqual(profile.notes.count, 1)
    }
    
    func testInjuryConstraintsFilterExercises() {
        // Given
        var input = PlanBuilderInput()
        input.goals = [.strength]
        input.daysPerWeek = 3
        input.programDuration = 1
        input.injuryNotes = [
            InjuryNote(raw: "knee pain"),
            InjuryNote(raw: "shoulder impingement")
        ]
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        let restrictedExercises = ["Jump Squats", "Box Jumps", "Overhead Press", "Dips"]
        for week in plan.weeks {
            for day in week.days {
                for exercise in day.exercises {
                    XCTAssertFalse(restrictedExercises.contains(exercise.name))
                }
            }
        }
    }
    
    func testInjuryConstraintsApplySubstitutions() {
        // Given
        var input = PlanBuilderInput()
        input.goals = [.strength]
        input.daysPerWeek = 3
        input.programDuration = 1
        input.injuryNotes = [InjuryNote(raw: "knee problems")]
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        // Should see knee-friendly substitutions
        let exerciseNames = plan.weeks.first!.days.first!.exercises.map { $0.name }
        
        // Check for any knee-friendly patterns
        let hasKneeFriendly = exerciseNames.contains { name in
            let lowercased = name.lowercased()
            return lowercased.contains("box") || lowercased.contains("goblet") || 
                   lowercased.contains("reverse") || lowercased.contains("wall") || 
                   lowercased.contains("step") || lowercased.contains("knee") ||
                   lowercased.contains("squat") || lowercased.contains("lunge")
        }
        XCTAssertTrue(hasKneeFriendly, "Should include knee-friendly exercise variations. Found: \(exerciseNames)")
    }
    
    // MARK: - Input Validation Tests
    
    func testEmptyNameUsesDefault() {
        // Given
        var input = PlanBuilderInput()
        input.name = ""
        input.goals = [.strength]
        input.daysPerWeek = 3
        input.programDuration = 4
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        XCTAssertEqual(plan.name, "Custom Plan")
    }
    
    func testValidInputCheck() {
        // Given
        var input = PlanBuilderInput()
        
        // When/Then - Invalid without goals
        XCTAssertFalse(input.isValid)
        
        // Add goals
        input.goals = [.strength]
        input.name = "Test"
        XCTAssertTrue(input.isValid)
        
        // Invalid days per week
        input.daysPerWeek = 0
        XCTAssertFalse(input.isValid)
        
        input.daysPerWeek = 8
        XCTAssertFalse(input.isValid)
        
        // Valid days per week
        input.daysPerWeek = 4
        XCTAssertTrue(input.isValid)
    }
    
    // MARK: - Variety Continuum Tests
    
    func testVarietyContinuum_low_keepsAccessoriesStable() {
        // Given
        var input = createValidInput()
        input.varietyContinuum = 0.1 // Very low variety
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        XCTAssertEqual(plan.varietyContinuum, 0.1)
        XCTAssertEqual(plan.varietyContinuum.band, .consistent)
        
        // Check that exercises are more stable (less shuffling)
        let week1Exercises = plan.weeks[0].days[0].exercises.map { $0.name }
        let week2Exercises = plan.weeks[1].days[0].exercises.map { $0.name }
        
        // Should have some overlap for consistent variety
        let overlap = Set(week1Exercises).intersection(Set(week2Exercises))
        XCTAssertGreaterThan(overlap.count, 0)
    }
    
    func testVarietyContinuum_mid_rotatesModerately() {
        // Given
        var input = createValidInput()
        input.varietyContinuum = 0.5 // Balanced variety
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        XCTAssertEqual(plan.varietyContinuum, 0.5)
        XCTAssertEqual(plan.varietyContinuum.band, .balanced)
    }
    
    func testVarietyContinuum_high_rotatesAggressively() {
        // Given
        var input = createValidInput()
        input.varietyContinuum = 0.9 // High variety
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        XCTAssertEqual(plan.varietyContinuum, 0.9)
        XCTAssertEqual(plan.varietyContinuum.band, .varied)
    }
    
    func testMainLiftVariantRate_scalesWithContinuum() {
        // Given
        let lowVariety = VarietyPolicy.from(0.1)
        let highVariety = VarietyPolicy.from(0.9)
        
        // Then
        XCTAssertLessThan(lowVariety.mainLiftVariantRate, highVariety.mainLiftVariantRate)
        XCTAssertEqual(lowVariety.mainLiftVariantRate, 0.03, accuracy: 0.01) // 0.1 * 0.3
        XCTAssertEqual(highVariety.mainLiftVariantRate, 0.27, accuracy: 0.01) // 0.9 * 0.3
    }
    
    func testSupersetBias_scalesWithContinuum_whenEnabled() {
        // Given
        let lowVariety = VarietyPolicy.from(0.1)
        let highVariety = VarietyPolicy.from(0.9)
        
        // Then
        XCTAssertLessThan(lowVariety.supersetBias, highVariety.supersetBias)
        XCTAssertEqual(lowVariety.supersetBias, 0.24, accuracy: 0.01) // 0.2 + 0.4 * 0.1
        XCTAssertEqual(highVariety.supersetBias, 0.56, accuracy: 0.01) // 0.2 + 0.4 * 0.9
    }
    
    func testVarietyContinuum_clamping() {
        // Given
        var input = createValidInput()
        input.varietyContinuum = 1.5 // Above 1.0
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        XCTAssertEqual(plan.varietyContinuum, 1.0) // Should be clamped
    }
    
    func testVarietyContinuum_negativeClamping() {
        // Given
        var input = createValidInput()
        input.varietyContinuum = -0.5 // Below 0.0
        
        // When
        let plan = engine.generatePlan(from: input)
        
        // Then
        XCTAssertEqual(plan.varietyContinuum, 0.0) // Should be clamped
    }
    
    // MARK: - Helper Methods
    
    private func createValidInput() -> PlanBuilderInput {
        var input = PlanBuilderInput()
        input.name = "Test Plan"
        input.goals = [.strength]
        input.daysPerWeek = 3
        input.programDuration = 4
        return input
    }
}
