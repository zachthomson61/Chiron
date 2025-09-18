import Foundation
import Combine
import SwiftUI

// MARK: - Custom Split View Model

@MainActor
final class CustomSplitViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var selectedDayIndex: Int = 0 // 0-based in VM, UI shows 1-based
    @Published var intents: [DayIntent] = []
    @Published var customSpecs: [Int: CustomDaySpec] = [:] // key = 0-based index in VM
    
    // MARK: - Private Properties
    
    private let input: PlanBuilderInput
    private var onSave: (CustomSplit) -> Void
    
    // MARK: - Computed Properties
    
    var days: Int {
        input.daysPerWeek
    }
    
    var canSave: Bool {
        intents.count == days && 
        intents.enumerated().allSatisfy { idx, intent in
            intent != .customMuscles || (customSpecs[idx]?.muscles.isEmpty == false)
        }
    }
    
    var currentDayIntent: DayIntent {
        get {
            guard selectedDayIndex < intents.count else { return .fullBody }
            return intents[selectedDayIndex]
        }
        set {
            guard selectedDayIndex < intents.count else { return }
            intents[selectedDayIndex] = newValue
            
            // Clear custom specs if not custom muscles
            if newValue != .customMuscles {
                customSpecs.removeValue(forKey: selectedDayIndex)
            }
        }
    }
    
    var currentDayCustomMuscles: Set<MuscleGroup> {
        get {
            customSpecs[selectedDayIndex]?.muscles ?? []
        }
        set {
            customSpecs[selectedDayIndex] = CustomDaySpec(muscles: newValue)
        }
    }
    
    // MARK: - Initialization
    
    init(input: PlanBuilderInput, onSave: @escaping (CustomSplit) -> Void) {
        self.input = input
        self.onSave = onSave
        setupDefaults()
    }
    
    // MARK: - Public Methods
    
    func selectDay(_ index: Int) {
        guard index >= 0 && index < days else { return }
        selectedDayIndex = index
    }
    
    func toggleCustomMuscle(_ muscle: MuscleGroup) {
        var muscles = currentDayCustomMuscles
        if muscles.contains(muscle) {
            muscles.remove(muscle)
        } else {
            muscles.insert(muscle)
        }
        currentDayCustomMuscles = muscles
    }
    
    func save() {
        guard canSave else { return }
        
        // Convert 0-based indices to 1-based for CustomSplit
        var oneBasedCustomSpecs: [Int: CustomDaySpec] = [:]
        for (zeroBasedIndex, spec) in customSpecs {
            oneBasedCustomSpecs[zeroBasedIndex + 1] = spec
        }
        
        let customSplit = CustomSplit(
            dayIntents: intents,
            customSpecs: oneBasedCustomSpecs
        )
        
        onSave(customSplit)
    }
    
    // MARK: - Private Methods
    
    private func setupDefaults() {
        // Initialize intents array with default values
        intents = Array(repeating: .fullBody, count: days)
        
        // Apply heuristics based on number of days
        switch days {
        case 3:
            intents = [.push, .pull, .legs]
        case 4:
            intents = [.upper, .lower, .push, .pull]
        case 5:
            intents = [.push, .pull, .legs, .upper, .lower]
        case 6:
            intents = [.push, .pull, .legs, .push, .pull, .legs]
        case 7:
            intents = [.push, .pull, .legs, .upper, .lower, .arms, .fullBody]
        default:
            // Keep default fullBody for other cases
            break
        }
    }
}
