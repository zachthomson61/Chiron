//
//  OpenAIClient.swift
//  Chiron
//
//  OpenAI Responses API client for structured coaching feedback.
//  Uses the /v1/responses endpoint with JSON schema output format.
//

import Foundation

// MARK: - Coaching Response Model

/// Structured coaching response from OpenAI.
/// Contains headline, positive feedback, and optional corrective cues.
struct CoachingResponse: Codable {
    /// Tone of the response: "praise_only" (score >= 75) or "mixed" (score < 75)
    let tone: String
    
    /// Short headline/hype line for the coaching
    let headline: String
    
    /// 1-2 things the user did well (always populated)
    let did_well: [String]
    
    /// 0-2 corrective cues (empty if formScore >= 75)
    let fix_next: [String]
    
    /// Combines headline and feedback into a speakable string
    func toSpeakableText() -> String {
        var parts: [String] = [headline]
        
        if !did_well.isEmpty {
            parts.append(did_well.joined(separator: ". "))
        }
        
        if !fix_next.isEmpty {
            parts.append("Next set, focus on: " + fix_next.joined(separator: ". "))
        }
        
        return parts.joined(separator: " ")
    }
}

// MARK: - OpenAI Client Errors

enum OpenAIClientError: LocalizedError {
    case invalidURL
    case invalidAPIKey
    case rateLimited
    case badRequest(String)
    case serverError(Int)
    case decodingFailed(String)
    case networkError(Error)
    case timeout
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidAPIKey:
            return "Invalid API key (401)"
        case .rateLimited:
            return "Rate limit exceeded (429). Please try again later."
        case .badRequest(let message):
            return "Bad request: \(message)"
        case .serverError(let code):
            return "Server error (\(code))"
        case .decodingFailed(let message):
            return "Failed to parse response: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .timeout:
            return "Request timed out"
        case .unknownError:
            return "Unknown error occurred"
        }
    }
}

// MARK: - OpenAI Client

