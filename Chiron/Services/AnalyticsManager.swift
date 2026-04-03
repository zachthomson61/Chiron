import Foundation

/// Simple analytics manager for tracking user events
class AnalyticsManager {
    static let shared = AnalyticsManager()
    
    private init() {}
    
    /// Track when user changes their primary goal
    func trackGoalChanged(from: String, to: String, source: String) {
        let event = "goal_changed"
        let properties: [String: Any] = [
            "from": from,
            "to": to,
            "source": source,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        logEvent(event, properties: properties)
    }
    
    /// Track when goal selector is opened
    func trackGoalSelectorOpened(currentGoal: String?) {
        let event = "goal_selector_opened"
        let properties: [String: Any] = [
            "current_goal": currentGoal ?? "none",
            "timestamp": Date().timeIntervalSince1970
        ]
        
        logEvent(event, properties: properties)
    }
    
    /// Track first run experience
    func trackFirstRunGoalPrompt() {
        let event = "first_run_goal_prompt"
        let properties: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970
        ]
        
        logEvent(event, properties: properties)
    }
    
    private func logEvent(_ event: String, properties: [String: Any]) {}
}




