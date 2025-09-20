import Foundation

// MARK: - Planner Engine

final class PlannerEngine {
    
    // MARK: - WorkoutExercise Database
    
    private let exerciseDatabase: [ExerciseCategory: [String]] = [
        .compound: [
            "Barbell Squat", "Deadlift", "Bench Press", "Overhead Press",
            "Pull-ups", "Dips", "Rows", "Front Squat", "Romanian Deadlift",
            "Incline Press", "Close-Grip Bench", "Sumo Deadlift"
        ],
        .isolation: [
            "Bicep Curls", "Tricep Extensions", "Lateral Raises", "Leg Curls",
            "Leg Extensions", "Calf Raises", "Face Pulls", "Shrugs",
            "Cable Flyes", "Hammer Curls", "Preacher Curls", "Cable Crossovers"
        ],
        .cardio: [
            "Treadmill Run", "Bike Intervals", "Rowing", "Stairmaster",
            "Elliptical", "Jump Rope", "Battle Ropes", "Sled Push"
        ],
        .mobility: [
            "Dynamic Stretching", "Foam Rolling", "Yoga Flow", "Hip Circles",
            "Shoulder Dislocations", "Cat-Cow", "Bird Dog", "Dead Hang"
        ],
        .plyometric: [
            "Box Jumps", "Jump Squats", "Burpees", "Medicine Ball Slams",
            "Broad Jumps", "Split Jumps", "Clap Push-ups", "Tuck Jumps"
        ],
        .functional: [
            "Kettlebell Swings", "Turkish Get-ups", "Farmer's Walk", "Sled Pull",
            "Battle Ropes", "Tire Flips", "Sandbag Carries", "Wall Balls"
        ]
    ]
    
    // MARK: - Injury Modifications
    
    private let injuryExclusions: [Injury: [String]] = [
        .knee: ["Jump Squats", "Box Jumps", "Split Jumps", "Tuck Jumps", "Deep Squats"],
        .shoulder: ["Overhead Press", "Dips", "Behind-the-Neck Press", "Upright Rows"],
        .back: ["Deadlift", "Good Mornings", "Hyperextensions", "Heavy Rows"],
        .ankle: ["Jump Rope", "Box Jumps", "Calf Raises", "Running"],
        .wrist: ["Push-ups", "Bench Press", "Wrist Curls"],
        .hip: ["Deep Squats", "Lunges", "Hip Thrusts"],
        .neck: ["Shrugs", "Neck Extensions", "Heavy Overhead Press"]
    ]
    
    private let injuryConstraintExclusions: [InjuryConstraint: [String]] = [
        .knee: ["Jump Squats", "Box Jumps", "Split Jumps", "Tuck Jumps", "Deep Squats", "Lunges", "Step-ups"],
        .shoulder: ["Overhead Press", "Dips", "Behind-the-Neck Press", "Upright Rows", "Lateral Raises", "Face Pulls"],
        .lowBack: ["Deadlift", "Good Mornings", "Hyperextensions", "Heavy Rows", "Bent-over Rows", "Romanian Deadlift"],
        .upperBack: ["Heavy Rows", "Bent-over Rows", "Upright Rows", "Shrugs"],
        .ankle: ["Jump Rope", "Box Jumps", "Calf Raises", "Running", "Plyometric Exercises"],
        .wrist: ["Push-ups", "Bench Press", "Wrist Curls", "Handstand Push-ups", "Dips"],
        .hip: ["Deep Squats", "Lunges", "Hip Thrusts", "Bulgarian Split Squats", "Step-ups"],
        .neck: ["Shrugs", "Neck Extensions", "Heavy Overhead Press", "Upright Rows"],
        .generalPain: ["High Impact Exercises", "Heavy Lifting", "Complex Movements"]
    ]
    
