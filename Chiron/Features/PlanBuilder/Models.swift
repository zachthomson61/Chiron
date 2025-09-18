import Foundation

// MARK: - Training Plan Models

struct TrainingPlan: Codable, Identifiable {
    let id = UUID()
    let name: String
    let duration: Int // weeks
    let daysPerWeek: Int
    let targetMuscles: [MuscleGroup]
    let split: WorkoutSplit
    let injuries: [Injury]
    let varietyContinuum: VarietyContinuum
    let varietyLevel: VarietyLevel // Legacy - kept for backward compatibility
    let supersets: Bool
    let weeks: [TrainingWeek]
    let createdAt: Date
    let version: String = "1.0"
    
    init(name: String, duration: Int, daysPerWeek: Int, targetMuscles: [MuscleGroup], 
         split: WorkoutSplit, injuries: [Injury], varietyContinuum: VarietyContinuum, 
         supersets: Bool, weeks: [TrainingWeek]) {
        self.name = name
        self.duration = duration
        self.daysPerWeek = daysPerWeek
        self.targetMuscles = targetMuscles
        self.split = split
        self.injuries = injuries
        self.varietyContinuum = varietyContinuum
        self.varietyLevel = .medium // Default fallback
        self.supersets = supersets
        self.weeks = weeks
        self.createdAt = Date()
    }
    
    // Legacy initializer for backward compatibility
    init(name: String, duration: Int, daysPerWeek: Int, targetMuscles: [MuscleGroup], 
         split: WorkoutSplit, injuries: [Injury], varietyLevel: VarietyLevel, 
         supersets: Bool, weeks: [TrainingWeek]) {
        self.name = name
        self.duration = duration
        self.daysPerWeek = daysPerWeek
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
    
    init(name: String, category: ExerciseCategory, sets: Int, reps: String, 
         restTime: Int, notes: String? = nil, isSuperset: Bool = false, supersetGroup: Int? = nil) {
        self.name = name
        self.category = category
        self.sets = sets
        self.reps = reps
        self.restTime = restTime
        self.notes = notes
        self.isSuperset = isSuperset
        self.supersetGroup = supersetGroup
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
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case trapezius = "Trapezius"
    case forearms = "Forearms"
    case quads = "Quads"
    case hamstrings = "Hamstrings"
    case glutes = "Glutes"
    case calves = "Calves"
    case abductors = "Abductors"
    case adductors = "Adductors"
    case abs = "Abs"
    case lowerBack = "Lower Back"
    
    var icon: String {
        switch self {
        case .chest: return "figure.arms.open"
        case .back: return "figure.core.training"
        case .shoulders: return "figure.arms.open"
        case .biceps: return "figure.arms.open"
        case .triceps: return "figure.arms.open"
        case .trapezius: return "figure.core.training"
        case .forearms: return "figure.arms.open"
        case .quads: return "figure.walk"
        case .hamstrings: return "figure.walk"
        case .glutes: return "figure.walk"
        case .calves: return "figure.walk"
        case .abductors: return "figure.walk"
        case .adductors: return "figure.walk"
        case .abs: return "figure.core.training"
        case .lowerBack: return "figure.core.training"
        }
    }
    
    var imageName: String {
        switch self {
        case .chest: return "Chest_Icon"
        case .back: return "Back_Icon"
        case .shoulders: return "Front_Deltoid_Icon"
        case .biceps: return "Bicep_Icon"
        case .triceps: return "Tricep_Icon"
        case .trapezius: return "Trapezius_Icon"
        case .forearms: return "Forearms_Icon"
        case .quads: return "Quads_Icon"
        case .hamstrings: return "Hamstrings_Icon"
        case .glutes: return "Glutes_Icon"
        case .calves: return "Calves_Icon"
        case .abductors: return "Abductors_Icon"
        case .adductors: return "Adductors_Icon"
        case .abs: return "Abs_Icon"
        case .lowerBack: return "Lower_Back_Icon"
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
    var duration: Int = 4 // weeks
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
        !name.isEmpty && 
        !goals.isEmpty && 
        duration > 0 && 
        daysPerWeek > 0 && 
        daysPerWeek <= 7 &&
        programDuration > 0
    }
    
    // Default initializer
    init() {
        self.name = ""
        self.goals = []
        self.duration = 4
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
        duration = try container.decodeIfPresent(Int.self, forKey: .duration) ?? 4
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
    
    private enum CodingKeys: String, CodingKey {
        case name, goals, duration, daysPerWeek, programDuration
        case targetMuscles, split, injuries, injuryNotes, injuryProfile
        case varietyContinuum, varietyLevel, supersets, customSplit
    }
}
