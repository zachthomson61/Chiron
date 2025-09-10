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
    
    // MARK: - Natural Single Feedback (Replaces Two-Point System)
    func getNaturalFeedback(formAnalysis: FormAnalysis, completion: @escaping (String) -> Void) {
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

        let prompt = """
        You are an encouraging athletic trainer coaching someone through bodyweight squats. Reply with ONE natural, conversational coaching message.

        Style and structure (very important):
        - Two clauses or two short sentences: PRAISE first, then a COACHING TIP
        - Praise can include natural enthusiasm (e.g., an exclamation)
        - The tip should start with: "Focus on...", "Try...", "Make sure...", or "On the next set, ..."
        - Be specific about technique (depth, knees over toes, chest up, tempo, bracing)
        - Sound human and supportive; avoid robotic lists or filler
        - Length target: 14–28 words

        Examples:
        - "Nice control on the way down! Focus on keeping your back straight on the next set."
        - "Great depth there, loved the tempo—try keeping your knees tracking over your toes next set."
        - "Good rhythm today! On the next round, keep your chest up and brace your core."

        ANALYSIS_METRICS:
        \(analysisJSON)

        MOVEMENT_SUMMARY:
        \(summary)
        """

        print("🤖 Natural: preparing OpenAI request for unified feedback")

        guard let url = URL(string: baseURL) else {
            completion(generateFallbackFeedback(from: formAnalysis))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                ["role": "system", "content": "You are a natural, encouraging athletic trainer. Speak conversationally as if you're right there coaching. Be specific and supportive."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 40,
            "temperature": 0.7
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(generateFallbackFeedback(from: formAnalysis))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ OpenAI natural feedback error: \(error)")
                DispatchQueue.main.async {
                    completion(self.generateFallbackFeedback(from: formAnalysis))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(self.generateFallbackFeedback(from: formAnalysis))
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
                            completion(self.generateFallbackFeedback(from: formAnalysis))
                        }
                    } else {
                        DispatchQueue.main.async {
                            completion(cleanedFeedback)
                        }
                    }
                } else {
                    print("❌ Natural: failed to parse OpenAI response")
                    DispatchQueue.main.async {
                        completion(self.generateFallbackFeedback(from: formAnalysis))
                    }
                }
            } catch {
                print("❌ Natural: parse error - \(error)")
                DispatchQueue.main.async {
                    completion(self.generateFallbackFeedback(from: formAnalysis))
                }
            }
        }.resume()
    }
    
    // MARK: - Natural Fallback Feedback
    private func generateFallbackFeedback(from analysis: FormAnalysis) -> String {
        // Natural, two-part phrasing with specific technique cues
        if analysis.issues.contains("Insufficient Depth") || analysis.depth < 0.45 {
            return "Nice control on the way down! Try sitting a little deeper on the next set."
        }
        if analysis.issues.contains("Forward Lean") || abs(analysis.backAngle) > 30 {
            return "Good tempo there! Focus on keeping your back straight and chest up next set."
        }
        if analysis.issues.contains("Knee Valgus") {
            return "Great effort! Make sure you push your knees out over your toes next set."
        }
        if analysis.issues.contains("Knee Varus") {
            return "Nice work staying steady! Keep your knees tracking straight over your toes next set."
        }
        if analysis.depth >= 0.6 {
            return "Great depth there! Keep that smooth tempo and stay tall on the next set."
        }
        return "Nice control there! Focus on bracing your core throughout the next set."
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
    func analyzeAndGetNaturalFeedback(formAnalysis: FormAnalysis, completion: @escaping (String) -> Void) {
        print("🤖 Starting natural feedback analysis")
        
        // Check for valid data first
        if formAnalysis.repCount <= 0 || formAnalysis.summary.isEmpty {
            let noDataFeedback = "I didn't catch that set - make sure you're visible in the frame."
            speakFeedback(noDataFeedback)
            completion(noDataFeedback)
            return
        }
        
        getNaturalFeedback(formAnalysis: formAnalysis) { feedback in
            print("🤖 Received natural feedback: \(feedback)")
            // Speak the unified feedback
            self.speakFeedback(feedback)
            completion(feedback)
        }
    }
    
    // MARK: - Backward compatibility wrapper
    // Previous API used throughout the app. Forward to the new natural feedback flow.
    func analyzeAndGetFeedback(formAnalysis: FormAnalysis, isDetailed: Bool = false, completion: @escaping (String) -> Void) {
        analyzeAndGetNaturalFeedback(formAnalysis: formAnalysis, completion: completion)
    }
    
    // MARK: - Legacy Support (Updated)
    func getCoachingFeedback(summary: String, isDetailed: Bool = false, completion: @escaping (String) -> Void) {
        // For backward compatibility, but encourage using the new natural feedback system
        print("🤖 Legacy coaching feedback called - consider using getNaturalFeedback instead")
        
        DispatchQueue.main.async {
            self.isRequestingFeedback = true
        }
        
        let prompt = generateNaturalCoachingPrompt(summary: summary, isDetailed: isDetailed)
        
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
    
    private func generateNaturalCoachingPrompt(summary: String, isDetailed: Bool = false) -> String {
        return """
        You are an athletic trainer giving natural, conversational feedback for bodyweight squats.

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
        getNaturalFeedback(formAnalysis: formAnalysis) { naturalFeedback in
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
