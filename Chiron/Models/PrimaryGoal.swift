import Foundation

/// Represents the user's primary fitness goal
enum PrimaryGoal: String, CaseIterable, Identifiable, Codable {
    // Declaration order = display order (ForEach iterates allCases).
    // Raw values are kept intact so existing saved profiles still decode.
    case loseFat = "lose_fat"
    case buildMuscle = "build_muscle"
    case getStronger = "get_stronger"
    case rehabPreventInjury = "rehab_prevent_injury"
    case improveHealthLongevity = "improve_health_longevity"
    case enhanceAthleticPerformance = "enhance_athletic_performance"
    case improveEndurance = "improve_endurance"
    case getToned = "get_toned"

    var id: String { rawValue }

    /// Display name for the UI
    var displayName: String {
        switch self {
        case .loseFat:
            return "Lose fat"
        case .buildMuscle:
            return "Build muscle"
        case .getStronger:
            return "Get stronger"
        case .rehabPreventInjury:
            return "Rehab or prevent injury"
        case .improveHealthLongevity:
            return "Support health & longevity"
        case .enhanceAthleticPerformance:
            return "Enhance athletic performance"
        case .improveEndurance:
            return "Boost endurance"
        case .getToned:
            return "Get toned"
        }
    }
    
    /// Helper text describing each goal
    var description: String {
        switch self {
        case .loseFat:
            return "Focus on fat loss while maintaining muscle mass"
        case .buildMuscle:
            return "Maximize muscle growth and hypertrophy"
        case .getStronger:
            return "Increase strength and power output"
        case .rehabPreventInjury:
            return "Recover from injury or prevent future issues"
        case .improveHealthLongevity:
            return "Focus on overall health and wellness"
        case .enhanceAthleticPerformance:
            return "Optimize sport-specific performance"
        case .improveEndurance:
            return "Build stamina and cardiovascular fitness"
        case .getToned:
            return "Build lean muscle and improve definition"
        }
    }

    /// Goal-specific tempo reference points. `nil` means tempo is not coached
    /// for this goal (on-device tempo issue codes stay suppressed).
    ///
    /// Values are soft references, not thresholds — see `TempoTargets`.
    var tempoTargets: TempoTargets? {
        switch self {
        case .buildMuscle:
            // Slow eccentric + hold the stretch. Concentric is "as fast as
            // possible" for hypertrophy concentric intent — not coached.
            return TempoTargets(
                minEccentricMs: 2500,
                maxConcentricMs: nil,
                minStretchPauseMs: 1000
            )
        case .getStronger:
            // 1000 ms eccentric floor so the lifter stays in control under
            // heavy load. Concentric should be explosive — not coached.
            return TempoTargets(
                minEccentricMs: 1000,
                maxConcentricMs: 3000,
                minStretchPauseMs: nil
            )
        case .enhanceAthleticPerformance:
            // Same control floor as strength; dawdling concentric is flagged
            // because the whole point is developing power output.
            return TempoTargets(
                minEccentricMs: 1000,
                maxConcentricMs: 3000,
                minStretchPauseMs: nil
            )
        case .rehabPreventInjury:
            // Slow controlled eccentric; no cue on concentric (grinding a
            // rehab rep shouldn't get flagged as "dawdling").
            return TempoTargets(
                minEccentricMs: 2500,
                maxConcentricMs: nil,
                minStretchPauseMs: nil
            )
        case .loseFat, .getToned, .improveEndurance, .improveHealthLongevity:
            return nil
        }
    }
}

/// Manager for persisting user preferences
class UserPreferencesManager: ObservableObject {
    static let shared = UserPreferencesManager()
    
    @Published var primaryGoal: PrimaryGoal? {
        didSet {
            persistGoal()
            OnDevicePoseManager.shared.tempoTargets = primaryGoal?.tempoTargets
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
    
    /// Hook for future remote sync. `persistGoal()` only calls this when `primaryGoal` is non-nil.
    private func syncToBackend() {
        // TODO: Push goal to backend when account sync exists.
    }
    
    private func trackGoalChanged(from oldGoal: PrimaryGoal, to newGoal: PrimaryGoal?) {
        AnalyticsManager.shared.trackGoalChanged(
            from: oldGoal.rawValue,
            to: newGoal?.rawValue ?? "none",
            source: "home_subtitle"
        )
    }
}




