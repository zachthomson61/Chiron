import Foundation
import SwiftUI
import Combine

// MARK: - One Question Flow View Model

@MainActor
final class OQFViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentStepId: StepId
    @Published var answers: [String: Any] = [:]
    @Published var history: [StepId] = []
    @Published var startedAt: Date = Date()
    @Published var lastUpdatedAt: Date = Date()
    @Published var validationError: String?
    @Published var isGenerating: Bool = false
    
    // MARK: - Computed Properties
    
    var currentStep: FlowStep? {
        return FlowConfig.shared.steps[currentStepId]
    }
    
    var progress: Double {
        guard !history.isEmpty else { return 0.0 }
        let total = Double(FlowConfig.shared.estimatedLength)
        let completed = Double(history.count)
        return min(completed / total, 0.95)
    }
    
    var canGoBack: Bool {
        !history.isEmpty
    }
    
    var isAtResult: Bool {
        currentStepId == .result
    }
    
    // MARK: - Private Properties
    
    private let config = FlowConfig.shared
    private let persistence = UserDefaults.standard
    private let persistenceKey = "planBuilderOQF_v2"
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        // Initialize all stored properties first
        self.currentStepId = config.start
        self.answers = [:]
        self.history = []
        self.startedAt = Date()
        self.lastUpdatedAt = Date()
        
        // Now try to load existing state (can use self now)
        if let saved = loadState() {
            self.currentStepId = saved.currentStepId
            self.answers = saved.answers
            self.history = saved.history
            self.startedAt = saved.startedAt
            self.lastUpdatedAt = saved.lastUpdatedAt
        }
        
        // Auto-save on changes
        $answers
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveState()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    func submitAnswer(_ answer: Any) -> Bool {
        guard let step = currentStep else { return false }
        
        // Skip validation for empty optional answers
        if !step.required, let answerString = answer as? String, answerString.isEmpty {
            // Skip this question
            let nextId = step.next(answer, answers)
            history.append(currentStepId)
            currentStepId = nextId
            lastUpdatedAt = Date()
            saveState()
            return true
        }
        
        // Validate answer
        if let error = step.validate?(answer) {
            validationError = error
            return false
        }
        
        validationError = nil
        
        // Store answer (skip empty strings for optional)
        if !(answer is String && (answer as? String)?.isEmpty == true) {
            answers[step.id.rawValue] = answer
        }
        
        // Determine next step
        let nextId = step.next(answer, answers)
        
        // Update history
        history.append(currentStepId)
        
        // Move to next step
        currentStepId = nextId
        lastUpdatedAt = Date()
        
        // Save state
        saveState()
        
        return true
    }
    
    func goBack() {
        guard !history.isEmpty else { return }
        
        let previousStep = history.removeLast()
        currentStepId = previousStep
        lastUpdatedAt = Date()
        
        // Remove answer for the step we're going back from
        answers.removeValue(forKey: currentStepId.rawValue)
        
        saveState()
    }
    
    func reset() {
        currentStepId = config.start
        answers = [:]
        history = []
        startedAt = Date()
        lastUpdatedAt = Date()
        validationError = nil
        
        persistence.removeObject(forKey: persistenceKey)
    }
    
    func jumpToStep(_ stepId: StepId) {
        // Find the step in history
        if let index = history.firstIndex(of: stepId) {
            // Truncate history to this step
            history = Array(history[0..<index])
            currentStepId = stepId
            lastUpdatedAt = Date()
            saveState()
        }
    }
    
    // MARK: - Plan Generation
    
    func generatePlan() async -> PlanBuilderInput? {
        guard currentStepId == .result else { return nil }
        
        isGenerating = true
        defer { isGenerating = false }
        
        // Convert answers to PlanBuilderInput
        var input = PlanBuilderInput()
        
        // Plan Name
        if let name = answers[StepId.planName.rawValue] as? String {
            input.name = name
        }
        
        // Goals - map from string to FocusArea
        if let goal = answers[StepId.primaryGoal.rawValue] as? String {
            switch goal {
            case "muscle_gain", "hypertrophy":
                input.goals = [.hypertrophy]
            case "strength":
                input.goals = [.strength]
            case "fat_loss":
                input.goals = [.hypertrophy] // Could add fat loss goal
            case "endurance":
                input.goals = [.endurance]
            default:
                input.goals = [.hypertrophy]
            }
        }
        
        // Days per week
        if let days = answers[StepId.daysPerWeek.rawValue] as? Int {
            input.daysPerWeek = days
        }
        
        // Session duration
        if let duration = answers[StepId.sessionDuration.rawValue] as? Int {
            input.sessionMinutes = duration
        } else if let duration = answers[StepId.sessionDurationShort.rawValue] as? Int {
            input.sessionMinutes = duration
        }
        
        // Program duration
        if let duration = answers[StepId.programDuration.rawValue] as? Int {
            input.programDuration = duration
        }
        
        // Target muscles
        if let muscleStrings = answers[StepId.targetMuscles.rawValue] as? [String] {
            input.targetMuscles = muscleStrings.compactMap { MuscleGroup(rawValue: $0) }
        }
        
        // Workout split
        if let splitString = answers[StepId.workoutSplit.rawValue] as? String,
           let split = WorkoutSplit(rawValue: splitString) {
            input.split = split
        }
        
        // Custom split
        // Handled inline on the workout split step; no separate text entry is used.
        
        // Exercise variety
        if let variety = answers[StepId.exerciseVariety.rawValue] as? String {
            switch variety {
            case "consistent":
                input.varietyContinuum = 0.2
            case "balanced":
                input.varietyContinuum = 0.5
            case "varied":
                input.varietyContinuum = 0.8
            default:
                input.varietyContinuum = 0.5
            }
        }
        
        // Supersets
        if let supersets = answers[StepId.supersets.rawValue] as? Bool {
            input.supersets = supersets
        }
        
        // Injury notes
        if let injuryDetails = answers[StepId.injuryDetails.rawValue] as? String {
            input.injuryNotes = [InjuryNote(raw: injuryDetails)]
        }
        
        return input
    }
    
    // MARK: - Persistence
    
    private func saveState() {
        let stateDict: [String: Any] = [
            "currentStepId": currentStepId.rawValue,
            "history": history.map { $0.rawValue },
            "startedAt": startedAt.timeIntervalSince1970,
            "lastUpdatedAt": lastUpdatedAt.timeIntervalSince1970,
            "answers": answers
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: stateDict) {
            persistence.set(data, forKey: persistenceKey)
        }
    }
    
    private func loadState() -> (currentStepId: StepId, answers: [String: Any], history: [StepId], startedAt: Date, lastUpdatedAt: Date)? {
        guard let data = persistence.data(forKey: persistenceKey),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stepIdString = dict["currentStepId"] as? String,
              let stepId = StepId(rawValue: stepIdString),
              let historyStrings = dict["history"] as? [String],
              let startedTimestamp = dict["startedAt"] as? TimeInterval,
              let updatedTimestamp = dict["lastUpdatedAt"] as? TimeInterval,
              let answersDict = dict["answers"] as? [String: Any] else {
            return nil
        }
        
        return (
            currentStepId: stepId,
            answers: answersDict,
            history: historyStrings.compactMap { StepId(rawValue: $0) },
            startedAt: Date(timeIntervalSince1970: startedTimestamp),
            lastUpdatedAt: Date(timeIntervalSince1970: updatedTimestamp)
        )
    }
}
