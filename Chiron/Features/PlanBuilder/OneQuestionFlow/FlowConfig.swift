import Foundation

// MARK: - Flow Configuration for One Question Flow

enum StepId: String, CaseIterable {
    case planName = "plan_name"
    case primaryGoal = "primary_goal"
    case caloricTracking = "caloric_tracking"
    case dietPhase = "diet_phase"
    case cardioPreference = "cardio_preference"
    case sportType = "sport_type"
    case experienceLevel = "experience_level"
    case currentActivityLevel = "current_activity_level"
    case daysPerWeek = "days_per_week"
    case sessionDuration = "session_duration"
    case sessionDurationShort = "session_duration_short"
    case targetMuscles = "target_muscles"
    case specificWeaknesses = "specific_weaknesses"
    case workoutSplit = "workout_split"
    case equipmentAvailable = "equipment_available"
    case trainingPreferencesLifting = "training_preferences_lifting"
    case trainingPreferencesCardio = "training_preferences_cardio"
    case cardioTypePreference = "cardio_type_preference"
    case trainingIntensity = "training_intensity"
    case injuryCheck = "injury_check"
    case injuryDetails = "injury_details"
    case exerciseVariety = "exercise_variety"
    case supersets = "supersets"
    case programDuration = "program_duration"
    case result = "RESULT"
}

enum QuestionType {
    case singleChoice
    case multiChoice
    case number
    case range
    case chips
    case yesNo
    case time
    case text
}

struct QuestionOption {
    let value: String
    let label: String
    let helper: String?
    
    init(value: String, label: String, helper: String? = nil) {
        self.value = value
        self.label = label
        self.helper = helper
    }
}

struct FlowStep {
    let id: StepId
    let prompt: String
    let helper: String?
    let type: QuestionType
    let options: [QuestionOption]?
    let min: Double?
    let max: Double?
    let step: Double?
    let unit: String?
    let placeholder: String?
    let required: Bool
    let validate: ((Any) -> String?)?
    let next: (Any, [String: Any]) -> StepId
    
    init(
        id: StepId,
        prompt: String,
        helper: String? = nil,
        type: QuestionType,
        options: [QuestionOption]? = nil,
        min: Double? = nil,
        max: Double? = nil,
        step: Double? = nil,
        unit: String? = nil,
        placeholder: String? = nil,
        required: Bool = true,
        validate: ((Any) -> String?)? = nil,
        next: @escaping (Any, [String: Any]) -> StepId
    ) {
        self.id = id
        self.prompt = prompt
        self.helper = helper
        self.type = type
        self.options = options
        self.min = min
        self.max = max
        self.step = step
        self.unit = unit
        self.placeholder = placeholder
        self.required = required
        self.validate = validate
        self.next = next
    }
}

struct FlowConfig {
    let start: StepId
    let steps: [StepId: FlowStep]
    let estimatedLength: Int
    
    static let shared = FlowConfig.createDefault()
    
    private static func createDefault() -> FlowConfig {
        var steps: [StepId: FlowStep] = [:]
        
        // 1. Plan Name
        steps[.planName] = FlowStep(
            id: .planName,
            prompt: "What would you like to name your training plan?",
            helper: "Give your plan a memorable name that reflects your goals",
            type: .text,
            placeholder: "e.g., Summer Strength, Marathon Prep",
            required: true,
            validate: { answer in
                guard let name = answer as? String else { return "Please enter a plan name" }
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return "Please enter a plan name" }
                if trimmed.count < 2 { return "Name must be at least 2 characters" }
                if trimmed.count > 50 { return "Name must be less than 50 characters" }
                return nil
            },
            next: { _, _ in .primaryGoal }
        )
        
