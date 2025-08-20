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
    
    // MARK: - Two-point concise feedback
    func getTwoPointFeedback(formAnalysis: FormAnalysis, completion: @escaping (String, String) -> Void) {
        let summary = formAnalysis.summary
        // Provide structured metrics and issues to reduce generic answers
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

        let prompt = """
        You are a concise fitness coach for bodyweight squats.
        Use the analysis below to output ONLY compact JSON with two short cues:
        {"good":"<one short, specific thing they did well>", "improve":"<one short, specific thing to improve>"}
        Rules:
        - Be specific and actionable (e.g., "Push your knees out", "Keep chest tall", "Brace your core").
        - Do NOT mention reps, sets, or scores.
        - Do NOT output generic phrases like "Completed full set" or "Work on form" or "Keep practicing".
        - Keep each value under 9 words, no punctuation at the end, no newlines.

        ANALYSIS_METRICS_JSON:
        \(analysisJSON)

        ANALYSIS_SUMMARY:
        \(summary)
        """

        print("🤖 TwoPoint: preparing OpenAI request. Summary length=\(summary.count)")

        guard let url = URL(string: baseURL) else {
            completion("Good control.", "Go a bit deeper.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                ["role": "system", "content": "You are a precise JSON generator. Output only JSON, no commentary."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 60,
            "temperature": 0.6
        ]

        do { request.httpBody = try JSONSerialization.data(withJSONObject: body) } catch {
            completion("Good control.", "Go a bit deeper.")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let http = response as? HTTPURLResponse {
                print("🤖 TwoPoint: HTTP status=\(http.statusCode)")
            }
            if let error = error {
                print("❌ OpenAI two-point error: \(error)")
                DispatchQueue.main.async { completion("Good control.", "Go a bit deeper.") }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion("Good control.", "Go a bit deeper.") }
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    print("🤖 TwoPoint: raw content=\(content)")
                    var good = ""
                    var improve = ""
                    if let contentData = content.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: contentData) as? [String: Any] {
                        good = (parsed["good"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        improve = (parsed["improve"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    } else {
                        // Heuristic fallback: split
                        let parts = content
                            .replacingOccurrences(of: "\n", with: ". ")
                            .components(separatedBy: ". ")
                            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        good = parts.first ?? "Good control"
                        improve = parts.dropFirst().first ?? "Go a bit deeper"
                    }
                    // Filter generic content
                    let genericPatterns = ["completed full set", "work on", "form", "practice", "overall", "good job", "nice work"]
                    func isGeneric(_ s: String) -> Bool {
                        let lower = s.lowercased()
                        return genericPatterns.contains { lower.contains($0) }
                    }
                    if good.isEmpty || improve.isEmpty || isGeneric(good) || isGeneric(improve) {
                        // Build rule-based fallback from metrics/issues
                        let fallback = Self.ruleBasedTwoPoint(from: formAnalysis)
                        DispatchQueue.main.async { completion(fallback.0, fallback.1) }
                    } else {
                        DispatchQueue.main.async { completion(good, improve) }
                    }
                } else {
                    DispatchQueue.main.async { completion("Good control.", "Go a bit deeper.") }
                }
            } catch {
                print("❌ Parse error: \(error)")
                DispatchQueue.main.async { completion("Good control.", "Go a bit deeper.") }
            }
        }.resume()
    }

    private static func ruleBasedTwoPoint(from analysis: FormAnalysis) -> (String, String) {
        // Good
        let good: String
        if analysis.depth >= 0.6 {
            good = "Good depth"
        } else if abs(analysis.backAngle) <= 25 {
            good = "Chest tall"
        } else {
            good = "Controlled tempo"
        }
        // Improve
        let improve: String
        if analysis.issues.contains("Knee Valgus") {
            improve = "Push your knees out"
        } else if analysis.issues.contains("Knee Varus") {
            improve = "Keep knees over toes"
        } else if analysis.issues.contains("Forward Lean") {
            improve = "Lift your chest"
        } else if analysis.issues.contains("Insufficient Depth") || analysis.depth < 0.45 {
            improve = "Squat a little deeper"
        } else {
            improve = "Brace your core"
        }
        return (good, improve)
    }
} 