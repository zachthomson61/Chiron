import Foundation
import SwiftUI

/// Simple store for managing saved training plans
final class PlanStore: ObservableObject {
    @Published var savedPlans: [TrainingPlan] = [] {
        didSet {
            ensureSelectionStillValid()
        }
    }
    /// A persisted handle to the plan shown in the home plan card.
    @Published private(set) var lastSelectedPlanID: UUID? {
        didSet {
            persistSelectedPlanID()
        }
    }
    
    private let persistence = PlanPersistence.shared
    private let defaults = UserDefaults.standard
    private let lastSelectedPlanKey = "com.chiron.lastSelectedPlanId"
    private var hasLoadedPlans = false
    
    init() {
        loadLastSelectedPlan()
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
            }
        }
    }

    /// Keep track of the training plan that should appear on the home card.
    func markPlanSelected(_ plan: TrainingPlan) {
        guard lastSelectedPlanID != plan.id else { return }
        lastSelectedPlanID = plan.id
    }
    
    /// Remove any persisted home card selection.
    func clearSelectedPlan() {
        lastSelectedPlanID = nil
    }

    /// Returns the cached plan that matches the persisted selection ID.
    var lastSelectedPlan: TrainingPlan? {
        guard let id = lastSelectedPlanID else { return nil }
        return savedPlans.first { $0.id == id }
    }

    /// Clears the selection if the previously displayed plan was deleted.
    private func ensureSelectionStillValid() {
        guard let selectedId = lastSelectedPlanID,
              !savedPlans.contains(where: { $0.id == selectedId })
        else { return }
        
        lastSelectedPlanID = nil
    }
    
    /// Reads the last selected ID from UserDefaults before plans are loaded.
    private func loadLastSelectedPlan() {
        guard let idString = defaults.string(forKey: lastSelectedPlanKey),
              let uuid = UUID(uuidString: idString)
        else { return }
        
        lastSelectedPlanID = uuid
    }
    
    /// Writes the current selection ID to UserDefaults so the home card can restore.
    private func persistSelectedPlanID() {
        if let id = lastSelectedPlanID {
            defaults.set(id.uuidString, forKey: lastSelectedPlanKey)
        } else {
            defaults.removeObject(forKey: lastSelectedPlanKey)
        }
    }
}