    private let injuryConstraintSubstitutions: [InjuryConstraint: [String: String]] = [
        .knee: [
            "Squats": "Box Squats",
            "Lunges": "Reverse Lunges",
            "Jump Squats": "Goblet Squats",
            "Step-ups": "Seated Leg Press"
        ],
        .shoulder: [
            "Overhead Press": "Landmine Press",
            "Dips": "Close-Grip Push-ups",
            "Lateral Raises": "Cable Lateral Raises",
            "Face Pulls": "Band Pull-aparts"
        ],
        .lowBack: [
            "Deadlift": "Trap Bar Deadlift",
            "Bent-over Rows": "Chest-supported Rows",
            "Good Mornings": "Romanian Deadlift (Light)",
            "Hyperextensions": "Bird Dog"
        ],
        .upperBack: [
            "Heavy Rows": "Light Rows",
            "Upright Rows": "Lateral Raises",
            "Shrugs": "Scapular Wall Slides"
        ],
        .ankle: [
            "Calf Raises": "Seated Calf Raises",
            "Jump Rope": "Low Impact Cardio",
            "Box Jumps": "Step-ups"
        ],
        .wrist: [
            "Push-ups": "Knee Push-ups",
            "Bench Press": "Dumbbell Press",
            "Wrist Curls": "Grip Strengthening"
        ],
        .hip: [
            "Deep Squats": "Box Squats",
            "Lunges": "Reverse Lunges",
            "Hip Thrusts": "Glute Bridges"
        ],
        .neck: [
            "Shrugs": "Scapular Wall Slides",
            "Heavy Overhead Press": "Light Lateral Raises"
        ]
    ]
    
    // MARK: - Public Methods
    
    func generatePlan(from input: PlanBuilderInput) -> TrainingPlan {
        var weeks: [TrainingWeek] = []

        // Parse injury profile if not already set
        let injuryProfile = input.injuryProfile ?? {
            let allText = input.injuryNotes.map { $0.raw }.joined(separator: " ")
            return InjuryParser.parse(allText, notes: input.injuryNotes)
        }()

        // Clamp variety continuum to valid range
        let clampedVarietyContinuum = input.varietyContinuum.clamped(to: 0...1)
        
        // Compute variety policy
        let varietyPolicy = VarietyPolicy.from(clampedVarietyContinuum)
        
        // Debug: Print input values
        print("DEBUG: Generating plan with input:")
        print("  - name: '\(input.name)'")
        print("  - goals: \(input.goals)")
        print("  - sessionMinutes: \(input.sessionMinutes)")
        print("  - daysPerWeek: \(input.daysPerWeek)")
        print("  - programDuration: \(input.programDuration)")
        print("  - targetMuscles: \(input.targetMuscles)")
        print("  - split: \(input.split)")
        print("  - varietyContinuum: \(clampedVarietyContinuum)")
        print("  - supersets: \(input.supersets)")
        
        for weekNum in 1...input.programDuration {
            let days = generateWeekDays(
                weekNumber: weekNum,
                daysPerWeek: input.daysPerWeek,
                split: input.split,
                targetMuscles: input.targetMuscles,
                injuries: input.injuries,
                varietyLevel: input.varietyLevel,
                varietyContinuum: clampedVarietyContinuum,
                varietyPolicy: varietyPolicy,
                supersets: input.supersets,
                sessionMinutes: input.sessionMinutes,
                totalWeeks: input.programDuration,
                customSplit: input.customSplit,
                injuryProfile: injuryProfile
            )
            weeks.append(TrainingWeek(weekNumber: weekNum, days: days))
            print("DEBUG: Generated week \(weekNum) with \(days.count) days")
        }
        
        print("DEBUG: Creating TrainingPlan with \(weeks.count) weeks")
        
        let plan = TrainingPlan(
            name: input.name.isEmpty ? "Custom Plan" : input.name,
            duration: input.programDuration,
            daysPerWeek: input.daysPerWeek,
            targetMuscles: input.targetMuscles,
            split: input.split,
            injuries: input.injuries,
            varietyContinuum: clampedVarietyContinuum,
            supersets: input.supersets,
            weeks: weeks
        )
        
        print("DEBUG: Successfully created TrainingPlan: \(plan.name)")
        return plan
    }
    
    // MARK: - Private Methods
    
