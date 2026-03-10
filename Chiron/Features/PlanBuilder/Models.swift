import Foundation

// MARK: - Training Plan Models

struct TrainingPlan: Codable, Identifiable {
    let id: UUID
    let name: String
    let duration: Int // weeks
    let daysPerWeek: Int
    let goals: [FocusArea]
    let targetMuscles: [MuscleGroup]
    let split: WorkoutSplit
    let injuries: [Injury]
    let varietyContinuum: VarietyContinuum
    let varietyLevel: VarietyLevel // Legacy - kept for backward compatibility
    let supersets: Bool
    let weeks: [TrainingWeek]
    let createdAt: Date
    let version: String = "1.0"
    
    init(id: UUID = UUID(), name: String, duration: Int, daysPerWeek: Int, goals: [FocusArea], targetMuscles: [MuscleGroup], 
         split: WorkoutSplit, injuries: [Injury], varietyContinuum: VarietyContinuum, 
         supersets: Bool, weeks: [TrainingWeek]) {
        self.id = id
        self.name = name
        self.duration = duration
        self.daysPerWeek = daysPerWeek
        self.goals = goals
        self.targetMuscles = targetMuscles
        self.split = split
        self.injuries = injuries
        self.varietyContinuum = varietyContinuum
        self.varietyLevel = .medium // Default fallback
        self.supersets = supersets
        self.weeks = weeks
        self.createdAt = Date()
    }
    
    // Custom decoding for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        duration = try container.decode(Int.self, forKey: .duration)
        daysPerWeek = try container.decode(Int.self, forKey: .daysPerWeek)
        goals = try container.decodeIfPresent([FocusArea].self, forKey: .goals) ?? []
        targetMuscles = try container.decodeIfPresent([MuscleGroup].self, forKey: .targetMuscles) ?? []
        split = try container.decode(WorkoutSplit.self, forKey: .split)
        injuries = try container.decodeIfPresent([Injury].self, forKey: .injuries) ?? []
        varietyContinuum = try container.decodeIfPresent(VarietyContinuum.self, forKey: .varietyContinuum) ?? 0.5
        varietyLevel = try container.decodeIfPresent(VarietyLevel.self, forKey: .varietyLevel) ?? .medium
        supersets = try container.decodeIfPresent(Bool.self, forKey: .supersets) ?? false
        weeks = try container.decode([TrainingWeek].self, forKey: .weeks)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(duration, forKey: .duration)
        try container.encode(daysPerWeek, forKey: .daysPerWeek)
        try container.encode(goals, forKey: .goals)
        try container.encode(targetMuscles, forKey: .targetMuscles)
        try container.encode(split, forKey: .split)
        try container.encode(injuries, forKey: .injuries)
        try container.encode(varietyContinuum, forKey: .varietyContinuum)
        try container.encode(varietyLevel, forKey: .varietyLevel)
        try container.encode(supersets, forKey: .supersets)
        try container.encode(weeks, forKey: .weeks)
        try container.encode(createdAt, forKey: .createdAt)
    }
    
    private enum CodingKeys: String, CodingKey {
        case name, duration, daysPerWeek, targetMuscles, split, injuries
        case id, goals, varietyContinuum, varietyLevel, supersets, weeks, createdAt
    }
    
    // Legacy initializer for backward compatibility
    init(id: UUID = UUID(), name: String, duration: Int, daysPerWeek: Int, goals: [FocusArea], targetMuscles: [MuscleGroup], 
         split: WorkoutSplit, injuries: [Injury], varietyLevel: VarietyLevel, 
         supersets: Bool, weeks: [TrainingWeek]) {
        self.id = id
        self.name = name
        self.duration = duration
        self.daysPerWeek = daysPerWeek
        self.goals = goals
        self.targetMuscles = targetMuscles
        self.split = split
        self.injuries = injuries
        self.varietyLevel = varietyLevel
        self.varietyContinuum = varietyLevel.toContinuum
        self.supersets = supersets
        self.weeks = weeks
        self.createdAt = Date()
    }
}

struct TrainingWeek: Codable, Identifiable {
    let id = UUID()
    let weekNumber: Int
    let days: [TrainingDay]
    
    init(weekNumber: Int, days: [TrainingDay]) {
        self.weekNumber = weekNumber
        self.days = days
    }
    
