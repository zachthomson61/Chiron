//
//  OpenAICoachingManager.swift
//  Chiron
//
//  Manages OpenAI API integration for generating exercise-specific coaching feedback.
//
//  Architecture:
//  - Generates natural, conversational feedback based on form analysis
//  - Adapts coaching cues based on exercise type (bodyweight vs barbell back squat)
//  - Provides exercise-specific examples and fallback feedback
//  - Handles API errors gracefully with exercise-appropriate fallback messages
//
//  Exercise-Specific Coaching:
//  - Bodyweight squats: Focus on balance, chest position, knee tracking
//  - Barbell back squats: Focus on bar position, core bracing, upper back tightness
//

import Foundation
import AVFoundation

// MARK: - OpenAI Coaching Manager

/// Generates natural, conversational coaching feedback using OpenAI API.
/// Provides exercise-specific feedback based on SquatType (bodyweight or barbell).
class OpenAICoachingManager: ObservableObject {
    static let shared = OpenAICoachingManager()
    
    @Published var isRequestingFeedback = false
    @Published var currentFeedback: String = ""
    
    // OpenAI API Configuration
    private let apiKey = "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"
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    private init() {}
    
    // MARK: - Natural Single Feedback
    
    /// Generates a single, flowing coaching message using OpenAI API.
    /// Adapts coaching cues and examples based on exercise type.
    ///
    /// - Parameters:
    ///   - formAnalysis: Current form analysis with depth, back angle, knee alignment, etc.
    ///   - exerciseType: .bodyweight or .barbell to determine exercise-specific coaching cues
    ///   - completion: Callback with the generated feedback string
    func getNaturalFeedback(formAnalysis: FormAnalysis, exerciseType: SquatType, completion: @escaping (String) -> Void) {
        let summary = formAnalysis.summary
        
        // Create structured analysis for better prompt context
        let analysisPayload: [String: Any] = [
            "depth": formAnalysis.depth,
            "back_angle": formAnalysis.backAngle,
            "knee_alignment": formAnalysis.kneeAlignment,
            "rep_count": formAnalysis.repCount,
            "issues": formAnalysis.issues
        ]
        
        let analysisJSON: String = {
            if let data = try? JSONSerialization.data(withJSONObject: analysisPayload, options: [.sortedKeys]),
               let str = String(data: data, encoding: .utf8) { return str }
            return "{}"
        }()

        // Build exercise-specific context
        let squatLabel: String
        let coachingFocus: String
        
        switch exerciseType {
        case .barbell:
            squatLabel = "barbell back squat"
            coachingFocus = """
            This is a barbell back squat. Key priorities:
            - Bar stays stacked over mid foot
            - Strong braced core and neutral spine
            - Upper back tight and bar stable on the back
            - Knees track over mid foot, not collapsing in
            """
        case .bodyweight:
            squatLabel = "bodyweight squat"
            coachingFocus = """
            This is a bodyweight squat. Key priorities:
            - Balanced weight through mid foot and heels
            - Upright chest and stable core
            - Knees tracking over toes without collapsing in
            """
        case .benchPress:
            squatLabel = "close-grip bench press"
            coachingFocus = """
            This is a close-grip bench press. Key priorities:
            - Shoulder blades retracted and tight against the bench
            - Feet flat on the floor for stability
            - Controlled bar path down to mid-chest
            - Elbows stay close to the body
            - Full lockout at the top
            """
        }
        
        let prompt = """
        You're an encouraging gym trainer giving real-time feedback. Based on this \(squatLabel) analysis, give ONE flowing response that sounds natural:

        EXERCISE_CONTEXT:
        \(coachingFocus)

        ANALYSIS_METRICS:
        \(analysisJSON)

        MOVEMENT_SUMMARY:
        \(summary)

        Respond like you're standing right there coaching a beginner. Use simple, everyday language - no technical terms.

        Start with quick acknowledgment: "There we go" / "Alright" / "Much better"
        Add specific observation: "good depth" / "nice control" / "solid tempo"
        Transition naturally: "now" / "just" / "but let's"
        Give one specific cue using simple language appropriate for \(squatLabel):
        \(exerciseType == .barbell ? """
        - "brace your core before you descend"
        - "keep that bar over mid foot"
        - "squeeze your upper back and keep the bar steady"
        """ : """
        - "sit back a bit more"
        - "keep your chest proud"
        - "knees track over your toes"
        """)

        Examples for \(squatLabel):
        \(exerciseType == .barbell ? """
        "There we go, good depth - now keep that bar over mid foot"
        "Alright, strong effort, squeeze your upper back and keep your chest proud"
        "Much better, I see that depth - now brace your core before you descend"
        """ : """
        "There we go, good depth - now drive through those heels"
        "Alright, nice control, just keep that chest proud"
        "Much better, I see that depth - now push those knees out"
        """)

        Keep it 12-18 words, conversational, specific. Avoid technical terms like valgus, varus, eccentric, concentric.
        """

        print("🤖 Natural: preparing OpenAI request for unified feedback")

        guard let url = URL(string: baseURL) else {
            completion(generateFallbackFeedback(from: formAnalysis, exerciseType: exerciseType))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                ["role": "system", "content": "You are a natural, encouraging athletic trainer coaching beginners. Use simple everyday language, no technical jargon. Speak conversationally as if you're right there helping a friend. Be specific and supportive."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 40,
            "temperature": 0.7
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(generateFallbackFeedback(from: formAnalysis, exerciseType: exerciseType))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ OpenAI natural feedback error: \(error)")
                DispatchQueue.main.async {
                    completion(self.generateFallbackFeedback(from: formAnalysis, exerciseType: exerciseType))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(self.generateFallbackFeedback(from: formAnalysis, exerciseType: exerciseType))
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    
                    let cleanedFeedback = content
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: "  ", with: " ")
                    
                    print("🤖 Natural: received feedback - \(cleanedFeedback)")
                    
                    // Check for generic or robotic responses
                    if self.isGenericResponse(cleanedFeedback) {
                        print("🤖 Natural: detected generic response, using fallback")
                        DispatchQueue.main.async {
                            completion(self.generateFallbackFeedback(from: formAnalysis, exerciseType: exerciseType))
                        }
                    } else {
                        DispatchQueue.main.async {
                            completion(cleanedFeedback)
                        }
                    }
                } else {
                    print("❌ Natural: failed to parse OpenAI response")
                    DispatchQueue.main.async {
                        completion(self.generateFallbackFeedback(from: formAnalysis, exerciseType: exerciseType))
                    }
                }
            } catch {
                print("❌ Natural: parse error - \(error)")
                DispatchQueue.main.async {
                    completion(self.generateFallbackFeedback(from: formAnalysis, exerciseType: exerciseType))
                }
            }
        }.resume()
    }
    
    // MARK: - Fallback Feedback
    
    /// Generates fallback feedback when OpenAI API fails or returns generic responses.
    /// Provides exercise-specific cues based on form issues detected.
    private func generateFallbackFeedback(from analysis: FormAnalysis, exerciseType: SquatType) -> String {
        if exerciseType == .barbell {
            if analysis.issues.contains("Insufficient Depth") || analysis.depth < 0.45 {
                return "There we go, now sit back and keep the bar over mid foot"
            }
            if analysis.issues.contains("Forward Lean") || abs(analysis.backAngle) > 30 {
                return "Alright, strong effort, squeeze your upper back and keep your chest a bit prouder"
            }
            if analysis.issues.contains("Knees Caving In") {
                return "Much better, solid effort - now push those knees out and keep the bar steady"
            }
            if analysis.depth >= 0.6 {
                return "Nice depth, keep that bar steady and drive up through mid foot"
            }
            return "Nice control there - brace your core and keep that bar over mid foot"
        } else {
            // Bodyweight fallback cues
            if analysis.issues.contains("Insufficient Depth") || analysis.depth < 0.45 {
                return "There we go, nice control - now sit back a little deeper"
            }
            if analysis.issues.contains("Forward Lean") || abs(analysis.backAngle) > 30 {
                return "Alright, good tempo - just keep that chest proud"
            }
            if analysis.issues.contains("Knees Caving In") {
                return "Much better, solid effort - now push those knees out"
            }
            if analysis.issues.contains("Knees Bowing Out") {
                return "Nice work staying steady - keep those knees tracking straight"
            }
            if analysis.depth >= 0.6 {
                return "Great depth there - now drive through those heels"
            }
            return "Nice control there - just brace that core throughout"
        }
    }
    
    // MARK: - Generic Response Detection
    private func isGenericResponse(_ response: String) -> Bool {
        let genericPatterns = [
            "good job", "nice work", "well done", "keep it up",
            "great work", "excellent", "perfect", "work on form",
            "practice more", "keep practicing", "overall good"
        ]
        
        let lowercased = response.lowercased()
        let genericCount = genericPatterns.filter { lowercased.contains($0) }.count
        
        // If response is too generic (contains multiple generic phrases or is very short)
        return genericCount >= 2 || response.count < 15
    }
    
    // MARK: - Updated Speech Synthesis (Single Call)
    func speakFeedback(_ feedback: String) {
        // Use high priority to ensure immediate, uninterrupted delivery
        SpeechManager.shared.speak(feedback, priority: .high)
        print("🎤 Speaking unified coaching feedback: \(feedback)")
    }
    
    // MARK: - Combined Analysis and Natural Feedback
    
    /// Main entry point for getting coaching feedback after a set.
    /// Validates form analysis data, then generates and speaks exercise-specific feedback.
    ///
    /// - Parameters:
    ///   - formAnalysis: Form analysis from OnDevicePoseManager
    ///   - exerciseType: .bodyweight or .barbell for exercise-specific coaching
    ///   - completion: Callback with the feedback string (speech is handled internally)
    func analyzeAndGetNaturalFeedback(formAnalysis: FormAnalysis, exerciseType: SquatType, completion: @escaping (String) -> Void) {
        print("🤖 Starting natural feedback analysis for \(exerciseType == .barbell ? "barbell" : "bodyweight") squat")
        
        // Check for valid data first
        if formAnalysis.repCount <= 0 || formAnalysis.summary.isEmpty {
            let noDataFeedback = "I didn't catch that set - make sure you're visible in the frame."
            speakFeedback(noDataFeedback)
            completion(noDataFeedback)
            return
        }
        
        getNaturalFeedback(formAnalysis: formAnalysis, exerciseType: exerciseType) { feedback in
            print("🤖 Received natural feedback: \(feedback)")
            // Speak the unified feedback
            self.speakFeedback(feedback)
            completion(feedback)
        }
    }
    
    // MARK: - Backward Compatibility
    
    /// Legacy API wrapper. Defaults to bodyweight squat for backward compatibility.
    /// New code should use `analyzeAndGetNaturalFeedback(formAnalysis:exerciseType:completion:)` directly.
    @available(*, deprecated, message: "Use analyzeAndGetNaturalFeedback(formAnalysis:exerciseType:completion:) with explicit exerciseType")
    func analyzeAndGetFeedback(formAnalysis: FormAnalysis, isDetailed: Bool = false, completion: @escaping (String) -> Void) {
        analyzeAndGetNaturalFeedback(formAnalysis: formAnalysis, exerciseType: .bodyweight, completion: completion)
    }
    
    // MARK: - Legacy Support (Updated)
    func getCoachingFeedback(summary: String, isDetailed: Bool = false, completion: @escaping (String) -> Void) {
        // For backward compatibility, but encourage using the new natural feedback system
        print("🤖 Legacy coaching feedback called - consider using getNaturalFeedback instead")
        
        DispatchQueue.main.async {
            self.isRequestingFeedback = true
        }
        
        // Default to bodyweight for legacy support, but ideally this should be parameterized
        let prompt = generateNaturalCoachingPrompt(summary: summary, isDetailed: isDetailed, exerciseType: .bodyweight)
        
        let requestBody: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                [
                    "role": "system",
                    "content": "You are a natural, conversational athletic trainer. Speak like you're right there coaching someone through their workout. Be encouraging but constructive, and always sound human and supportive."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "max_tokens": 35,
            "temperature": 0.7
        ]
        
        guard let url = URL(string: baseURL) else {
            DispatchQueue.main.async {
                self.isRequestingFeedback = false
                completion("Nice work on that set.")
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            DispatchQueue.main.async {
                self.isRequestingFeedback = false
                completion("Good effort on that set.")
            }
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isRequestingFeedback = false
                
                if let error = error {
                    print("❌ OpenAI API error: \(error)")
                    completion("Nice work, keep it up.")
                    return
                }
                
                guard let data = data else {
                    completion("Good job on that set.")
                    return
                }
                
                do {
                    if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = jsonResponse["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        
                        let feedback = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        if feedback.uppercased().contains("NO_VALID_DATA") {
                            self?.currentFeedback = "No exercise detected. Please ensure visible in the camera frame."
                            completion("No exercise detected. Please ensure you're visible and doing squats.")
                        } else {
                            self?.currentFeedback = feedback
                            completion(feedback)
                        }
                        
                    } else {
                        completion("Keep up the good work.")
                    }
                } catch {
                    print("❌ Error parsing OpenAI response: \(error)")
                    completion("Nice effort there.")
                }
            }
        }.resume()
    }
    
    private func generateNaturalCoachingPrompt(summary: String, isDetailed: Bool = false, exerciseType: SquatType = .bodyweight) -> String {
        let exerciseName = exerciseType == .barbell ? "barbell back squats" : "bodyweight squats"
        return """
        You are an athletic trainer giving natural, conversational feedback for \(exerciseName).

        The user just completed a set:
        \(summary)

        Reply with ONE message using this structure:
        - Short praise first (allow an exclamation for enthusiasm)
        - Then a specific coaching tip starting with: "Focus on...", "Try...", "Make sure...", or "On the next set, ..."
        - Two clauses or two short sentences; 14–28 words; human and supportive

        Example: "Nice control on the way down! Focus on keeping your back straight on the next set."
        If there is no valid exercise data, return exactly: NO_VALID_DATA
        """
    }
    
    // MARK: - Deprecated Two-Point Method
    @available(*, deprecated, message: "Use getNaturalFeedback instead for better user experience")
    func getTwoPointFeedback(formAnalysis: FormAnalysis, completion: @escaping (String, String) -> Void) {
        // Redirect to natural feedback and split for backward compatibility
        // Default to bodyweight for backward compatibility
        getNaturalFeedback(formAnalysis: formAnalysis, exerciseType: .bodyweight) { naturalFeedback in
            // Split the natural feedback if needed for legacy support
            let parts = naturalFeedback.components(separatedBy: ", but ")
            if parts.count >= 2 {
                completion(parts[0], parts[1])
                    } else {
                // Create a split from the unified feedback
                completion("Good work there", "keep focusing on your form")
            }
        }
    }
}