    private func generateWeekDays(
        weekNumber: Int,
        daysPerWeek: Int,
        split: WorkoutSplit,
        targetMuscles: [MuscleGroup],
        injuries: [Injury],
        varietyLevel: VarietyLevel,
        varietyContinuum: VarietyContinuum,
        varietyPolicy: VarietyPolicy,
        supersets: Bool,
        sessionMinutes: Int,
        totalWeeks: Int,
        customSplit: CustomSplit? = nil,
        injuryProfile: InjuryProfile? = nil
    ) -> [TrainingDay] {
        var days: [TrainingDay] = []
        
        for dayNum in 1...daysPerWeek {
            let dayName = getDayName(dayNumber: dayNum, split: split, daysPerWeek: daysPerWeek, customSplit: customSplit)
            let exercises = generateExercises(
                for: dayName,
                split: split,
                targetMuscles: targetMuscles,
                injuries: injuries,
                varietyLevel: varietyLevel,
                varietyContinuum: varietyContinuum,
                varietyPolicy: varietyPolicy,
                supersets: supersets,
                weekNumber: weekNumber,
                totalWeeks: totalWeeks,
                customSplit: customSplit,
                dayNumber: dayNum,
                injuryProfile: injuryProfile,
                sessionMinutes: sessionMinutes
            )
            
            let duration = estimateSessionDuration(exercises: exercises)
            let difficulty = calculateDifficulty(weekNumber: weekNumber, totalWeeks: totalWeeks)
            
            days.append(TrainingDay(
                dayNumber: dayNum,
                name: dayName,
                exercises: exercises,
                duration: duration,
                difficulty: difficulty
            ))
        }
        
        return days
    }
    
    private func getDayName(dayNumber: Int, split: WorkoutSplit, daysPerWeek: Int, customSplit: CustomSplit? = nil) -> String {
        switch split {
        case .fullBody:
            return "Full Body Day \(dayNumber)"
        case .upperLower:
            return dayNumber % 2 == 1 ? "Upper Body" : "Lower Body"
        case .pushPullLegs:
            let options = ["Push", "Pull", "Legs"]
            return options[(dayNumber - 1) % 3]
        case .custom:
            if let customSplit = customSplit, dayNumber <= customSplit.dayIntents.count {
                let intent = customSplit.dayIntents[dayNumber - 1]
                return intent.rawValue
            }
            return "Workout Day \(dayNumber)"
        }
    }
    
    private func generateExercises(
        for dayName: String,
        split: WorkoutSplit,
        targetMuscles: [MuscleGroup],
        injuries: [Injury],
        varietyLevel: VarietyLevel,
        varietyContinuum: VarietyContinuum,
        varietyPolicy: VarietyPolicy,
        supersets: Bool,
        weekNumber: Int,
        totalWeeks: Int,
        customSplit: CustomSplit? = nil,
        dayNumber: Int = 1,
        injuryProfile: InjuryProfile? = nil,
        sessionMinutes: Int
    ) -> [WorkoutExercise] {
        var exercises: [WorkoutExercise] = []
        let exerciseCount = getExerciseCount(varietyLevel: varietyLevel, targetMuscles: targetMuscles)
        
        // Add warm-up
        exercises.append(WorkoutExercise(
            name: "Dynamic Warm-up",
            category: .mobility,
            sets: 1,
            reps: "5-10 min",
            restTime: 0,
            notes: "Light cardio and dynamic stretching"
        ))
        
        // Generate main exercises based on split
        var mainWorkoutExercises = selectMainWorkoutExercises(
            for: dayName,
            split: split,
            count: exerciseCount,
            injuries: injuries,
            varietyLevel: varietyLevel,
            varietyContinuum: varietyContinuum,
            varietyPolicy: varietyPolicy,
            weekNumber: weekNumber,
            customSplit: customSplit,
            dayNumber: dayNumber,
            injuryProfile: injuryProfile
        )

        // Deterministic time boxing: trim isolation work first to fit sessionMinutes
        let warmupCooldownMin = 10
        let perExerciseMinutes: (WorkoutExercise) -> Int = { ex in
            switch ex.category {
            case .compound: return 8
            case .isolation: return 5
            case .cardio: return 8
            case .mobility: return 5
            case .plyometric: return 6
            case .functional: return 7
            }
        }
        func estimatedMainMinutes(_ items: [WorkoutExercise]) -> Int {
            items.reduce(0) { $0 + perExerciseMinutes($1) }
        }
        while warmupCooldownMin + estimatedMainMinutes(mainWorkoutExercises) > sessionMinutes {
            if let lastIsolationIndex = mainWorkoutExercises.lastIndex(where: { $0.category == .isolation }) {
                mainWorkoutExercises.remove(at: lastIsolationIndex)
            } else {
                break
            }
        }
        
        // Deterministic supersets: if enabled and short sessions, pair adjacent
        let shouldUseSupersets = supersets && sessionMinutes < 45 && mainWorkoutExercises.count >= 2
        if shouldUseSupersets {
            exercises.append(contentsOf: createSupersets(from: mainWorkoutExercises))
        } else {
            exercises.append(contentsOf: mainWorkoutExercises)
        }
        
        // Add cool-down
        exercises.append(WorkoutExercise(
            name: "Cool-down Stretching",
            category: .mobility,
            sets: 1,
            reps: "5-10 min",
            restTime: 0,
            notes: "Static stretching and foam rolling"
        ))
        
        return exercises
    }
    
