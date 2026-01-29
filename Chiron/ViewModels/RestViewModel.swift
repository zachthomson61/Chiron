//
//  RestViewModel.swift
//  Chiron
//
//  View model for managing coaching feedback state during rest periods.
//  Handles loading, success, and error states for OpenAI coaching responses.
//

import Foundation
import SwiftUI

// MARK: - Rest State

/// State of the coaching feedback during rest period
enum RestCoachingState: Equatable {
    case idle
    case loading
    case success(CoachingResponse)
    case error(String)
    
    static func == (lhs: RestCoachingState, rhs: RestCoachingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.loading, .loading):
            return true
        case (.success(let lhsResponse), .success(let rhsResponse)):
            return lhsResponse.headline == rhsResponse.headline
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

// MARK: - Rest View Model

/// Manages coaching feedback state during rest periods after close-grip bench press.
@MainActor
class RestViewModel: ObservableObject {
    /// Current state of the coaching feedback
    @Published var state: RestCoachingState = .idle
    
    /// The summary used for the last fetch (for retry)
    private var lastSummary: CloseGripBenchSummary?
    
    /// Fetches coaching feedback for a close-grip bench press set.
    ///
    /// Updates state to `.loading`, then asynchronously calls OpenAI API.
    /// On success: updates state to `.success(response)` and speaks the coaching.
    /// On error: updates state to `.error(message)` and speaks fallback coaching.
    ///
    /// All state updates are guaranteed to occur on the main thread via `@MainActor` Task.
    ///
    /// - Parameter summary: Compact summary of the completed set
    func fetchCoaching(summary: CloseGripBenchSummary) {
        // Store for retry capability
        lastSummary = summary
        
        // Update state to loading
        state = .loading
        
        // Fetch asynchronously - explicitly use MainActor to ensure state updates are on main thread
        Task { @MainActor in
            do {
                let response = try await OpenAIClient.shared.getBenchCoaching(summary: summary)
                
                // Update state on main actor (guaranteed by @MainActor Task)
                self.state = .success(response)
                
                // Speak the coaching feedback
                speakCoaching(response)
                
            } catch let error as OpenAIClientError {
                self.state = .error(error.localizedDescription ?? "Unknown error")
                
                // Speak fallback feedback
                speakFallbackCoaching(summary: summary)
                
            } catch {
                self.state = .error(error.localizedDescription)
                
                // Speak fallback feedback
                speakFallbackCoaching(summary: summary)
            }
        }
    }
    
    /// Retries the last coaching fetch
    func retry() {
        guard let summary = lastSummary else {
            #if DEBUG
            print("🏋️ RestViewModel: No summary to retry")
            #endif
            return
        }
        
        fetchCoaching(summary: summary)
    }
    
    /// Resets the state to idle (for next rest period)
    func reset() {
        state = .idle
        lastSummary = nil
    }
    
    // MARK: - Speech Integration
    
    /// Speaks the coaching response using SpeechManager.
    private func speakCoaching(_ response: CoachingResponse) {
        let text = response.toSpeakableText()
        SpeechManager.shared.speakCoachingFeedback(text)
    }
    
    /// Speaks fallback coaching when OpenAI API fails.
    ///
    /// Provides score-appropriate encouragement:
    /// - Score >= 75: Praise-focused messages
    /// - Score < 75: Form-focused encouragement
    private func speakFallbackCoaching(summary: CloseGripBenchSummary) {
        let fallback: String
        if summary.formScore >= 75 {
            let messages = [
                "Great set! Excellent form and control.",
                "Nice work! That was a solid set.",
                "Well done! Great execution on that set."
            ]
            fallback = messages.randomElement() ?? "Great set!"
        } else {
            let messages = [
                "Good effort on that set. Keep focusing on your form.",
                "Nice effort there. Focus on keeping those elbows tucked.",
                "Good work. Let's tighten up the form next set."
            ]
            fallback = messages.randomElement() ?? "Good effort!"
        }
        
        SpeechManager.shared.speakCoachingFeedback(fallback)
    }
}
