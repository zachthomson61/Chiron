import Foundation
import Combine
import SwiftUI

// MARK: - Plan Builder View Model

@MainActor
final class PlanBuilderViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var input = PlanBuilderInput()
    @Published var isGenerating = false
    @Published var generatedPlan: TrainingPlan?
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var navigateToPreview = false
    
    // MARK: - Injury Notes Management
    
    @Published var currentInjuryEntry: String = ""
    
    // MARK: - Private Properties
    
    private let plannerEngine = PlannerEngine()
    private let persistence = PlanPersistence.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Computed Properties
    
    var canGeneratePlan: Bool {
        let valid = input.isValid
        print("DEBUG: canGeneratePlan = \(valid), input.isValid = \(input.isValid)")
        return valid
    }
    
    var selectedGoalsText: String {
        if input.goals.isEmpty {
            return "None selected"
        } else if input.goals.count == 1 {
            return input.goals.first!.rawValue
        } else {
            return "\(input.goals.count) selected"
        }
    }
    
    var selectedTargetMusclesText: String {
        if input.targetMuscles.isEmpty {
            return "None selected"
        } else if input.targetMuscles.count == 1 {
            return input.targetMuscles.first!.displayName
        } else {
            return "\(input.targetMuscles.count) selected"
        }
    }
    
    var selectedInjuriesText: String {
        let filtered = input.injuries.filter { $0 != .none }
        if filtered.isEmpty {
            return "None"
        } else if filtered.count == 1 {
            return filtered.first!.rawValue
        } else {
            return "\(filtered.count) selected"
        }
    }
    
    var parsedInjuryProfile: InjuryProfile {
        let allText = input.injuryNotes.map { $0.raw }.joined(separator: " ")
        return InjuryParser.parse(allText, notes: input.injuryNotes)
    }
    
    var detectedConstraintsText: String {
        let constraints = parsedInjuryProfile.constraints
        if constraints.isEmpty {
            return "No constraints detected"
        } else {
            let names = constraints.map { $0.displayName }.sorted()
            return "Detected: \(names.joined(separator: ", "))"
        }
    }
    
    // MARK: - Initialization
    
    init() {
        setupDefaults()
        setupValidation()
    }
    
    // MARK: - Public Methods
    
    func toggleGoal(_ goal: FocusArea) {
        if input.goals.contains(goal) {
            input.goals.removeAll { $0 == goal }
        } else {
            input.goals.append(goal)
        }
    }
    
    func toggleTargetMuscle(_ muscle: MuscleGroup) {
        if input.targetMuscles.contains(muscle) {
            input.targetMuscles.removeAll { $0 == muscle }
        } else {
            input.targetMuscles.append(muscle)
        }
    }
    
    func toggleInjury(_ injury: Injury) {
        if injury == .none {
            input.injuries = []
        } else {
            if input.injuries.contains(injury) {
                input.injuries.removeAll { $0 == injury }
            } else {
                input.injuries.append(injury)
            }
        }
    }
    
    // MARK: - Injury Notes Methods
    
    func addCurrentInjuryEntry() {
        let trimmed = currentInjuryEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        input.injuryNotes.append(InjuryNote(raw: trimmed))
        currentInjuryEntry = ""
        
        // Update the injury profile
        input.injuryProfile = parsedInjuryProfile
    }
    
    func removeInjuryNote(_ note: InjuryNote) {
        input.injuryNotes.removeAll { $0.id == note.id }
        
        // Update the injury profile
        input.injuryProfile = parsedInjuryProfile
    }
    
    func generatePlan() async {
        print("DEBUG: generatePlan called")
        print("DEBUG: canGeneratePlan = \(canGeneratePlan)")
        print("DEBUG: input.isValid = \(input.isValid)")
        print("DEBUG: input.name = '\(input.name)'")
        print("DEBUG: input.goals = \(input.goals)")
        print("DEBUG: input.sessionMinutes = \(input.sessionMinutes)")
        print("DEBUG: input.daysPerWeek = \(input.daysPerWeek)")
        print("DEBUG: input.programDuration = \(input.programDuration)")
        
        guard canGeneratePlan else {
            print("DEBUG: Validation failed, showing error")
            showValidationError()
            return
        }
        
        isGenerating = true
        errorMessage = nil
        
        do {
            // Simulate network delay for better UX
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            print("DEBUG: About to generate plan from input")
            // Generate plan
            let plan = plannerEngine.generatePlan(from: input)
            print("DEBUG: Successfully generated plan, about to save")
            
            // Clear any existing saved plans to avoid decoding issues
            try await persistence.clearAllPlans()
            print("DEBUG: Cleared existing plans")
            
            // Save plan
            try await persistence.savePlan(plan)
            print("DEBUG: Successfully saved plan")
            
            // Update state
            generatedPlan = plan
            navigateToPreview = true
            
        } catch {
            print("DEBUG: Error in generatePlan: \(error)")
            print("DEBUG: Error details: \(error.localizedDescription)")
            errorMessage = "Failed to generate plan: \(error.localizedDescription)"
            showError = true
        }
        
        isGenerating = false
    }
    
    func reset() {
        input = PlanBuilderInput()
        setupDefaults()
        generatedPlan = nil
        errorMessage = nil
        showError = false
        navigateToPreview = false
    }
    
    // MARK: - Private Methods
    
    private func setupDefaults() {
        input.name = "My Training Plan"
        input.goals = [.hypertrophy] // Default goal
        input.targetMuscles = [.chest, .back, .shoulders, .quadriceps, .hamstrings, .glutes] // Default target muscles
        input.sessionMinutes = 45 // minutes
        input.daysPerWeek = 3
        input.programDuration = 4 // weeks
        input.split = .fullBody
        input.varietyLevel = .medium
        input.supersets = false
    }
    
    private func setupValidation() {
        // Observe input changes for validation
        $input
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    private func showValidationError() {
        print("DEBUG: showValidationError called")
        print("DEBUG: name.isEmpty = \(input.name.isEmpty)")
        print("DEBUG: goals.isEmpty = \(input.goals.isEmpty)")
        print("DEBUG: daysPerWeek = \(input.daysPerWeek)")
        print("DEBUG: programDuration = \(input.programDuration)")
        print("DEBUG: sessionMinutes = \(input.sessionMinutes)")
        
        if input.name.isEmpty {
            errorMessage = "Please enter a plan name"
        } else if input.goals.isEmpty {
            errorMessage = "Please select at least one goal"
        } else if input.daysPerWeek < 1 || input.daysPerWeek > 7 {
            errorMessage = "Days per week must be between 1 and 7"
        } else if input.programDuration < 1 {
            errorMessage = "Program duration must be at least 1 week"
        } else if input.sessionMinutes < 1 {
            errorMessage = "Session duration must be at least 1 minute"
        } else {
            errorMessage = "Please fill in all required fields"
        }
        print("DEBUG: Setting error message: \(errorMessage ?? "nil")")
        showError = true
    }
}

// MARK: - View Model Extensions

extension PlanBuilderViewModel {
    
    var daysPerWeekOptions: [Int] {
        Array(1...7)
    }
    
    var programDurationOptions: [Int] {
        [2, 4, 6, 8, 12, 16]
    }
    
    var sessionDurationOptions: [Int] {
        [30, 45, 60, 75, 90]
    }
    
    func formattedDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(mins)m"
            }
        }
    }
}
