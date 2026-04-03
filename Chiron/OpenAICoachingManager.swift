//
//  OpenAICoachingManager.swift
//  Chiron
//
//  Phrasing-only coaching feedback via OpenAI API.
//
//  Architecture (correct pipeline):
//    pose → metrics → flags → ranked issues → PhrasingPayload → LLM phrasing
//
//  The LLM is used ONLY for natural phrasing, combining cues, and tone.
//  It must NOT decide what's wrong or interpret raw pose / metrics.
//  All issue detection, ranking, and suppression happen in CoachingLogic
//  (see CoachingContract.swift).
//

import Combine
import Foundation

// MARK: - OpenAI Coaching Manager

class OpenAICoachingManager: ObservableObject {
    static let shared = OpenAICoachingManager()

    @Published var isRequestingFeedback = false
    @Published var currentFeedback: String = ""

    static let insufficientDataFallback = "Good set. When you're ready, start your next set."

    private static let apiTimeoutSeconds: TimeInterval = 8

    private let apiKey = "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"
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    /// Stores the primary cue text delivered at set-end, keyed by exercise type.
    /// Enables the coach to reference the previous set's cue when the user does another set.
    private var lastCuedTextByExercise: [TrackedExerciseType: String] = [:]

    private init() {}

    // MARK: - Previous-Set Cue API

    /// Returns the cue given on the previous set for this exercise, or `nil` if none.
    func getLastCuedText(exerciseType: TrackedExerciseType) -> String? {
        lastCuedTextByExercise[exerciseType]
    }

    /// Records the primary cue delivered this set so the next set can reference it.
    /// Only stores non-empty cues; empty strings are ignored to avoid overwriting a real cue.
    func recordLastCued(exerciseType: TrackedExerciseType, cue: String) {
        guard !cue.isEmpty else { return }
        lastCuedTextByExercise[exerciseType] = cue
    }

    // MARK: - Main Entry Point

    /// Builds a `PhrasingPayload` from `FormAnalysis` via the deterministic logic layer,
    /// then asks the LLM only for natural phrasing. No raw metrics are sent.
    func analyzeAndGetNaturalFeedback(
        formAnalysis: FormAnalysis,
        exerciseType: TrackedExerciseType,
        completion: @escaping (String) -> Void
    ) {
        let payload = CoachingLogic.buildPayload(from: formAnalysis, exerciseType: exerciseType)

        // Short-circuit non-normal feedback states without calling the LLM
        guard payload.feedbackState == .normal else {
            let fb = Self.insufficientDataFallback
            completion(fb)
            return
        }

        getPhrasing(payload: payload, exerciseType: exerciseType, completion: completion)
    }

    // MARK: - LLM Phrasing (phrasing only — no assessment)

    /// Sends the pre-determined `PhrasingPayload` to the LLM for natural-language phrasing.
    /// The prompt explicitly instructs the model NOT to assess form or invent new issues.
    private func getPhrasing(
        payload: PhrasingPayload,
        exerciseType: TrackedExerciseType,
        completion: @escaping (String) -> Void
    ) {
        let exerciseLabel = Self.exerciseLabel(for: exerciseType)

        let primaryDisplay = payload.primaryIssue.map { CoachingContract.displayName(for: $0) }
        let primaryCue     = payload.primaryIssue.map { CoachingContract.cue(for: $0) }
        let secondaryDisplay = payload.secondaryIssue.map { CoachingContract.displayName(for: $0) }

        let previousCue = getLastCuedText(exerciseType: exerciseType)
        let previousCueBlock: String
        if let prev = previousCue, !prev.isEmpty {
            previousCueBlock = """

            PREVIOUS SET CUE: "\(prev)"
            If the same or similar issue applies this set, reference it (e.g. "keep working on that" or "same focus: …").
            If they improved on it, acknowledge briefly (e.g. "that looked better").
            Do NOT repeat the previous cue verbatim.
            """
        } else {
            previousCueBlock = ""
        }

        let prompt = """
        You are phrasing pre-determined coaching feedback for a \(exerciseLabel) set.

        PHRASING_PAYLOAD:
        \(payload.toJSON())

        RESOLVED CONTEXT:
        - Primary issue: \(primaryDisplay ?? "none") — cue: \(primaryCue ?? "none")
        - Secondary issue: \(secondaryDisplay ?? "none")
        - Positive note: \(payload.positiveNote ?? "none")
        - Rep count: \(payload.repCount)\(previousCueBlock)

        RULES:
        1. Start with a short positive phrase about what they did well (use the positive_note).
        2. Then give ONE specific coaching cue for the primary issue (use the cue text, rephrased naturally).
        3. If there is a secondary issue, weave it in briefly.
        4. If there is no primary issue, give praise only.
        5. Do NOT assess form, do NOT suggest new issues, do NOT interpret metrics.
        6. Do NOT use technical terms (eccentric, concentric, valgus, varus).
        7. Keep it 12–18 words, conversational, encouraging.

        EXAMPLES:
        "There we go, good depth — now push those knees out a bit more"
        "Nice control there, just keep that chest tall on the way down"
        "Solid set, elbows looked great — keep that same form"
        """

        if let primary = payload.primaryIssue {
            recordLastCued(exerciseType: exerciseType, cue: CoachingContract.cue(for: primary))
        }

        guard let url = URL(string: baseURL) else {
            let fb = generateFallbackFeedback(payload: payload, exerciseType: exerciseType)
            completion(fb)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                [
                    "role": "system",
                    "content": "You are a natural, encouraging athletic trainer. You only PHRASE pre-determined feedback — you never assess form or invent new issues. Use simple everyday language. Be specific and supportive."
                ],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 40,
            "temperature": 0.7
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            let fb = generateFallbackFeedback(payload: payload, exerciseType: exerciseType)
            completion(fb)
            return
        }

        let completionLock = NSLock()
        var didComplete = false

        let safeComplete: (String, String) -> Void = { feedback, _ in
            completionLock.lock()
            defer { completionLock.unlock() }
            guard !didComplete else { return }
            didComplete = true
            DispatchQueue.main.async { completion(feedback) }
        }

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }

