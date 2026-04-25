//
//  OpenAICoachingManager.swift
//  Chiron
//
//  Phrasing-only coaching feedback via OpenAI API.
//
//  Architecture (set-end pipeline):
//    pose → frame metrics → per-set aggregation
//        → SetEndFeedbackPlanner (Stage 1 + Stage 2 gate in Swift)
//        → LLM phrasing (persona-aware) → SetEndFeedback
//
//  The LLM is used ONLY for phrasing the deterministic plan. It never
//  decides whether to critique — that decision happens in Swift via
//  `SetEndFeedbackPlanner.plan(...)`. When the gate suppresses the
//  critique, the prompt instructs the model to return a positive-only
//  line; a clean set is a first-class outcome, not a missing slot.
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
    /// Enables the coach to reference the previous set's cue when the user does another set,
    /// and feeds the Stage 2 gate's repeated-cue suppression check.
    private var lastCuedTextByExercise: [TrackedExerciseType: String] = [:]

    /// 1-based set counter per exercise in the current app session. Drives the
    /// movement-limitation-based safety-cue cadence; reset whenever the
    /// onboarding profile changes (e.g. the user just finished onboarding).
    private var setIndexByExercise: [TrackedExerciseType: Int] = [:]

    /// Cached user profile for profile-aware phrasing. Lazily loaded from the
    /// store and refreshed whenever `refreshProfile()` is called — typically
    /// right after onboarding completes.
    private var cachedProfile: ChironUserProfile?
    private let profileStore: UserProfileStore

    private init(profileStore: UserProfileStore = UserDefaultsUserProfileStore()) {
        self.profileStore = profileStore
        self.cachedProfile = profileStore.load()
    }

    /// Call after onboarding finishes (or whenever the persisted profile
    /// changes) so subsequent feedback uses the new values without requiring
    /// a relaunch.
    func refreshProfile() {
        cachedProfile = profileStore.load()
        setIndexByExercise.removeAll()
    }

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

    // MARK: - Public API — set-end feedback

    /// Primary entry point. Builds a deterministic `SetEndFeedbackPlanner.Plan`
    /// via Stage 1 + Stage 2 in Swift, then calls the LLM to phrase the plan
    /// (persona-aware). On network/parse failure, falls back to a deterministic
    /// spoken line. Always returns a fully-populated `SetEndFeedback`.
    ///
    /// - Parameter personalRecord: when non-nil, the just-completed set beat
    ///   the user's prior best for this exercise. The planner suppresses any
    ///   non-safety-critical critique so the spoken line celebrates cleanly,
    ///   and the prompt is injected with PR context so the model opens with
    ///   an explicit "personal record" call-out. Safety-critical cues still
    ///   surface — a dangerous rep at a new PR is exactly when the coach
    ///   needs to speak up.
    func generateSetEndFeedback(
        formAnalysis: FormAnalysis,
        aggregatedMetrics: SetEndAggregatedMetrics,
        exerciseType: TrackedExerciseType,
        personalRecord: PersonalRecord.Info? = nil,
        completion: @escaping (SetEndFeedback) -> Void
    ) {
        // Early out: confidence / data-quality short-circuit — no LLM call.
        let payload = CoachingLogic.buildPayload(from: formAnalysis, exerciseType: exerciseType)
        guard payload.feedbackState == .normal else {
            let fb = SetEndFeedback(
                bestThing: "",
                nextSetFocus: nil,
                tone: .clean,
                spokenText: Self.insufficientDataFallback,
                displayShortCue: nil,
                suppressionReason: nil,
                candidateIssue: nil
            )
            completion(fb)
            return
        }

        // Advance the per-exercise set index so safety-cue cadence works
        // and the Stage 2 repeat-set gate has the right context.
        setIndexByExercise[exerciseType, default: 0] += 1
        let currentSetIndex = setIndexByExercise[exerciseType] ?? 1
        let profileContext = cachedProfile.map {
            CoachingProfileContext(
                profile: $0,
                exerciseType: exerciseType,
                setIndex: currentSetIndex
            )
        }

        // Stage 1 + Stage 2 in Swift. The LLM never sees the raw metrics or
        // decides whether to critique; it only phrases the decided plan.
        let plan = SetEndFeedbackPlanner.plan(
            formAnalysis: formAnalysis,
            aggregatedMetrics: aggregatedMetrics,
            exerciseType: exerciseType,
            previousCueText: getLastCuedText(exerciseType: exerciseType),
            setIndex: currentSetIndex,
            isPersonalRecord: personalRecord != nil
        )

        // Remember the cue we surfaced (for the next set's repeated-cue check).
        if let surfaced = plan.surfacedIssue {
            recordLastCued(exerciseType: exerciseType, cue: CoachingContract.cue(for: surfaced))
        }

        phraseAndComplete(
            plan: plan,
            exerciseType: exerciseType,
            profileContext: profileContext,
            personalRecord: personalRecord,
            completion: completion
        )
    }

    /// Back-compat shim for legacy callers that only have a FormAnalysis and
    /// expect a spoken string. New callers should use `generateSetEndFeedback`.
    func analyzeAndGetNaturalFeedback(
        formAnalysis: FormAnalysis,
        exerciseType: TrackedExerciseType,
        completion: @escaping (String) -> Void
    ) {
        generateSetEndFeedback(
            formAnalysis: formAnalysis,
            aggregatedMetrics: .empty,
            exerciseType: exerciseType,
            personalRecord: nil
        ) { feedback in
            completion(feedback.spokenText)
        }
    }

    // MARK: - LLM phrasing (phrasing only — no assessment)

    private func phraseAndComplete(
        plan: SetEndFeedbackPlanner.Plan,
        exerciseType: TrackedExerciseType,
        profileContext: CoachingProfileContext?,
        personalRecord: PersonalRecord.Info?,
        completion: @escaping (SetEndFeedback) -> Void
    ) {
        let exerciseLabel = Self.exerciseLabel(for: exerciseType)

        // Profile + safety directives are unchanged from the previous pipeline.
        let profileBlock: String
        if let profileContext, let block = profileContext.promptBlock {
            profileBlock = """


            COACHING PROFILE (persist across the whole response):
            \(block)
            """
        } else {
            profileBlock = ""
        }

        let safetyOverride: String
        if let profileContext, profileContext.injectSafetyThisSet {
            safetyOverride = """


            SAFETY OVERRIDE:
            A safety cue is required this set. Always include it, even if FEEDBACK_TONE is "clean" and the default rule would tell you to give praise only. Name the flagged area by its coaching noun (e.g., "knees", "lower back"). The safety cue replaces or precedes any other cue — do not skip it.
            """
        } else {
            safetyOverride = ""
        }

        let previousCue = getLastCuedText(exerciseType: exerciseType)
        let previousCueBlock: String
        if let prev = previousCue, !prev.isEmpty, plan.tone == .corrective {
            previousCueBlock = """


            PREVIOUS SET CUE: "\(prev)"
            If this set's cue is similar, rephrase it — do not repeat verbatim.
            If they improved, acknowledge briefly ("that looked better").
            """
        } else {
            previousCueBlock = ""
        }

        // PR celebration block: when the set just beat the user's prior best,
        // the spoken line opens with an explicit "personal record" call-out
        // and skips all non-safety-critical critique. Safety cues, when the
        // SAFETY OVERRIDE fires, still precede everything else — a risky rep
        // at a new PR is exactly when the coach needs to speak up.
        let personalRecordBlock: String
        if let pr = personalRecord {
            personalRecordBlock = """


            PERSONAL RECORD (mandatory — this is the athlete's new best):
            - Descriptor (say aloud): "\(pr.spokenDescriptor)"
            - Open the line by celebrating the PR explicitly. Use the exact phrase "personal record" at the start.
            - Do NOT deliver any form-correction cue, optimization cue, or critical feedback in this response, UNLESS a SAFETY OVERRIDE is present — safety cues still take precedence.
            - Keep the line warm and confident, not over-the-top.
            """
        } else {
            personalRecordBlock = ""
        }

        let cueText = plan.nextSetFocus ?? "none"
        let toneLabel = plan.tone.rawValue
        let suppressionDebug = plan.suppressionReason?.rawValue ?? "none"
        let lengthBudget: String
        if personalRecord != nil {
            lengthBudget = "10–20 words, celebratory, one natural sentence"
        } else if plan.tone == .corrective {
            lengthBudget = "12–22 words, one natural sentence"
        } else {
            lengthBudget = "6–14 words, positive-only, one natural sentence"
        }

        let prompt = """
        You are phrasing pre-determined coaching feedback for a \(exerciseLabel) set.

        PLAN (already decided — do not second-guess):
        - FEEDBACK_TONE: \(toneLabel)
        - BEST_THING: \(plan.bestThing)
        - NEXT_SET_CUE: \(cueText)
        - SUPPRESSION_REASON (debug, never mention): \(suppressionDebug)\(previousCueBlock)\(personalRecordBlock)\(profileBlock)\(safetyOverride)

        RULES:
        1. If PERSONAL RECORD is present, the line MUST open with the phrase "personal record" and include the descriptor exactly as given. Do NOT include any critique, form correction, or optimization suggestion in a PR response, unless SAFETY OVERRIDE is also present (safety always wins).
        2. If FEEDBACK_TONE is "clean" and PERSONAL RECORD is absent, output a short positive-only line that references BEST_THING. Do NOT invent a correction, do NOT mention anything about what to fix. A clean set is a reward — say so confidently.
        3. If FEEDBACK_TONE is "corrective" and PERSONAL RECORD is absent, output one natural sentence that opens with BEST_THING and then delivers NEXT_SET_CUE, rephrased naturally.
        4. SAFETY OVERRIDE, when present, is mandatory regardless of FEEDBACK_TONE and precedes everything else.
        5. Do NOT assess form, do NOT invent issues, do NOT interpret metrics.
        6. Do NOT use technical terms (eccentric, concentric, valgus, varus).
        7. Do NOT use similes, metaphors, or figurative comparisons. ANY clause starting with "like …", "as if …", "as though …", or "as X as Y" is forbidden. Banned examples — do NOT emit anything resembling these: "like you're showing off a medal", "as if you're holding a tray", "as solid as a rock", "like a well-oiled machine". Speak plainly and directly — every word is a literal cue spoken aloud.
        8. Length: \(lengthBudget). Conversational, encouraging. Match persona + intensity from the COACHING PROFILE.
        9. NEVER ask the athlete a question. The output is spoken aloud and the athlete cannot respond. Phrase every cue as a statement.

        EXAMPLES (illustrative shape only — your actual cue MUST come from NEXT_SET_CUE, never from these):
        clean  → "That set was dialed in — \\(BEST_THING here)."
        clean  → "Clean reps. Same thing next set."
        corrective → "\\(BEST_THING here), now \\(NEXT_SET_CUE rephrased)."
        PR     → "Personal record — 185 for 8. Huge work."
        PR     → "Personal record — 25 reps. That's a new best, great job."
        """

        guard let url = URL(string: baseURL) else {
            completion(buildFallbackFeedback(plan: plan, profileContext: profileContext))
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
                    "content": "You are a natural, encouraging athletic trainer. You only PHRASE pre-determined feedback — you never assess form or invent new issues. When FEEDBACK_TONE is 'clean', you happily give positive-only feedback — silence on a clean set is a feature, not a gap. Use simple everyday language."
                ],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 50,
            "temperature": 0.7
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(buildFallbackFeedback(plan: plan, profileContext: profileContext))
            return
        }

        let completionLock = NSLock()
        var didComplete = false

        let safeComplete: (SetEndFeedback) -> Void = { fb in
            completionLock.lock()
            defer { completionLock.unlock() }
            guard !didComplete else { return }
            didComplete = true
            DispatchQueue.main.async { completion(fb) }
        }

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }

            if error != nil {
                safeComplete(self.buildFallbackFeedback(plan: plan, profileContext: profileContext))
                return
            }
            guard let data = data else {
                safeComplete(self.buildFallbackFeedback(plan: plan, profileContext: profileContext))
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any],
                   let content = message["content"] as? String {

                    let cleaned = Self.stripSimiles(
                        content
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "\n", with: " ")
                            .replacingOccurrences(of: "  ", with: " ")
                    )

                    if self.isGenericResponse(cleaned) {
                        safeComplete(self.buildFallbackFeedback(plan: plan, profileContext: profileContext))
                    } else {
                        safeComplete(self.buildFeedback(plan: plan, spokenText: cleaned))
                    }
                } else {
                    safeComplete(self.buildFallbackFeedback(plan: plan, profileContext: profileContext))
                }
            } catch {
                safeComplete(self.buildFallbackFeedback(plan: plan, profileContext: profileContext))
            }
        }
        task.resume()

        DispatchQueue.global().asyncAfter(deadline: .now() + Self.apiTimeoutSeconds) {
            task.cancel()
            safeComplete(self.buildFallbackFeedback(plan: plan, profileContext: profileContext))
        }
    }

    // MARK: - SetEndFeedback construction

    /// Wraps a plan + an LLM-phrased spoken string into a full SetEndFeedback.
    private func buildFeedback(
        plan: SetEndFeedbackPlanner.Plan,
        spokenText: String
    ) -> SetEndFeedback {
        SetEndFeedback(
            bestThing: plan.bestThing,
            nextSetFocus: plan.nextSetFocus,
            tone: plan.tone,
            spokenText: spokenText,
            displayShortCue: plan.displayShortCue,
            suppressionReason: plan.suppressionReason,
            candidateIssue: plan.candidateIssue
        )
    }

    /// Deterministic spoken-text fallback for when the LLM is unavailable or
    /// returns something generic/unusable. Still respects the plan's tone.
    private func buildFallbackFeedback(
        plan: SetEndFeedbackPlanner.Plan,
        profileContext: CoachingProfileContext?
    ) -> SetEndFeedback {
        let capitalizedBest = plan.bestThing.isEmpty
            ? "Nice effort there"
            : (plan.bestThing.prefix(1).uppercased() + plan.bestThing.dropFirst())
        let safety = profileContext?.fallbackSafetyClause

        let base: String
        switch plan.tone {
        case .corrective:
            if let cue = plan.nextSetFocus {
                base = "\(capitalizedBest), now \(cue.lowercased())"
            } else {
                base = "\(capitalizedBest) — keep that same form"
            }
        case .clean:
            base = "\(capitalizedBest) — that set was dialed in"
        }

        let spoken = safety.map { "\($0). \(base)" } ?? base
        return buildFeedback(plan: plan, spokenText: spoken)
    }

    // MARK: - Simile / figurative-language filter

    /// Defence-in-depth against similes and figurative comparisons that slip
    /// past the prompt rule. Strips clauses introduced by `like …`, `as if …`,
    /// `as though …`, and `as X as …` through the next sentence boundary,
    /// then cleans up residue. Keeps the surrounding sentence intact.
    ///
    /// Literal coaching language lands better than clever flourishes, and
    /// similes throw off the speech synthesiser's cadence. Examples that
    /// MUST be stripped:
    ///   "You're dialled in, like you're showing off a medal."
    ///   "Lock it out as if you're standing at attention."
    ///   "Chest up, like a proud lion."
    ///   "Stand as tall as a flagpole."
    ///
    /// The `\blike\b` pattern is intentionally aggressive — in a short
    /// coaching cue the word "like" is effectively always a simile
    /// introducer, not a literal verb ("I like that"). False positives are
    /// acceptable here; overcoached-sounding audio is not.
    static func stripSimiles(_ text: String) -> String {
        // One alternation covers every introducer we care about. All four are
        // treated as simile bait: "like", "as if", "as though", "as X as Y".
        // False positives on literal uses of these words are acceptable —
        // in a short spoken coaching cue, they're effectively always similes.
        let introducer = #"\b(?:like|as\s+if|as\s+though|as\s+[a-z]+\s+as)\b"#

        // Three structural patterns, applied in order. Each gets global
        // replacement against the full string.
        //
        // 1) Trailing-simile attached to a finished sentence:
        //    "Great set. Like a rocket!" → "Great set."
        //    Uses a lookbehind so the opening ".!?" is preserved; consumes
        //    the simile's own terminating punctuation.
        // 2) Embedded simile introduced by a comma:
        //    "You're dialled in, like you're showing off a medal."
        //      → "You're dialled in."
        //    Stops before the next punctuation so the sentence-ending "."
        //    stays attached to the surviving clause.
        // 3) Inline simile with no comma boundary:
        //    "You're dialled in like a rocket."
        //      → "You're dialled in."
        let patterns: [String] = [
            #"(?i)(?<=[.!?])\s+"# + introducer + #"[^.!?]+[.!?]?"#,
            #"(?i)\s*,\s+"# + introducer + #"[^,.!?]+"#,
            #"(?i)\s+"# + introducer + #"[^,.!?]+"#
        ]

        var out = text
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(out.startIndex..<out.endIndex, in: out)
                out = regex.stringByReplacingMatches(
                    in: out, range: range, withTemplate: ""
                )
            }
        }

        // Residue cleanup for doubled separators or adjacency artefacts.
        out = out.replacingOccurrences(of: "  ", with: " ")
        out = out.replacingOccurrences(of: " ,", with: ",")
        out = out.replacingOccurrences(of: " .", with: ".")
        out = out.replacingOccurrences(of: ".!", with: ".")
        out = out.replacingOccurrences(of: ".?", with: ".")
        out = out.replacingOccurrences(of: "!.", with: "!")
        out = out.replacingOccurrences(of: "?.", with: "?")
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return out
    }

    // MARK: - Generic response detection

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
        case .row: return "barbell row"
        case .deadlift: return "conventional deadlift"
        case .romanianDeadlift: return "Romanian deadlift"
        }
    }

    // MARK: - Legacy entry points

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

    @available(*, deprecated, message: "Use generateSetEndFeedback(formAnalysis:aggregatedMetrics:exerciseType:completion:)")
    func speakFeedback(_ feedback: String) {
        SpeechManager.shared.speak(feedback, priority: .high)
    }
}
