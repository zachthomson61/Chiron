import Foundation
import SwiftUI

/// Simple store for managing saved training plans
final class PlanStore: ObservableObject {
    @Published var savedPlans: [TrainingPlan] = []
    
    private let persistence = PlanPersistence.shared
    private var hasLoadedPlans = false
    
    init() {
        // Don't load plans immediately - load them lazily when needed
    }
    
    // MARK: - Public Methods
    
    /// Loads plans if not already loaded
    func loadPlansIfNeeded() {
        guard !hasLoadedPlans else { return }
        hasLoadedPlans = true
        loadPlans()
    }
    
    func loadPlans() {
        Task {
            do {
                let plans = try await persistence.loadPlans()
                await MainActor.run {
                    self.savedPlans = plans
                }
            } catch {
                print("Failed to load plans: \(error)")
                await MainActor.run {
                    self.savedPlans = []
                }
            }
        }
    }
    
    func addPlan(_ plan: TrainingPlan) {
        Task {
            do {
                try await persistence.savePlan(plan)
                await MainActor.run {
                    // Check if plan already exists and update it
                    if let index = self.savedPlans.firstIndex(where: { $0.id == plan.id }) {
                        self.savedPlans[index] = plan
                    } else {
                        self.savedPlans.append(plan)
                    }
                }
            } catch {
                print("Failed to save plan: \(error)")
            }
        }
    }
    
    func deletePlan(at indexSet: IndexSet) {
        guard let index = indexSet.first else { return }
        let plan = savedPlans[index]
        
        Task {
            do {
                try await persistence.deletePlan(withId: plan.id)
                await MainActor.run {
                    self.savedPlans.remove(atOffsets: indexSet)
                }
            } catch {
                print("Failed to delete plan: \(error)")
            }
        }
    }
    
    func deletePlan(withId id: UUID) {
        Task {
            do {
                try await persistence.deletePlan(withId: id)
                await MainActor.run {
                    self.savedPlans.removeAll { $0.id == id }
                }
            } catch {
                print("Failed to delete plan: \(error)")
            }
        }
    }
}