            if error != nil {
                let fb = self.generateFallbackFeedback(payload: payload, exerciseType: exerciseType)
                safeComplete(fb, "path=api_fallback reason=network_error")
                return
            }
            guard let data = data else {
                let fb = self.generateFallbackFeedback(payload: payload, exerciseType: exerciseType)
                safeComplete(fb, "path=api_fallback reason=no_data")
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any],
                   let content = message["content"] as? String {

                    let cleaned = content
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: "  ", with: " ")

                    if self.isGenericResponse(cleaned) {
                        let fb = self.generateFallbackFeedback(payload: payload, exerciseType: exerciseType)
                        safeComplete(fb, "path=api_fallback reason=generic_response")
                    } else {
                        safeComplete(cleaned, "path=openai_success")
                    }
                } else {
                    let fb = self.generateFallbackFeedback(payload: payload, exerciseType: exerciseType)
                    safeComplete(fb, "path=api_fallback reason=parse_error")
                }
            } catch {
                let fb = self.generateFallbackFeedback(payload: payload, exerciseType: exerciseType)
                safeComplete(fb, "path=api_fallback reason=json_decode_error")
            }
        }
        task.resume()

        DispatchQueue.global().asyncAfter(deadline: .now() + Self.apiTimeoutSeconds) {
            let fb = self.generateFallbackFeedback(payload: payload, exerciseType: exerciseType)
            task.cancel()
            safeComplete(fb, "path=timeout")
        }
    }

    // MARK: - Deterministic Fallback

    /// Produces a hard-coded fallback sentence from the payload when the LLM is unavailable.
    /// Uses the contract's cue text for the primary issue.
    private func generateFallbackFeedback(payload: PhrasingPayload, exerciseType: TrackedExerciseType) -> String {
        let positive = payload.positiveNote ?? "Nice effort there"
        let positiveCapitalized = positive.prefix(1).uppercased() + positive.dropFirst()

        guard let primary = payload.primaryIssue else {
            return "\(positiveCapitalized) — keep that same form"
        }

        let cue = CoachingContract.cue(for: primary).lowercased()
        return "\(positiveCapitalized), now \(cue)"
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
        return genericCount >= 2 || response.count < 15
    }

    // MARK: - Helpers

    private static func exerciseLabel(for type: TrackedExerciseType) -> String {
        switch type {
        case .barbell: return "barbell back squat"
        case .bodyweight: return "bodyweight squat"
        case .benchPress: return "bench press"
        case .closeGripBenchPress: return "close-grip bench press"
        }
    }

    // MARK: - Backward Compatibility

    @available(*, deprecated, message: "Use analyzeAndGetNaturalFeedback(formAnalysis:exerciseType:completion:) with explicit exerciseType")
    func analyzeAndGetFeedback(formAnalysis: FormAnalysis, isDetailed: Bool = false, completion: @escaping (String) -> Void) {
        analyzeAndGetNaturalFeedback(formAnalysis: formAnalysis, exerciseType: .bodyweight, completion: completion)
    }

    /// Legacy string-based entry point. Builds a minimal FormAnalysis so the new pipeline can handle it.
    func getCoachingFeedback(summary: String, isDetailed: Bool = false, completion: @escaping (String) -> Void) {
        DispatchQueue.main.async { self.isRequestingFeedback = true }
        let minimalAnalysis = FormAnalysis(
            depth: 0.5, backAngle: 0.0, kneeAlignment: 0.0,
            overallScore: 0.5, issues: [], summary: summary,
            repCount: 1,
            avgEccentricMs: nil, avgPauseMs: nil, avgConcentricMs: nil,
            avgBottomDepth: nil, deepRepRatio: nil
        )
        analyzeAndGetNaturalFeedback(formAnalysis: minimalAnalysis, exerciseType: .bodyweight) { [weak self] feedback in
            DispatchQueue.main.async {
                self?.isRequestingFeedback = false
                self?.currentFeedback = feedback
                completion(feedback)
            }
        }
    }

    // MARK: - Legacy Speech (deprecated)

    @available(*, deprecated, message: "OpenAICoachingManager returns text only. Use SpeechManager.shared.speak() from the caller.")
    func speakFeedback(_ feedback: String) {
        SpeechManager.shared.speak(feedback, priority: .high)
    }

    @available(*, deprecated, message: "Use analyzeAndGetNaturalFeedback instead")
    func getTwoPointFeedback(formAnalysis: FormAnalysis, completion: @escaping (String, String) -> Void) {
        analyzeAndGetNaturalFeedback(formAnalysis: formAnalysis, exerciseType: .bodyweight) { feedback in
            let parts = feedback.components(separatedBy: ", but ")
            if parts.count >= 2 {
                completion(parts[0], parts[1])
            } else {
                completion("Good work there", "keep focusing on your form")
            }
        }
    }

    /// Convenience wrapper: builds PhrasingPayload for use by callers who only have a FormAnalysis.
    /// Deprecated — callers should migrate to `analyzeAndGetNaturalFeedback`.
    @available(*, deprecated, message: "Use analyzeAndGetNaturalFeedback")
    func getNaturalFeedback(formAnalysis: FormAnalysis, exerciseType: TrackedExerciseType, completion: @escaping (String) -> Void) {
        analyzeAndGetNaturalFeedback(formAnalysis: formAnalysis, exerciseType: exerciseType, completion: completion)
    }
}