    private enum CodingKeys: String, CodingKey {
        case weekNumber, days
    }
}

struct TrainingDay: Codable, Identifiable {
    let id = UUID()
    let dayNumber: Int
    let name: String
    let exercises: [WorkoutExercise]
    let duration: Int // minutes
    let difficulty: DifficultyLevel
    
    init(dayNumber: Int, name: String, exercises: [WorkoutExercise], duration: Int, difficulty: DifficultyLevel) {
        self.dayNumber = dayNumber
        self.name = name
        self.exercises = exercises
        self.duration = duration
        self.difficulty = difficulty
    }
    
    private enum CodingKeys: String, CodingKey {
        case dayNumber, name, exercises, duration, difficulty
    }
}

struct WorkoutExercise: Codable, Identifiable {
    let id = UUID()
    let name: String
    let category: ExerciseCategory
    let sets: Int
    let reps: String // e.g., "8-12", "3x5", "30s"
    let restTime: Int // seconds
    let notes: String?
    let isSuperset: Bool
    let supersetGroup: Int?
    let phase: String? // e.g., "Warm-up", "Main Workout", "Cool-down"
    
    init(name: String, category: ExerciseCategory, sets: Int, reps: String, 
         restTime: Int, notes: String? = nil, isSuperset: Bool = false, supersetGroup: Int? = nil, phase: String? = nil) {
        self.name = name
        self.category = category
        self.sets = sets
        self.reps = reps
        self.restTime = restTime
        self.notes = notes
        self.isSuperset = isSuperset
        self.supersetGroup = supersetGroup
        self.phase = phase
    }
    
    private enum CodingKeys: String, CodingKey {
        case name, category, sets, reps, restTime, notes, isSuperset, supersetGroup, phase
    }
}

// MARK: - Enums

enum FocusArea: String, CaseIterable, Codable {
    case strength = "Strength"
    case hypertrophy = "Muscle Building"
    case endurance = "Endurance"
    case mobility = "Mobility"
    case power = "Power"
    case stability = "Injury Prevention"
    
    var icon: String {
        switch self {
        case .strength: return "dumbbell"
        case .hypertrophy: return "figure.strengthtraining.traditional"
        case .endurance: return "heart"
        case .mobility: return "figure.flexibility"
        case .power: return "bolt"
        case .stability: return "balance"
        }
    }
}

enum MuscleGroup: String, CaseIterable, Codable {
    case quadriceps
    case hamstrings
    case glutes
    case calves
    case chest
    case back
    case lats
    case traps
    case shoulders
    case frontDelts
    case rearDelts
    case biceps
    case triceps
    case forearms
    case core
    case obliques
    case erectors
    case lowerBack
    case abs
    case abductors
    case adductors
    
    var icon: String {
        switch self {
        case .chest, .shoulders, .frontDelts, .rearDelts, .biceps, .triceps, .forearms:
            return "figure.arms.open"
        case .back, .lats, .traps, .erectors, .lowerBack, .core, .obliques, .abs:
            return "figure.core.training"
        case .quadriceps, .hamstrings, .glutes, .calves, .abductors, .adductors:
            return "figure.walk"
        }
    }
    
    var imageName: String {
        switch self {
        case .chest:
            return "Chest Icon"
        case .back, .lats, .rearDelts:
            return "Back Icon"
        case .traps:
            return "Trapezius Icon"
        case .shoulders, .frontDelts:
            return "Front Deltoid Icon"
        case .biceps:
            return "Bicep Icon"
        case .triceps:
            return "Tricep Icon"
        case .forearms:
            return "Forearms Icon"
        case .quadriceps:
            return "Quads Icon"
        case .hamstrings:
            return "Hamstrings Icon"
        case .glutes:
            return "Glutes Icon"
        case .calves:
            return "Calves Icon"
        case .abductors:
            return "Abductors Icon"
        case .adductors:
            return "Adductors Icon"
        case .core, .obliques, .abs:
            return "Abs Icon"
        case .erectors, .lowerBack:
            return "Lower Back Icon"
        }
    }
    
    var displayName: String {
        switch self {
        case .quadriceps:
            return "Quadriceps"
        case .frontDelts:
            return "Front Delts"
        case .rearDelts:
            return "Rear Delts"
        case .lowerBack:
            return "Lower Back"
        case .back:
            return "Middle Back" // Display name for the general back muscle group
        case .adductors:
            return "Inner Thighs"
        default:
            return rawValue.capitalized
        }
    }
}

