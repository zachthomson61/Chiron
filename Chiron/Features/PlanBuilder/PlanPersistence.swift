import Foundation
import SwiftUI

// MARK: - Persistence Protocol

protocol PlanPersistenceProtocol {
    func savePlan(_ plan: TrainingPlan) async throws
    func loadPlans() async throws -> [TrainingPlan]
    func deletePlan(withId id: UUID) async throws
    func exportPlan(_ plan: TrainingPlan) async throws -> Data
    func importPlan(from data: Data) async throws -> TrainingPlan
}

// MARK: - JSON Persistence Implementation

final class PlanPersistence: PlanPersistenceProtocol, ObservableObject {
    static let shared = PlanPersistence()
    
    @Published var savedPlans: [TrainingPlan] = []
    
    private let userDefaults = UserDefaults.standard
    private let plansKey = "com.chiron.savedTrainingPlans"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        
        // Load saved plans on init
        Task {
            try? await loadPlans()
        }
    }
    
    // MARK: - Public Methods
    
    func savePlan(_ plan: TrainingPlan) async throws {
        let loadedPlans = try await loadPlans()
        var updatedPlans = loadedPlans
        
        // Check if plan already exists and update it
        if let index = updatedPlans.firstIndex(where: { $0.id == plan.id }) {
            updatedPlans[index] = plan
        } else {
            updatedPlans.append(plan)
        }
        
        let data = try encoder.encode(updatedPlans)
        userDefaults.set(data, forKey: plansKey)
        
        // Capture immutable copy for async closure
        let finalPlans = updatedPlans
        await MainActor.run {
            self.savedPlans = finalPlans
        }
    }
    
    @discardableResult
    func loadPlans() async throws -> [TrainingPlan] {
        guard let data = userDefaults.data(forKey: plansKey) else {
            await MainActor.run {
                self.savedPlans = []
            }
            return []
        }
        
        let plans = try decoder.decode([TrainingPlan].self, from: data)
        
        await MainActor.run {
            self.savedPlans = plans
        }
        
        return plans
    }
    
    func deletePlan(withId id: UUID) async throws {
        let loadedPlans = try await loadPlans()
        var updatedPlans = loadedPlans
        updatedPlans.removeAll { $0.id == id }
        
        let data = try encoder.encode(updatedPlans)
        userDefaults.set(data, forKey: plansKey)
        
        // Capture immutable copy for async closure
        let finalPlans = updatedPlans
        await MainActor.run {
            self.savedPlans = finalPlans
        }
    }
    
    func exportPlan(_ plan: TrainingPlan) async throws -> Data {
        return try encoder.encode(plan)
    }
    
    func importPlan(from data: Data) async throws -> TrainingPlan {
        let plan = try decoder.decode(TrainingPlan.self, from: data)
        try await savePlan(plan)
        return plan
    }
    
    // MARK: - Convenience Methods
    
    func getPlan(withId id: UUID) -> TrainingPlan? {
        return savedPlans.first { $0.id == id }
    }
    
    func clearAllPlans() async throws {
        userDefaults.removeObject(forKey: plansKey)
        await MainActor.run {
            self.savedPlans = []
        }
    }
}

// MARK: - Export/Import Helpers

extension PlanPersistence {
    
    func exportToFile(_ plan: TrainingPlan) async throws -> URL {
        let data = try await exportPlan(plan)
        let fileName = "\(plan.name.replacingOccurrences(of: " ", with: "_"))_\(Date().timeIntervalSince1970).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url)
        return url
    }
    
    func importFromFile(at url: URL) async throws -> TrainingPlan {
        let data = try Data(contentsOf: url)
        return try await importPlan(from: data)
    }
}

// MARK: - AppStorage Extension for Simple Values

extension View {
    func withPlanPersistence() -> some View {
        self.environmentObject(PlanPersistence.shared)
    }
}

// MARK: - Mock Data for Testing

extension TrainingPlan {
    static var mockPlan: TrainingPlan {
        let exercises = [
            WorkoutExercise(name: "Barbell Squat", category: .compound, sets: 4, reps: "8-10", restTime: 120),
            WorkoutExercise(name: "Romanian Deadlift", category: .compound, sets: 3, reps: "10-12", restTime: 90),
            WorkoutExercise(name: "Leg Press", category: .compound, sets: 3, reps: "12-15", restTime: 60),
            WorkoutExercise(name: "Leg Curls", category: .isolation, sets: 3, reps: "12-15", restTime: 60)
        ]
        
        let day = TrainingDay(
            dayNumber: 1,
            name: "Leg Day",
            exercises: exercises,
            duration: 45,
            difficulty: .intermediate
        )
        
        let week = TrainingWeek(weekNumber: 1, days: [day])
        
        return TrainingPlan(
            name: "Sample Plan",
            duration: 4,
            daysPerWeek: 3,
            targetMuscles: [.chest, .back, .shoulders],
            split: .pushPullLegs,
            injuries: [],
            varietyLevel: .medium,
            supersets: false,
            weeks: [week]
        )
    }
}