        // 2. Primary Goal
        steps[.primaryGoal] = FlowStep(
            id: .primaryGoal,
            prompt: "What is your primary training goal?",
            helper: "This helps us tailor your program structure",
            type: .singleChoice,
            options: [
                QuestionOption(value: "muscle_gain", label: "Build Muscle", helper: "Focus on hypertrophy and size"),
                QuestionOption(value: "strength", label: "Get Stronger", helper: "Increase max strength and power"),
                QuestionOption(value: "fat_loss", label: "Lose Fat", helper: "Body recomposition and definition"),
                QuestionOption(value: "endurance", label: "Improve Endurance", helper: "Build stamina and work capacity"),
                QuestionOption(value: "athletic", label: "Athletic Performance", helper: "Sport-specific training"),
                QuestionOption(value: "general", label: "General Fitness", helper: "Overall health and wellness")
            ],
            next: { answer, _ in
                guard let goal = answer as? String else { return .caloricTracking }
                if goal == "fat_loss" || goal == "endurance" { return .cardioPreference }
                if goal == "athletic" { return .sportType }
                return .caloricTracking
            }
        )
        
        // 2a. Caloric Tracking
        steps[.caloricTracking] = FlowStep(
            id: .caloricTracking,
            prompt: "Do you currently track your calories or have a nutrition plan?",
            helper: "This helps us align your training with your nutrition goals",
            type: .singleChoice,
            options: [
                QuestionOption(value: "yes_track", label: "Yes, I track calories"),
                QuestionOption(value: "no_healthy", label: "No, but I eat generally healthy"),
                QuestionOption(value: "no_improve", label: "No, I'd like to improve my nutrition"),
                QuestionOption(value: "specific_plan", label: "I have a specific diet plan")
            ],
            next: { answer, _ in
                guard let tracking = answer as? String else { return .experienceLevel }
                if tracking == "yes_track" { return .dietPhase }
                return .experienceLevel
            }
        )
        
        // 2b. Diet Phase (conditional)
        steps[.dietPhase] = FlowStep(
            id: .dietPhase,
            prompt: "What phase are you currently in?",
            helper: "This helps us optimize your training volume and recovery needs",
            type: .singleChoice,
            options: [
                QuestionOption(value: "cutting", label: "Cutting (calorie deficit)"),
                QuestionOption(value: "bulking", label: "Bulking (calorie surplus)"),
                QuestionOption(value: "maintaining", label: "Maintaining (maintenance calories)"),
                QuestionOption(value: "not_consistent", label: "Not consistently doing any of the above")
            ],
            next: { _, _ in .experienceLevel }
        )
        
        // 3. Cardio Preference
        steps[.cardioPreference] = FlowStep(
            id: .cardioPreference,
            prompt: "How would you like to incorporate cardio?",
            helper: "Cardio can complement your training goals",
            type: .singleChoice,
            options: [
                QuestionOption(value: "hiit", label: "HIIT", helper: "Short, intense intervals"),
                QuestionOption(value: "steady", label: "Steady State", helper: "Moderate pace for longer duration"),
                QuestionOption(value: "mixed", label: "Mix of Both", helper: "Variety of cardio styles"),
                QuestionOption(value: "minimal", label: "Minimal Cardio", helper: "Focus mainly on weights")
            ],
            next: { _, _ in .caloricTracking }
        )
        