    private func selectMainWorkoutExercises(
        for dayName: String,
        split: WorkoutSplit,
        count: Int,
        injuries: [Injury],
        varietyLevel: VarietyLevel,
        varietyContinuum: VarietyContinuum,
        varietyPolicy: VarietyPolicy,
        weekNumber: Int,
        customSplit: CustomSplit? = nil,
        dayNumber: Int = 1,
        injuryProfile: InjuryProfile? = nil
    ) -> [WorkoutExercise] {
        var selectedWorkoutExercises: [WorkoutExercise] = []
        var availableWorkoutExercises: [String] = []
        
        // Determine exercise pool based on day type
        switch split {
        case .fullBody:
            availableWorkoutExercises = Array(exerciseDatabase[.compound]!) + Array(exerciseDatabase[.isolation]!)
        case .upperLower:
            if dayName.contains("Upper") {
                availableWorkoutExercises = filterUpperBodyWorkoutExercises()
            } else {
                availableWorkoutExercises = filterLowerBodyWorkoutExercises()
            }
        case .pushPullLegs:
            if dayName == "Push" {
                availableWorkoutExercises = filterPushWorkoutExercises()
            } else if dayName == "Pull" {
                availableWorkoutExercises = filterPullWorkoutExercises()
            } else {
                availableWorkoutExercises = filterLegWorkoutExercises()
            }
        case .custom:
            availableWorkoutExercises = getCustomSplitExercises(
                customSplit: customSplit,
                dayNumber: dayNumber,
                dayName: dayName
            )
        default:
            availableWorkoutExercises = Array(exerciseDatabase[.compound]!) + Array(exerciseDatabase[.isolation]!)
        }
        
        // Filter out injury-restricted exercises
        availableWorkoutExercises = filterInjuryRestrictions(exercises: availableWorkoutExercises, injuries: injuries)
        
        // Apply new injury constraint filtering
        if let injuryProfile = injuryProfile {
            availableWorkoutExercises = filterInjuryConstraintRestrictions(exercises: availableWorkoutExercises, constraints: injuryProfile.constraints)
            availableWorkoutExercises = applyInjuryConstraintSubstitutions(exercises: availableWorkoutExercises, constraints: injuryProfile.constraints)
        }
        
        // Deterministic variety policy: sort and round-robin by week number
        availableWorkoutExercises.sort()
        if varietyContinuum < 0.33 {
            availableWorkoutExercises = Array(availableWorkoutExercises.prefix(6))
        }
        let poolCount = availableWorkoutExercises.count
        let startOffset = poolCount == 0 ? 0 : (max(0, weekNumber - 1) % poolCount)
        
        // Select exercises
        for i in 0..<min(count, availableWorkoutExercises.count) {
            let index = (startOffset + i) % availableWorkoutExercises.count
            let exercise = availableWorkoutExercises[index]
            let category: ExerciseCategory = i < 2 ? .compound : .isolation
            let sets = calculateSets(weekNumber: weekNumber, exerciseIndex: i)
            let reps = calculateReps(weekNumber: weekNumber, category: category)
            let rest = calculateRest(category: category)
            
            selectedWorkoutExercises.append(WorkoutExercise(
                name: exercise,
                category: category,
                sets: sets,
                reps: reps,
                restTime: rest
            ))
        }
        
        return selectedWorkoutExercises
    }
    