/// Client for OpenAI Responses API with structured JSON output.
/// Enforces the >= 75 form score policy for praise-only feedback.
actor OpenAIClient {
    static let shared = OpenAIClient()
    
    // MARK: - Configuration
    
    /// OpenAI API key.
    ///
    /// IMPORTANT:
    /// - Never hardcode API keys in source control.
    /// - This client reads the key from either:
    ///   1) Environment variable: `OPENAI_API_KEY` (useful for local tooling / CI)
    ///   2) App `Info.plist` entry: `OPENAI_API_KEY` (recommended for local dev only)
    ///
    /// If no key is found, requests will fail fast with `OpenAIClientError.invalidAPIKey`.
    private var apiKey: String {
        let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let envKey, !envKey.isEmpty { return envKey }
        
        let plistKey = (Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let plistKey, !plistKey.isEmpty { return plistKey }
        
        return ""
    }
    private let baseURL = "https://api.openai.com/v1/responses"
    private let model = "gpt-4o"
    private let timeoutSeconds: TimeInterval = 30
    
    private init() {}
    
    // MARK: - Public API
    
    /// Gets coaching feedback for a close-grip bench press set.
    ///
    /// **Policy Enforcement:**
    /// - If `formScore >= 75`: Enforces praise-only mode by hard-filtering `fix_next` to be empty
    /// - Uses structured JSON schema output for safe parsing
    /// - Handles all HTTP errors, timeouts, and decoding failures
    ///
    /// - Parameter summary: Compact summary of the set metrics
    /// - Returns: Structured coaching response
    /// - Throws: OpenAIClientError on failure
    func getBenchCoaching(summary: CloseGripBenchSummary) async throws -> CoachingResponse {
        let praiseOnly = summary.formScore >= 75
        
        // Build the request with appropriate prompt and JSON schema
        let request = try buildRequest(summary: summary, praiseOnly: praiseOnly)
        
        debugLog("Request URL: \(baseURL)")
        
        // Execute the request
        let (data, response) = try await executeRequest(request)
        
        // Handle HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.unknownError
        }
        
        debugLog("HTTP Status: \(httpResponse.statusCode)")
        
        // Check for errors
        try handleHTTPStatus(httpResponse.statusCode, data: data)
        
        // Parse the response
        var coachingResponse = try parseResponse(data)
        
        // Hard-filter: if praiseOnly, ensure fix_next is empty (policy enforcement)
        if praiseOnly && !coachingResponse.fix_next.isEmpty {
            debugLog("Policy enforcement: Clearing fix_next for score >= 75")
            coachingResponse = CoachingResponse(
                tone: "praise_only",
                headline: coachingResponse.headline,
                did_well: coachingResponse.did_well,
                fix_next: []
            )
        }
        
        return coachingResponse
    }
    
    // MARK: - Request Building
    
    private func buildRequest(summary: CloseGripBenchSummary, praiseOnly: Bool) throws -> URLRequest {
        guard let url = URL(string: baseURL) else {
            throw OpenAIClientError.invalidURL
        }
        
        guard !apiKey.isEmpty else {
            throw OpenAIClientError.invalidAPIKey
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeoutSeconds
        
        // Build the prompt
        let systemPrompt = "You are a strength coach. Be concise. Never mention being an AI."
        let userPrompt = buildUserPrompt(summary: summary, praiseOnly: praiseOnly)
        
        // Build the request body with JSON schema
        let body: [String: Any] = [
            "model": model,
            "input": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "bench_coaching",
                    "schema": buildJSONSchema(praiseOnly: praiseOnly),
                    "strict": true
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        
        return request
    }
    
    private func buildUserPrompt(summary: CloseGripBenchSummary, praiseOnly: Bool) -> String {
        guard let summaryJSON = summary.toJSONString() else {
            return "Generate coaching for close-grip bench press."
        }
        
        let policyInstruction: String
        if praiseOnly {
            policyInstruction = """
            IMPORTANT: The form score is \(summary.formScore) (>= 75), which is GOOD.
            You MUST NOT provide any critical feedback or corrective cues.
            The fix_next array MUST be empty [].
            Only provide positive reinforcement: call out 1-2 things done well.
            The tone MUST be "praise_only".
            """
        } else {
            policyInstruction = """
            The form score is \(summary.formScore) (< 75), which indicates room for improvement.
            Provide exactly 1 thing done well in did_well (find something positive even if score is low).
            Provide 1-2 short, actionable corrective cues in fix_next based on the keyWarnings.
            Each cue should be <= 12 words and actionable.
            The tone MUST be "mixed".
            """
        }
        
        return """
        Generate coaching feedback for a close-grip bench press set.
        
        Set summary (JSON):
        \(summaryJSON)
        
        \(policyInstruction)
        
        Close-grip bench press coaching priorities:
        - Grip width: should be just outside ribs (narrower than regular bench)
        - Elbow position: elbows should be tucked to sides (not flared)
        - ROM: full lockout at top, bar touches chest at bottom
        - Tempo: slow controlled eccentric (1+ sec), explosive concentric
        
        Keep the headline short and encouraging (like "Solid set!" or "Great control!").
        Keep did_well items specific to the metrics or general close-grip bench mechanics.
        """
    }
    
    private func buildJSONSchema(praiseOnly: Bool) -> [String: Any] {
        return [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "tone": [
                    "type": "string",
                    "enum": ["praise_only", "mixed"]
                ],
                "headline": [
                    "type": "string"
                ],
                "did_well": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "fix_next": [
                    "type": "array",
                    "items": ["type": "string"]
                ]
            ],
            "required": ["tone", "headline", "did_well", "fix_next"]
        ]
    }
    
    // MARK: - Request Execution
    
    private func executeRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw OpenAIClientError.timeout
        } catch {
            throw OpenAIClientError.networkError(error)
        }
    }
    
    // MARK: - Response Handling
    
    private func handleHTTPStatus(_ statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200...299:
            return // Success
        case 401:
            throw OpenAIClientError.invalidAPIKey
        case 429:
            throw OpenAIClientError.rateLimited
        case 400:
            let message = extractErrorMessage(from: data) ?? "Invalid request"
            throw OpenAIClientError.badRequest(message)
        default:
            throw OpenAIClientError.serverError(statusCode)
        }
    }
    
    private func extractErrorMessage(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return nil
    }
    
    private func parseResponse(_ data: Data) throws -> CoachingResponse {
        if let responseString = String(data: data, encoding: .utf8) {
            let truncated = String(responseString.prefix(2000))
            debugLog("Response body (first 2k chars): \(truncated)")
        }
        
        // Parse the Responses API response structure
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIClientError.decodingFailed("Invalid JSON response")
        }
        
        // The Responses API returns output in the "output" array
        // Each item has a "content" array with the actual content
        guard let output = json["output"] as? [[String: Any]],
              let firstOutput = output.first,
              let content = firstOutput["content"] as? [[String: Any]],
              let textContent = content.first(where: { ($0["type"] as? String) == "output_text" }),
              let text = textContent["text"] as? String else {
            
            // Try alternative response structure (direct text field)
            if let outputText = json["output_text"] as? String {
                return try decodeCoachingResponse(from: outputText)
            }
            
            throw OpenAIClientError.decodingFailed("Could not extract text from response")
        }
        
        return try decodeCoachingResponse(from: text)
    }
    
    private func decodeCoachingResponse(from text: String) throws -> CoachingResponse {
        guard let textData = text.data(using: .utf8) else {
            throw OpenAIClientError.decodingFailed("Invalid text encoding")
        }
        
        do {
            return try JSONDecoder().decode(CoachingResponse.self, from: textData)
        } catch {
            throw OpenAIClientError.decodingFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Debug Logging
    
    private func debugLog(_ message: String) {
        // Never log the API key
        if apiKey.isEmpty {
            return
        }
        
        let safeMessage = message.replacingOccurrences(of: apiKey, with: "[REDACTED]")
    }
}
