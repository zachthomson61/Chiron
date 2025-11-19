import Foundation

/// Represents the user's primary fitness goal
enum PrimaryGoal: String, CaseIterable, Identifiable, Codable {
    case loseFat = "lose_fat"
    case getToned = "get_toned"
    case buildMuscle = "build_muscle"
    case getStronger = "get_stronger"
    case improveEndurance = "improve_endurance"
    case enhanceAthleticPerformance = "enhance_athletic_performance"
    case improveHealthLongevity = "improve_health_longevity"
    case rehabPreventInjury = "rehab_prevent_injury"
    
    var id: String { rawValue }
    
    /// Display name for the UI
    var displayName: String {
        switch self {
        case .loseFat:
            return "Lose fat"
        case .getToned:
            return "Get toned"
        case .buildMuscle:
            return "Build muscle"
        case .getStronger:
            return "Get stronger"
        case .improveEndurance:
            return "Improve endurance"
        case .enhanceAthleticPerformance:
            return "Enhance athletic performance"
        case .improveHealthLongevity:
            return "Improve health & longevity"
        case .rehabPreventInjury:
            return "Rehabilitate or prevent injury"
        }
    }
    
    /// Helper text describing each goal
    var description: String {
        switch self {
        case .loseFat:
            return "Focus on fat loss while maintaining muscle mass"
        case .getToned:
            return "Build lean muscle and improve definition"
        case .buildMuscle:
            return "Maximize muscle growth and hypertrophy"
        case .getStronger:
            return "Increase strength and power output"
        case .improveEndurance:
            return "Build stamina and cardiovascular fitness"
        case .enhanceAthleticPerformance:
            return "Optimize sport-specific performance"
        case .improveHealthLongevity:
            return "Focus on overall health and wellness"
        case .rehabPreventInjury:
            return "Recover from injury or prevent future issues"
        }
    }
}

/// Manager for persisting user preferences
class UserPreferencesManager: ObservableObject {
    static let shared = UserPreferencesManager()
    
    @Published var primaryGoal: PrimaryGoal? {
        didSet {
            persistGoal()
            if let oldValue = oldValue {
                trackGoalChanged(from: oldValue, to: primaryGoal)
            }
        }
    }
    
    private let primaryGoalKey = "user_primary_goal"
    
    init() {
        loadGoal()
    }
    
    private func loadGoal() {
        if let savedGoalString = UserDefaults.standard.string(forKey: primaryGoalKey),
           let savedGoal = PrimaryGoal(rawValue: savedGoalString) {
            self.primaryGoal = savedGoal
        }
    }
    
    private func persistGoal() {
        if let goal = primaryGoal {
            UserDefaults.standard.set(goal.rawValue, forKey: primaryGoalKey)
            
            // Sync to backend if available
            syncToBackend()
        } else {
            UserDefaults.standard.removeObject(forKey: primaryGoalKey)
        }
    }
    
    private func syncToBackend() {
        // TODO: Sync with Firebase/backend when available
        guard let goal = primaryGoal else { return }
        print("📱 Syncing primary goal to backend: \(goal.displayName)")
    }
    
    private func trackGoalChanged(from oldGoal: PrimaryGoal, to newGoal: PrimaryGoal?) {
        AnalyticsManager.shared.trackGoalChanged(
            from: oldGoal.rawValue,
            to: newGoal?.rawValue ?? "none",
            source: "home_subtitle"
        )
    }
}