    private func createSupersets(from exercises: [WorkoutExercise]) -> [WorkoutExercise] {
        var supersetWorkoutExercises: [WorkoutExercise] = []
        var supersetGroup = 1
        
        for i in stride(from: 0, to: exercises.count, by: 2) {
            let first = exercises[i]
            supersetWorkoutExercises.append(WorkoutExercise(
                name: first.name,
                category: first.category,
                sets: first.sets,
                reps: first.reps,
                restTime: 30,
                notes: "Superset A\(supersetGroup)",
                isSuperset: true,
                supersetGroup: supersetGroup
            ))
            
            if i + 1 < exercises.count {
                let second = exercises[i + 1]
                supersetWorkoutExercises.append(WorkoutExercise(
                    name: second.name,
                    category: second.category,
                    sets: second.sets,
                    reps: second.reps,
                    restTime: 90,
                    notes: "Superset B\(supersetGroup)",
                    isSuperset: true,
                    supersetGroup: supersetGroup
                ))
                supersetGroup += 1
            }
        }
        
        return supersetWorkoutExercises
    }
    
    // MARK: - Helper Methods
    
    private func filterUpperBodyWorkoutExercises() -> [String] {
        ["Bench Press", "Overhead Press", "Pull-ups", "Rows", "Dips", 
         "Bicep Curls", "Tricep Extensions", "Lateral Raises", "Face Pulls"]
    }
    
    private func filterLowerBodyWorkoutExercises() -> [String] {
        ["Barbell Squat", "Deadlift", "Front Squat", "Romanian Deadlift",
         "Leg Curls", "Leg Extensions", "Calf Raises", "Lunges"]
    }
    
    private func filterPushWorkoutExercises() -> [String] {
        ["Bench Press", "Overhead Press", "Incline Press", "Dips",
         "Tricep Extensions", "Lateral Raises", "Cable Flyes"]
    }
    
    private func filterPullWorkoutExercises() -> [String] {
        ["Pull-ups", "Rows", "Deadlift", "Face Pulls",
         "Bicep Curls", "Hammer Curls", "Shrugs"]
    }
    
    private func filterLegWorkoutExercises() -> [String] {
        ["Barbell Squat", "Front Squat", "Romanian Deadlift", "Lunges",
         "Leg Curls", "Leg Extensions", "Calf Raises"]
    }
    
    private func getCustomSplitExercises(
        customSplit: CustomSplit?,
        dayNumber: Int,
        dayName: String
    ) -> [String] {
        guard let customSplit = customSplit,
              dayNumber <= customSplit.dayIntents.count else {
            return Array(exerciseDatabase[.compound]!) + Array(exerciseDatabase[.isolation]!)
        }
        
        let intent = customSplit.dayIntents[dayNumber - 1]
        
        switch intent {
        case .fullBody:
            return Array(exerciseDatabase[.compound]!) + Array(exerciseDatabase[.isolation]!)
        case .upper:
            return filterUpperBodyWorkoutExercises()
        case .lower:
            return filterLowerBodyWorkoutExercises()
        case .push:
            return filterPushWorkoutExercises()
        case .pull:
            return filterPullWorkoutExercises()
        case .legs:
            return filterLegWorkoutExercises()
        case .arms:
            return ["Bicep Curls", "Tricep Extensions", "Hammer Curls", "Preacher Curls",
                   "Close-Grip Bench", "Cable Curls", "Overhead Tricep Extension", "Dips"]
        case .customMuscles:
            if let customSpec = customSplit.customSpecs[dayNumber] {
                return getExercisesForMuscleGroups(customSpec.muscles)
            }
            return Array(exerciseDatabase[.compound]!) + Array(exerciseDatabase[.isolation]!)
        }
    }
    
