import Foundation
import AVFoundation

// MARK: - OpenAI Coaching Manager
class OpenAICoachingManager: ObservableObject {
    static let shared = OpenAICoachingManager()
    
    @Published var isRequestingFeedback = false
    @Published var currentFeedback: String = ""
    
    // OpenAI API Configuration
    private let apiKey = "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"
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    private init() {}
    
    // MARK: - Coaching Feedback Request
    func getCoachingFeedback(summary: String, isDetailed: Bool = false, completion: @escaping (String) -> Void) {
        print("🤖 Starting OpenAI API call with summary: \(summary)")
        
        DispatchQueue.main.async {
            self.isRequestingFeedback = true
        }
        
        let prompt = generateCoachingPrompt(summary: summary, isDetailed: isDetailed)
        print("🤖 Generated prompt: \(prompt)")
        
        let requestBody: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                [
                    "role": "system",
                    "content": "You are a friendly, enthusiastic fitness coach who speaks naturally and conversationally. You're encouraging, specific, and sound like a real person talking to a friend. Use natural language, be encouraging, and give specific, actionable feedback. Keep responses conversational and motivating."
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "max_tokens": 50,
            "temperature": 0.8
        ]
        
        guard let url = URL(string: baseURL) else {
            DispatchQueue.main.async {
                self.isRequestingFeedback = false
                completion("Unable to connect to coaching service.")
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
                completion("Error preparing coaching request.")
            }
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isRequestingFeedback = false
                
                if let error = error {
                    print("❌ OpenAI API error: \(error)")
                    completion("Network error. Please try again.")
                    return
                }
                
                guard let data = data else {
                    completion("No response from coaching service.")
                    return
                }
                
                do {
                    print("🤖 Parsing OpenAI response...")
                    if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = jsonResponse["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        
                        let feedback = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        print("🤖 Successfully parsed OpenAI feedback: \(feedback)")
                        
                        // Check for NO_VALID_DATA response
                        if feedback.uppercased().contains("NO_VALID_DATA") {
                            print("🤖 No valid exercise data detected")
                            self?.currentFeedback = "No exercise detected. Please ensure visible in the camera frame."
                            completion("No exercise detected. Please ensure you are performing squats and visible in the camera frame.")
                        } else {
                            self?.currentFeedback = feedback
                            completion(feedback)
                        }
                        
                    } else {
                        print("❌ Unexpected OpenAI response format")
                        print("🤖 Raw response: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
                        completion("Unable to parse coaching feedback.")
                    }
                } catch {
                    print("❌ Error parsing OpenAI response: \(error)")
                    completion("Error processing coaching feedback.")
                }
            }
        }.resume()
    }
    
    private func generateCoachingPrompt(summary: String, isDetailed: Bool = false) -> String {
        // Note: coachingStyles was intended for future use but not currently needed
        
        if isDetailed {
            // End of workout feedback - brief and encouraging
            return """
            You are a friendly, encouraging fitness coach. A user just completed a workout with the following form analysis:

            \(summary)

            IMPORTANT: First evaluate if this contains valid exercise data:
            - If no reps were completed (rep count = 0) → respond with "NO_VALID_DATA"
            - If the analysis shows no meaningful exercise (just face, no movement) → respond with "NO_VALID_DATA"
            - If the form analysis is empty or invalid → respond with "NO_VALID_DATA"
            
            If valid exercise data exists, respond briefly and conversationally:
            - If the form score is high (above 80%), give a short encouragement like "Great form!" or "Excellent work!"
            - If the score is lower, briefly mention what they did well, then give one constructive tip for next time
            
            Keep it brief and encouraging.
            """
        } else {
            // During workout feedback - very brief and adaptive
            return """
            You are a friendly, encouraging fitness coach. A user just completed a set with the following form analysis:

            \(summary)

            IMPORTANT: First evaluate if this contains valid exercise data:
            - If no reps were completed (rep count = 0) → respond with "NO_VALID_DATA"
            - If the analysis shows no meaningful exercise (just face, no movement) → respond with "NO_VALID_DATA"
            - If the form analysis is empty or invalid → respond with "NO_VALID_DATA"
            
            If valid exercise data exists, respond very briefly:
            - If the form score is high (above 80%), give only a short encouragement like "Great form!" or "Perfect!"
            - If the score is lower, briefly mention what they did well, then give one quick tip for the next set
            
            Keep it very brief - no more than 10 words total.
            """
        }
    }
    
    // MARK: - Speech Synthesis
    func speakFeedback(_ feedback: String) {
        // Use the main SpeechManager instead of creating a new synthesizer
        SpeechManager.shared.speak(feedback, priority: .normal)
        print("🎤 Speaking coaching feedback: \(feedback)")
    }
    
    // MARK: - Combined Analysis and Feedback
    func analyzeAndGetFeedback(formAnalysis: FormAnalysis, isDetailed: Bool = false, completion: @escaping (String) -> Void) {
        let summary = formAnalysis.summary
        print("🤖 Starting OpenAI analysis with summary: \(summary)")
        
        // Add context about the exercise and user level
        let contextualSummary = """
        Exercise: Bodyweight Squat (beginner-friendly)
        User Level: Beginner to Intermediate
        Reps Completed: \(formAnalysis.repCount) reps
        Form Analysis: \(summary)
        
        Note: This is a bodyweight squat, so focus on form over weight. The user is working on building proper movement patterns. Consider their rep count when giving advice - if they did many reps, they might be getting tired and form could be breaking down.
        
        IMPORTANT: Evaluate if this contains valid exercise data:
        - Rep count: \(formAnalysis.repCount)
        - Form analysis: \(summary)
        - If rep count is 0 or analysis is empty/invalid, respond with "NO_VALID_DATA"
        """
        
        getCoachingFeedback(summary: contextualSummary, isDetailed: isDetailed) { feedback in
            print("🤖 Received OpenAI feedback: \(feedback)")
            // Speak the feedback aloud
            self.speakFeedback(feedback)
            completion(feedback)
        }
    }
} 