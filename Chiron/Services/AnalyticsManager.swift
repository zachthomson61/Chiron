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
    
    /// Core logging function
    private func logEvent(_ event: String, properties: [String: Any]) {
        #if DEBUG
        print("📊 Analytics Event: \(event)")
        print("   Properties: \(properties)")
        #endif
        
        // TODO: Send to actual analytics service (Firebase Analytics, Amplitude, etc.)
        // For now, we'll just store locally for debugging
        
        // Store in UserDefaults for debugging (limited to last 100 events)
        var events = UserDefaults.standard.array(forKey: "analytics_events") as? [[String: Any]] ?? []
        
        var eventData = properties
        eventData["event_name"] = event
        eventData["session_id"] = getSessionId()
        
        events.append(eventData)
        
        // Keep only last 100 events
        if events.count > 100 {
            events = Array(events.suffix(100))
        }
        
        UserDefaults.standard.set(events, forKey: "analytics_events")
    }
    
    /// Get or create session ID
    private func getSessionId() -> String {
        let sessionKey = "current_session_id"
        let sessionTimeoutMinutes = 30.0
        
        // Check if we have a valid session
        if let sessionData = UserDefaults.standard.dictionary(forKey: sessionKey),
           let sessionId = sessionData["id"] as? String,
           let lastActivity = sessionData["last_activity"] as? Date {
            
            // Check if session is still valid (within timeout)
            if Date().timeIntervalSince(lastActivity) < sessionTimeoutMinutes * 60 {
                // Update last activity
                UserDefaults.standard.set([
                    "id": sessionId,
                    "last_activity": Date()
                ], forKey: sessionKey)
                return sessionId
            }
        }
        
        // Create new session
        let newSessionId = UUID().uuidString
        UserDefaults.standard.set([
            "id": newSessionId,
            "last_activity": Date()
        ], forKey: sessionKey)
        
        return newSessionId
    }
    
    /// Get analytics events for debugging
    func getRecentEvents() -> [[String: Any]] {
        return UserDefaults.standard.array(forKey: "analytics_events") as? [[String: Any]] ?? []
    }
}