enum WorkoutSplit: String, CaseIterable, Codable {
    case fullBody = "Full Body"
    case upperLower = "Upper/Lower"
    case pushPullLegs = "Push/Pull/Legs"
    case custom = "Custom"
    
    var description: String {
        switch self {
        case .fullBody: return "Work all muscle groups each session"
        case .upperLower: return "Alternate between upper and lower body"
        case .pushPullLegs: return "Push, pull, and leg focused days"
        case .custom: return "Create your own split"
        }
    }
}

// MARK: - Injury System

struct InjuryNote: Codable, Equatable, Identifiable {
    let id = UUID()
    let raw: String
    
    init(raw: String) {
        self.raw = raw
    }
    
    private enum CodingKeys: String, CodingKey {
        case raw
    }
}

enum InjuryConstraint: String, CaseIterable, Codable {
    case knee = "knee"
    case shoulder = "shoulder"
    case lowBack = "lowBack"
    case upperBack = "upperBack"
    case ankle = "ankle"
    case wrist = "wrist"
    case hip = "hip"
    case neck = "neck"
    case generalPain = "generalPain"
    
    var displayName: String {
        switch self {
        case .knee: return "Knee"
        case .shoulder: return "Shoulder"
        case .lowBack: return "Low Back"
        case .upperBack: return "Upper Back"
        case .ankle: return "Ankle"
        case .wrist: return "Wrist"
        case .hip: return "Hip"
        case .neck: return "Neck"
        case .generalPain: return "General Pain"
        }
    }
}

struct InjuryProfile: Codable, Equatable {
    var constraints: Set<InjuryConstraint>
    var notes: [InjuryNote]
    
    init(constraints: Set<InjuryConstraint> = [], notes: [InjuryNote] = []) {
        self.constraints = constraints
        self.notes = notes
    }
}

// MARK: - Injury Parser

struct InjuryParser {
    private static let lexicon: [InjuryConstraint: [String]] = [
        .knee: ["knee", "knees", "patella", "patellar", "quad tendon", "it band", "iliotibial"],
        .shoulder: ["shoulder", "shoulders", "rotator cuff", "impingement", "ac joint", "deltoid"],
        .lowBack: ["low back", "lower back", "lumbar", "si joint", "sacroiliac", "spine"],
        .upperBack: ["upper back", "thoracic", "rhomboid", "trap", "trapezius"],
        .ankle: ["ankle", "ankles", "achilles", "calf", "calves", "shin", "shins"],
        .wrist: ["wrist", "wrists", "forearm", "forearms", "elbow", "elbows"],
        .hip: ["hip", "hips", "groin", "adductor", "hip flexor", "glute"],
        .neck: ["neck", "cervical", "trap", "trapezius"],
        .generalPain: ["pain", "hurt", "sore", "ache", "stiff", "tight", "uncomfortable"]
    ]
    
    static func parse(_ text: String, notes: [InjuryNote]) -> InjuryProfile {
        let lower = text.lowercased()
        var found = Set<InjuryConstraint>()
        
        // Check each constraint's keywords
        for (constraint, keywords) in lexicon {
            if keywords.contains(where: { lower.contains($0) }) {
                found.insert(constraint)
            }
        }
        
        // If no specific constraints found but there's pain language, add general pain
        if found.isEmpty && lexicon[.generalPain]!.contains(where: { lower.contains($0) }) {
            found.insert(.generalPain)
        }
        
        return InjuryProfile(constraints: found, notes: notes)
    }
}

// MARK: - Legacy Injury Enum (kept for backward compatibility)

enum Injury: String, CaseIterable, Codable {
    case knee = "Knee"
    case shoulder = "Shoulder"
    case back = "Back"
    case ankle = "Ankle"
    case wrist = "Wrist"
    case hip = "Hip"
    case neck = "Neck"
    case none = "None"
    
    var icon: String {
        switch self {
        case .knee: return "figure.walk"
        case .shoulder: return "figure.arms.open"
        case .back: return "figure.core.training"
        case .ankle: return "figure.walk"
        case .wrist: return "hand.raised"
        case .hip: return "figure.flexibility"
        case .neck: return "figure.core.training"
        case .none: return "checkmark.circle"
        }
    }
}

// MARK: - Variety Continuum System