        // 4. Sport Type
        steps[.sportType] = FlowStep(
            id: .sportType,
            prompt: "What sport are you training for?",
            type: .text,
            placeholder: "e.g., Basketball, Soccer, CrossFit",
            required: true,
            validate: { answer in
                guard let sport = answer as? String else { return "Please enter a sport" }
                if sport.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return "Please enter a sport"
                }
                return nil
            },
            next: { _, _ in .caloricTracking }
        )
        
        // 5. Experience Level
        steps[.experienceLevel] = FlowStep(
            id: .experienceLevel,
            prompt: "What is your training experience?",
            helper: "This helps us set appropriate progressions",
            type: .singleChoice,
            options: [
                QuestionOption(value: "beginner", label: "Beginner", helper: "New to training (< 6 months)"),
                QuestionOption(value: "novice", label: "Novice", helper: "6-12 months of consistent training"),
                QuestionOption(value: "intermediate", label: "Intermediate", helper: "1-3 years experience"),
                QuestionOption(value: "advanced", label: "Advanced", helper: "3+ years of serious training")
            ],
            next: { _, _ in .currentActivityLevel }
        )
        
        // 5a. Current Activity Level
        steps[.currentActivityLevel] = FlowStep(
            id: .currentActivityLevel,
            prompt: "How many times per week are you currently exercising?",
            helper: "This helps us understand your current training volume and avoid overdoing it",
            type: .singleChoice,
            options: [
                QuestionOption(value: "0", label: "0 times per week (not currently exercising)"),
                QuestionOption(value: "1-2", label: "1-2 times per week"),
                QuestionOption(value: "3-4", label: "3-4 times per week"),
                QuestionOption(value: "5-6", label: "5-6 times per week"),
                QuestionOption(value: "7+", label: "7+ times per week (very active)")
            ],
            next: { _, _ in .daysPerWeek }
        )
        
        // 6. Days Per Week
        steps[.daysPerWeek] = FlowStep(
            id: .daysPerWeek,
            prompt: "How many days per week can you train?",
            helper: "Be realistic about your schedule",
            type: .range,
            min: 1,
            max: 7,
            step: 1,
            unit: "days",
            required: true,
            validate: { answer in
                guard let days = answer as? Int else { return "Please select a number" }
                if days < 1 { return "Minimum 1 day per week" }
                if days > 7 { return "Maximum 7 days per week" }
                return nil
            },
            next: { _, _ in .sessionDuration }
        )
        
        // 9. Session Duration
        steps[.sessionDuration] = FlowStep(
            id: .sessionDuration,
            prompt: "How long can you train per session?",
            type: .range,
            min: 20,
            max: 120,
            step: 5,
            unit: "minutes",
            next: { _, _ in .targetMuscles }
        )
        
        // 9b. Session Duration Short
        steps[.sessionDurationShort] = FlowStep(
            id: .sessionDurationShort,
            prompt: "How many minutes per session?",
            helper: "We'll design an efficient program",
            type: .range,
            min: 15,
            max: 45,
            step: 5,
            unit: "minutes",
            next: { _, _ in .targetMuscles }
        )
        
        // 10. Target Muscles
        steps[.targetMuscles] = FlowStep(
            id: .targetMuscles,
            prompt: "Which muscle groups do you want to focus on?",
            helper: "Select all that apply (minimum 3)",
            type: .multiChoice,
            options: MuscleGroup.allCases.map {
                QuestionOption(value: $0.rawValue, label: $0.displayName)
            },
            required: true,
            validate: { answer in
                guard let selected = answer as? [String] else { return "Please select at least 3 muscle groups" }
                if selected.count < 3 { return "Please select at least 3 muscle groups" }
                return nil
            },
            next: { _, _ in .specificWeaknesses }
        )
        
        // 10a. Specific Weaknesses
        steps[.specificWeaknesses] = FlowStep(
            id: .specificWeaknesses,
            prompt: "Are there any specific areas you feel are weak?",
            helper: "This could be strength imbalances, mobility issues, or areas you struggle with",
            type: .multiChoice,
            options: [
                QuestionOption(value: "upper_body_strength", label: "Upper body strength"),
                QuestionOption(value: "lower_body_strength", label: "Lower body strength"),
                QuestionOption(value: "core_stability", label: "Core stability"),
                QuestionOption(value: "mobility_flexibility", label: "Mobility/Flexibility"),
                QuestionOption(value: "cardiovascular_endurance", label: "Cardiovascular endurance"),
                QuestionOption(value: "balance_coordination", label: "Balance/Coordination"),
                QuestionOption(value: "posture", label: "Posture"),
                QuestionOption(value: "none", label: "None - I feel balanced"),
                QuestionOption(value: "custom", label: "Other (specify)")
            ],
            required: true,
            next: { _, _ in .workoutSplit }
        )
        
        // 11. Workout Split
        steps[.workoutSplit] = FlowStep(
            id: .workoutSplit,
            prompt: "How would you like to organize your training?",
            type: .singleChoice,
            options: WorkoutSplit.allCases.map {
                QuestionOption(value: $0.rawValue, label: $0.rawValue, helper: $0.description)
            },
            next: { _, _ in .equipmentAvailable }
        )
        
        // 13. Equipment Available
        steps[.equipmentAvailable] = FlowStep(
            id: .equipmentAvailable,
            prompt: "What equipment do you have access to?",
            type: .multiChoice,
            options: [
                QuestionOption(value: "barbell", label: "🏋️ Barbell"),
                QuestionOption(value: "dumbbells", label: "🏋️ Dumbbells"),
                QuestionOption(value: "cables", label: "🔗 Cable Machine"),
                QuestionOption(value: "machines", label: "⚙️ Gym Machines"),
                QuestionOption(value: "kettlebells", label: "🔔 Kettlebells"),
                QuestionOption(value: "bands", label: "🎗️ Resistance Bands"),
                QuestionOption(value: "bodyweight", label: "🤸 Bodyweight Only"),
                QuestionOption(value: "pullup_bar", label: "🚪 Pull-up Bar")
            ],
            required: true,
            validate: { answer in
                guard let selected = answer as? [String] else { return "Please select at least one option" }
                if selected.isEmpty { return "Please select at least one option" }
                return nil
            },
            next: { _, _ in .trainingPreferencesLifting }
        )
        
        // 13a. Training Preferences - Lifting Style
        steps[.trainingPreferencesLifting] = FlowStep(
            id: .trainingPreferencesLifting,
            prompt: "What kinds of movements do you enjoy most?",
            helper: "This helps us select exercises that match your preferences",
            type: .multiChoice,
            options: [
                QuestionOption(value: "compound", label: "Big compound movements (squats, deadlifts, presses)"),
                QuestionOption(value: "isolation", label: "Isolation work (targeting specific muscles)"),
                QuestionOption(value: "unilateral", label: "Unilateral movements (one side at a time)"),
                QuestionOption(value: "explosive", label: "Explosive/power movements (jumps, throws)"),
                QuestionOption(value: "controlled", label: "Controlled, slow movements (time under tension)"),
                QuestionOption(value: "bodyweight", label: "Bodyweight movements"),
                QuestionOption(value: "mix", label: "Mix of everything"),
                QuestionOption(value: "open", label: "I'm open to trying new things")
            ],
            required: true,
            validate: { answer in
                guard let selected = answer as? [String] else { return "Please select at least one option" }
                if selected.isEmpty { return "Please select at least one option" }
                return nil
            },
            next: { _, _ in .trainingPreferencesCardio }
        )
        
        // 13b. Training Preferences - Cardio Style
        steps[.trainingPreferencesCardio] = FlowStep(
            id: .trainingPreferencesCardio,
            prompt: "What's your preference for cardio training?",
            helper: "This helps us structure cardio sessions that you'll actually enjoy and stick with",
            type: .singleChoice,
            options: [
                QuestionOption(value: "love", label: "I love cardio (bring it on!)"),
                QuestionOption(value: "enjoy", label: "I enjoy some cardio (moderate amounts)"),
                QuestionOption(value: "tolerate", label: "I tolerate cardio (keep it minimal)"),
                QuestionOption(value: "dislike", label: "I really dislike cardio (avoid it if possible)"),
                QuestionOption(value: "specific_types", label: "I prefer specific types")
            ],
            next: { answer, _ in
                guard let preference = answer as? String else { return .trainingIntensity }
                if preference == "specific_types" { return .cardioTypePreference }
                return .trainingIntensity
            }
        )
        
        // 13c. Cardio Type Preference (conditional)
        steps[.cardioTypePreference] = FlowStep(
            id: .cardioTypePreference,
            prompt: "Which types of cardio do you enjoy?",
            helper: "Select all that apply",
            type: .multiChoice,
            options: [
                QuestionOption(value: "running", label: "Running/Jogging"),
                QuestionOption(value: "cycling", label: "Cycling/Spinning"),
                QuestionOption(value: "swimming", label: "Swimming"),
                QuestionOption(value: "rowing", label: "Rowing"),
                QuestionOption(value: "elliptical", label: "Elliptical/Stair Climber"),
                QuestionOption(value: "hiit", label: "HIIT/Intervals"),
                QuestionOption(value: "steady_state", label: "Steady State"),
                QuestionOption(value: "walking", label: "Walking"),
                QuestionOption(value: "dance", label: "Dance/Zumba"),
                QuestionOption(value: "other", label: "Other")
            ],
            required: true,
            validate: { answer in
                guard let selected = answer as? [String] else { return "Please select at least one type" }
                if selected.isEmpty { return "Please select at least one type" }
                return nil
            },
            next: { _, _ in .trainingIntensity }
        )
        
        // 13d. Training Intensity Preference
        steps[.trainingIntensity] = FlowStep(
            id: .trainingIntensity,
            prompt: "How intense do you like your workouts to feel?",
            helper: "This helps us set appropriate rest times and volume",
            type: .singleChoice,
            options: [
                QuestionOption(value: "light", label: "Light and easy (I prefer steady pace)"),
                QuestionOption(value: "moderate", label: "Moderate (challenging but sustainable)"),
                QuestionOption(value: "high", label: "High intensity (I like to push hard)"),
                QuestionOption(value: "varied", label: "Varied (mix of intensities)")
            ],
            next: { _, _ in .injuryCheck }
        )
        
        // 14. Injury Check
        steps[.injuryCheck] = FlowStep(
            id: .injuryCheck,
            prompt: "Do you have any injuries or physical limitations?",
            type: .yesNo,
            next: { answer, _ in
                guard let hasInjuries = answer as? Bool else { return .exerciseVariety }
                if hasInjuries { return .injuryDetails }
                return .exerciseVariety
            }
        )
        
        // 15. Injury Details
        steps[.injuryDetails] = FlowStep(
            id: .injuryDetails,
            prompt: "Describe your injuries or limitations",
            helper: "We'll avoid exercises that could aggravate these areas",
            type: .text,
            placeholder: "e.g., Lower back pain, shoulder impingement",
            next: { _, _ in .exerciseVariety }
        )
        
        // 16. Exercise Variety
        steps[.exerciseVariety] = FlowStep(
            id: .exerciseVariety,
            prompt: "How much exercise variety do you prefer?",
            helper: "Some prefer consistency, others like frequent changes",
            type: .singleChoice,
            options: [
                QuestionOption(value: "consistent", label: "Consistent", helper: "Same exercises each week"),
                QuestionOption(value: "balanced", label: "Balanced", helper: "Some variety, core stays same"),
                QuestionOption(value: "varied", label: "Highly Varied", helper: "Frequent exercise changes")
            ],
            next: { _, _ in .supersets }
        )
        
        // 17. Supersets
        steps[.supersets] = FlowStep(
            id: .supersets,
            prompt: "Would you like to include supersets?",
            helper: "Pair exercises to save time and increase intensity",
            type: .yesNo,
            next: { _, _ in .programDuration }
        )
        
        // 18. Program Duration
        steps[.programDuration] = FlowStep(
            id: .programDuration,
            prompt: "How long should this program last?",
            type: .range,
            min: 1,
            max: 24,
            step: 1,
            unit: "weeks",
            next: { _, _ in .result }
        )
        
        return FlowConfig(start: .planName, steps: steps, estimatedLength: 18)
    }
}