    private func getExercisesForMuscleGroups(_ muscleGroups: Set<MuscleGroup>) -> [String] {
        var exercises: [String] = []
        
        for muscle in muscleGroups {
            switch muscle {
            case .chest:
                exercises.append(contentsOf: ["Bench Press", "Incline Press", "Cable Flyes", "Push-ups"])
            case .back:
                exercises.append(contentsOf: ["Pull-ups", "Rows", "Deadlift", "Lat Pulldowns"])
            case .shoulders:
                exercises.append(contentsOf: ["Overhead Press", "Lateral Raises", "Face Pulls", "Shrugs"])
            case .biceps:
                exercises.append(contentsOf: ["Bicep Curls", "Hammer Curls", "Preacher Curls", "Cable Curls"])
            case .triceps:
                exercises.append(contentsOf: ["Tricep Extensions", "Close-Grip Bench", "Dips", "Overhead Extension"])
            case .quads:
                exercises.append(contentsOf: ["Barbell Squat", "Front Squat", "Leg Extensions", "Lunges"])
            case .hamstrings:
                exercises.append(contentsOf: ["Romanian Deadlift", "Leg Curls", "Good Mornings", "Stiff Leg Deadlift"])
            case .glutes:
                exercises.append(contentsOf: ["Hip Thrusts", "Glute Bridges", "Bulgarian Split Squats", "Romanian Deadlift"])
            case .calves:
                exercises.append(contentsOf: ["Calf Raises", "Seated Calf Raises", "Single Leg Calf Raises"])
            case .abs:
                exercises.append(contentsOf: ["Plank", "Crunches", "Russian Twists", "Mountain Climbers"])
            case .forearms:
                exercises.append(contentsOf: ["Wrist Curls", "Reverse Wrist Curls", "Farmer's Walk"])
            case .trapezius:
                exercises.append(contentsOf: ["Shrugs", "Face Pulls", "Upright Rows"])
            case .lowerBack:
                exercises.append(contentsOf: ["Hyperextensions", "Good Mornings", "Deadlift"])
            case .abductors:
                exercises.append(contentsOf: ["Clamshells", "Lateral Leg Raises", "Hip Abduction"])
            case .adductors:
                exercises.append(contentsOf: ["Sumo Squats", "Hip Adduction", "Cossack Squats"])
            }
        }
        
        return Array(Set(exercises)) // Remove duplicates
    }
    
    private func filterInjuryRestrictions(exercises: [String], injuries: [Injury]) -> [String] {
        var filtered = exercises
        for injury in injuries {
            if let exclusions = injuryExclusions[injury] {
                filtered = filtered.filter { !exclusions.contains($0) }
            }
        }
        return filtered
    }
    
    private func filterInjuryConstraintRestrictions(exercises: [String], constraints: Set<InjuryConstraint>) -> [String] {
        var filtered = exercises
        for constraint in constraints {
            if let exclusions = injuryConstraintExclusions[constraint] {
                filtered = filtered.filter { !exclusions.contains($0) }
            }
        }
        return filtered
    }
    
    private func applyInjuryConstraintSubstitutions(exercises: [String], constraints: Set<InjuryConstraint>) -> [String] {
        var substituted = exercises
        for constraint in constraints {
            if let substitutions = injuryConstraintSubstitutions[constraint] {
                for (original, replacement) in substitutions {
                    substituted = substituted.map { exercise in
                        exercise == original ? replacement : exercise
                    }
                }
            }
        }
        return substituted
    }
    
    private func getExerciseCount(varietyLevel: VarietyLevel, targetMuscles: [MuscleGroup]) -> Int {
        switch varietyLevel {
        case .low: return 4
        case .medium: return 5
        case .high: return 6
        }
    }
    
    private func calculateSets(weekNumber: Int, exerciseIndex: Int) -> Int {
        let baseSets = exerciseIndex < 2 ? 4 : 3
        let progression = min(weekNumber / 2, 1)
        return baseSets + progression
    }
    
    private func calculateReps(weekNumber: Int, category: ExerciseCategory) -> String {
        switch category {
        case .compound:
            return weekNumber <= 4 ? "8-10" : "6-8"
        case .isolation:
            return "10-15"
        case .cardio:
            return "20-30 min"
        case .mobility:
            return "10-15"
        case .plyometric:
            return "8-10"
        case .functional:
            return "10-12"
        }
    }
    
    private func calculateRest(category: ExerciseCategory) -> Int {
        switch category {
        case .compound: return 120
        case .isolation: return 60
        case .cardio: return 30
        case .mobility: return 30
        case .plyometric: return 90
        case .functional: return 90
        }
    }
    
    private func estimateSessionDuration(exercises: [WorkoutExercise]) -> Int {
        var total = 0
        for ex in exercises {
            switch ex.category {
            case .compound: total += 8
            case .isolation: total += 5
            case .cardio: total += 8
            case .mobility: total += 5
            case .plyometric: total += 6
            case .functional: total += 7
            }
        }
        return total
    }
    
    private func calculateDifficulty(weekNumber: Int, totalWeeks: Int) -> DifficultyLevel {
        let progression = Float(weekNumber) / Float(totalWeeks)
        if progression <= 0.33 {
            return .beginner
        } else if progression <= 0.67 {
            return .intermediate
        } else {
            return .advanced
        }
    }
}