// 0.0 = Consistent, 0.5 = Balanced, 1.0 = Varied
typealias VarietyContinuum = Double // clamp 0...1

enum VarietyBand: String, CaseIterable {
    case consistent = "Consistent"
    case balanced = "Balanced"
    case varied = "Varied"
    
    var description: String {
        switch self {
        case .consistent: return "Fewer rotations, repeat accessories"
        case .balanced: return "Mix of repeat & new accessories"
        case .varied: return "Frequent rotations, higher novelty"
        }
    }
}

extension VarietyContinuum {
    var band: VarietyBand {
        switch self {
        case ..<0.33: return .consistent
        case 0.33..<0.66: return .balanced
        default: return .varied
        }
    }
    
    func clamped(to range: ClosedRange<Double>) -> Double {
        return max(range.lowerBound, min(range.upperBound, self))
    }
}

// MARK: - Variety Policy

struct VarietyPolicy {
    let accessoryRotationRate: Double   // % of accessories swapped weekly
    let mainLiftVariantRate: Double     // chance to alternate main variations week to week
    let supersetBias: Double            // probability to pair non-competing accessories
    
    static func from(_ v: VarietyContinuum) -> VarietyPolicy {
        let r = max(0, min(1, v))
        return VarietyPolicy(
            accessoryRotationRate: 0.10 + 0.60 * r,   // 10% → 70%
            mainLiftVariantRate:   0.00 + 0.30 * r,   // 0%  → 30%
            supersetBias:          0.20 + 0.40 * r    // 20% → 60%
        )
    }
}

// MARK: - Legacy VarietyLevel (kept for backward compatibility)

enum VarietyLevel: String, CaseIterable, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    
    var description: String {
        switch self {
        case .low: return "Stick to basic exercises"
        case .medium: return "Mix of basic and advanced"
        case .high: return "Lots of exercise variety"
        }
    }
    
    // Migration helper
    var toContinuum: VarietyContinuum {
        switch self {
        case .low: return 0.15
        case .medium: return 0.5
        case .high: return 0.85
        }
    }
}

enum ExerciseCategory: String, CaseIterable, Codable {
    case compound = "Compound"
    case isolation = "Isolation"
    case cardio = "Cardio"
    case mobility = "Mobility"
    case plyometric = "Plyometric"
    case functional = "Functional"
}

enum DifficultyLevel: String, CaseIterable, Codable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    
    var color: String {
        switch self {
        case .beginner: return "green"
        case .intermediate: return "orange"
        case .advanced: return "red"
        }
    }
}

// MARK: - Custom Split Models

enum DayIntent: String, Codable, CaseIterable {
    case fullBody = "Full Body"
    case upper = "Upper Body"
    case lower = "Lower Body"
    case push = "Push"
    case pull = "Pull"
    case legs = "Legs"
    case arms = "Arms"
    case customMuscles = "Custom Muscles"
    
    var description: String {
        switch self {
        case .fullBody: return "Work all muscle groups"
        case .upper: return "Chest, back, shoulders, arms"
        case .lower: return "Quads, hamstrings, glutes, calves"
        case .push: return "Chest, shoulders, triceps"
        case .pull: return "Back, biceps, rear delts"
        case .legs: return "Quads, hamstrings, glutes"
        case .arms: return "Biceps and triceps"
        case .customMuscles: return "Choose specific muscles"
        }
    }
}

struct CustomDaySpec: Codable, Equatable {
    var muscles: Set<MuscleGroup>
    
    init(muscles: Set<MuscleGroup> = []) {
        self.muscles = muscles
    }
}

struct CustomSplit: Codable, Equatable {
    // Indexed 1...daysPerWeek (UI shows "Day X")
    var dayIntents: [DayIntent]
    var customSpecs: [Int: CustomDaySpec] // key = 1-based day index for .customMuscles
    
    init(dayIntents: [DayIntent], customSpecs: [Int: CustomDaySpec] = [:]) {
        self.dayIntents = dayIntents
        self.customSpecs = customSpecs
    }
}

// MARK: - Plan Builder Input Model

struct PlanBuilderInput: Codable {
    var name: String = ""
    var goals: [FocusArea] = []
    var sessionMinutes: Int = 45 // minutes per session
    var daysPerWeek: Int = 3
    var programDuration: Int = 8 // weeks
    var targetMuscles: [MuscleGroup] = []
    var split: WorkoutSplit = .fullBody
    var injuries: [Injury] = [] // Legacy - kept for backward compatibility
    var injuryNotes: [InjuryNote] = [] // New multi-entry system
    var injuryProfile: InjuryProfile? // Derived at generation
    var varietyContinuum: VarietyContinuum = 0.5 // New continuum system
    var varietyLevel: VarietyLevel = .medium // Legacy - kept for backward compatibility
    var supersets: Bool = false
    var customSplit: CustomSplit?
    
    var isValid: Bool {
        let nameValid = !name.isEmpty
        let goalsValid = !goals.isEmpty
        let sessionValid = sessionMinutes > 0
        let daysValid = daysPerWeek > 0 && daysPerWeek <= 7
        let durationValid = programDuration > 0
        
        
        return nameValid && goalsValid && sessionValid && daysValid && durationValid
    }
    
    // Default initializer
    init() {
        self.name = ""
        self.goals = []
        self.sessionMinutes = 45
        self.daysPerWeek = 3
        self.programDuration = 8
        self.targetMuscles = []
        self.split = .fullBody
        self.injuries = []
        self.injuryNotes = []
        self.injuryProfile = nil
        self.varietyContinuum = 0.5
        self.varietyLevel = .medium
        self.supersets = false
        self.customSplit = nil
    }
    
    // Custom decoding for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        goals = try container.decodeIfPresent([FocusArea].self, forKey: .goals) ?? []
        // Backward compatibility: older saves used `duration` to represent minutes
        let legacyDuration = try container.decodeIfPresent(Int.self, forKey: .duration)
        sessionMinutes = try container.decodeIfPresent(Int.self, forKey: .sessionMinutes) ?? legacyDuration ?? 45
        daysPerWeek = try container.decodeIfPresent(Int.self, forKey: .daysPerWeek) ?? 3
        programDuration = try container.decodeIfPresent(Int.self, forKey: .programDuration) ?? 8
        targetMuscles = try container.decodeIfPresent([MuscleGroup].self, forKey: .targetMuscles) ?? []
        split = try container.decodeIfPresent(WorkoutSplit.self, forKey: .split) ?? .fullBody
        injuries = try container.decodeIfPresent([Injury].self, forKey: .injuries) ?? []
        injuryNotes = try container.decodeIfPresent([InjuryNote].self, forKey: .injuryNotes) ?? []
        injuryProfile = try container.decodeIfPresent(InjuryProfile.self, forKey: .injuryProfile)
        supersets = try container.decodeIfPresent(Bool.self, forKey: .supersets) ?? false
        customSplit = try container.decodeIfPresent(CustomSplit.self, forKey: .customSplit)
        
        // Handle variety migration
        if let continuum = try container.decodeIfPresent(VarietyContinuum.self, forKey: .varietyContinuum) {
            varietyContinuum = continuum
            varietyLevel = .medium // Default fallback
        } else if let level = try container.decodeIfPresent(VarietyLevel.self, forKey: .varietyLevel) {
            varietyLevel = level
            varietyContinuum = level.toContinuum
        } else {
            varietyContinuum = 0.5
            varietyLevel = .medium
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(goals, forKey: .goals)
        try container.encode(sessionMinutes, forKey: .sessionMinutes)
        try container.encode(daysPerWeek, forKey: .daysPerWeek)
        try container.encode(programDuration, forKey: .programDuration)
        try container.encode(targetMuscles, forKey: .targetMuscles)
        try container.encode(split, forKey: .split)
        try container.encode(injuries, forKey: .injuries)
        try container.encode(injuryNotes, forKey: .injuryNotes)
        try container.encodeIfPresent(injuryProfile, forKey: .injuryProfile)
        try container.encode(varietyContinuum, forKey: .varietyContinuum)
        try container.encode(varietyLevel, forKey: .varietyLevel)
        try container.encode(supersets, forKey: .supersets)
        try container.encodeIfPresent(customSplit, forKey: .customSplit)
    }
    
    private enum CodingKeys: String, CodingKey {
        case name, goals, daysPerWeek, programDuration
        case targetMuscles, split, injuries, injuryNotes, injuryProfile
        case varietyContinuum, varietyLevel, supersets, customSplit
        case sessionMinutes
        case duration // Keep for backward compatibility with decoding
    }
}
