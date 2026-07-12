//
//  SpeechPhrases.swift
//  Chiron
//
//  Catalog of all speech phrases used in the app.
//  Each phrase has a unique ID that maps to a pre-generated audio file.
//

import Foundation

/// Category for organizing speech phrases
enum SpeechPhraseCategory: String {
    case encouragement
    case feedback
    case instruction
    case workoutFlow
    case cameraSetup
    case exerciseSetup
    case analysis
    case repFeedback
}

/// Represents a speech phrase with its ID, text, and category
struct SpeechPhrase {
    let id: String
    let text: String
    let category: SpeechPhraseCategory
}

/// Catalog of all speech phrases in the app
struct SpeechPhraseCatalog {
    /// All phrases organized by category
    static let phrases: [SpeechPhrase] = [
        // MARK: - Encouragement
        SpeechPhrase(id: "encouragement_great_job", text: "Great job!", category: .encouragement),
        SpeechPhrase(id: "encouragement_perfect_form", text: "Perfect form!", category: .encouragement),
        SpeechPhrase(id: "encouragement_keep_it_up", text: "Keep it up!", category: .encouragement),
        SpeechPhrase(id: "encouragement_nice_work", text: "Nice work!", category: .encouragement),
        SpeechPhrase(id: "encouragement_excellent", text: "Excellent!", category: .encouragement),
        SpeechPhrase(id: "encouragement_good_depth", text: "Good depth", category: .encouragement),
        SpeechPhrase(id: "encouragement_perfect_tempo", text: "Perfect tempo", category: .encouragement),
        SpeechPhrase(id: "encouragement_well_done", text: "Well done!", category: .encouragement),
        SpeechPhrase(id: "encouragement_keep_going", text: "Keep going!", category: .encouragement),
        SpeechPhrase(id: "encouragement_doing_great", text: "You're doing great!", category: .encouragement),
        SpeechPhrase(id: "encouragement_stay_focused", text: "Stay focused!", category: .encouragement),
        SpeechPhrase(id: "encouragement_good_form", text: "Good form", category: .encouragement),
        SpeechPhrase(id: "encouragement_excellent_depth", text: "Excellent depth", category: .encouragement),
        SpeechPhrase(id: "encouragement_perfect_alignment", text: "Perfect alignment", category: .encouragement),
        SpeechPhrase(id: "encouragement_nice_work_there", text: "Nice work there", category: .encouragement),
        SpeechPhrase(id: "encouragement_good_control", text: "Good control", category: .encouragement),
        SpeechPhrase(id: "encouragement_solid_effort", text: "Solid effort", category: .encouragement),
        SpeechPhrase(id: "encouragement_that_was_better", text: "That was better", category: .encouragement),
        SpeechPhrase(id: "encouragement_keep_that_up", text: "Keep that up", category: .encouragement),
        SpeechPhrase(id: "encouragement_i_like_that", text: "I like that", category: .encouragement),
        SpeechPhrase(id: "encouragement_much_better", text: "Much better", category: .encouragement),
        SpeechPhrase(id: "encouragement_getting_stronger", text: "Getting stronger", category: .encouragement),
        SpeechPhrase(id: "encouragement_nice_improvement", text: "Nice improvement", category: .encouragement),
        
        // MARK: - Rep Feedback
        SpeechPhrase(id: "rep_feedback_great_rep", text: "Great rep! ", category: .repFeedback),
        SpeechPhrase(id: "rep_feedback_good_rep", text: "Good rep. ", category: .repFeedback),
        SpeechPhrase(id: "rep_feedback_try_deeper", text: "Try going deeper next time. ", category: .repFeedback),
        SpeechPhrase(id: "rep_feedback_keep_chest_up", text: "Keep that chest up. ", category: .repFeedback),
        SpeechPhrase(id: "rep_feedback_keep_form", text: "Keep that form! ", category: .repFeedback),
        
        // MARK: - Analysis Feedback
        SpeechPhrase(id: "analysis_complete", text: "Analysis complete. ", category: .analysis),
        SpeechPhrase(id: "analysis_excellent_work", text: "Excellent work! You scored {score} percent. ", category: .analysis),
        SpeechPhrase(id: "analysis_good_job", text: "Good job! Your form score was {score} percent. ", category: .analysis),
        SpeechPhrase(id: "analysis_work_on_improving", text: "Your form score was {score} percent - let's work on improving that. ", category: .analysis),
        SpeechPhrase(id: "analysis_completed_solid_reps", text: "You completed {count} solid reps. ", category: .analysis),
        SpeechPhrase(id: "analysis_one_rep", text: "You completed one rep - let's build on that. ", category: .analysis),
        SpeechPhrase(id: "analysis_key_focus", text: "Key focus for next time: {recommendation}. ", category: .analysis),
        SpeechPhrase(id: "analysis_nice_work_reps", text: "Nice work on those {count} reps. ", category: .analysis),
        SpeechPhrase(id: "analysis_focus_improving", text: "Let's focus on improving {issue} next time. ", category: .analysis),
        SpeechPhrase(id: "analysis_keep_up_good_work", text: "Keep up the good work. ", category: .analysis),
        
        // MARK: - Exercise Setup Cues
        SpeechPhrase(id: "exercise_setup_bodyweight_squat", text: "Go slow and controlled on the way down. Keep your chest tall and core tight", category: .exerciseSetup),
        SpeechPhrase(id: "exercise_setup_barbell_back_squat", text: "Position the barbell across your upper traps. Keep the bar path vertical over mid foot. Brace your core before each descent", category: .exerciseSetup),
        SpeechPhrase(id: "exercise_setup_barbell_row", text: "Position yourself with feet hip-width apart. Hinge at the hips and keep your spine neutral", category: .exerciseSetup),
        SpeechPhrase(id: "exercise_setup_deadlift", text: "Position the bar over mid foot. Keep your chest up and spine neutral throughout the movement", category: .exerciseSetup),
        SpeechPhrase(id: "exercise_setup_romanian_deadlift", text: "Stand tall with feet hip-width. Keep your knees slightly bent and maintain a neutral spine", category: .exerciseSetup),
        SpeechPhrase(id: "exercise_setup_barbell_bench_press", text: "Position yourself on the bench with feet flat on the floor. Keep your shoulder blades retracted", category: .exerciseSetup),
        SpeechPhrase(id: "exercise_start_workout", text: "Let's get it!", category: .exerciseSetup),
        
        // MARK: - Camera Setup
        SpeechPhrase(id: "camera_setup_prompt", text: "Let's setup your camera for live coaching! Select the view you would like to use.", category: .cameraSetup),
        SpeechPhrase(id: "camera_setup_rack", text: "For a mount setup, mount your phone high up on one of the front rack posts, angled down toward the middle of the bar. Center the frame on the bar and your hands, not your face. Keep your full arm length and bar path visible. Try to avoid cropping at lockout or when you touch your chest.", category: .cameraSetup),
        SpeechPhrase(id: "camera_setup_floor", text: "For a floor setup, place your phone on the floor, 4 to 6 feet from the bench, angled slightly upwards. Center it on the bar. Make sure to keep your hands, elbows, and bar path in frame.", category: .cameraSetup),
        SpeechPhrase(id: "camera_setup_tripod", text: "For a tripod setup, place the tripod 2 to 3 feet in front of the bench, centered on the bar. Ensure that the tripod is at the same height as the racked bar or slightly higher. Angle the camera slightly down towards your grip. Ensure your hands, elbows, and bar path are in view.", category: .cameraSetup),
        
        // MARK: - Workout Flow
        SpeechPhrase(id: "workout_first_up", text: "First up, {exercise}, {repsTime}", category: .workoutFlow),
        SpeechPhrase(id: "workout_next_up", text: "Next up, {exercise}, {repsTime}", category: .workoutFlow),
        SpeechPhrase(id: "workout_exercise_guide", text: "{exercise}, {repsTime}", category: .workoutFlow),
        SpeechPhrase(id: "workout_rep_reminder", text: "When you've completed {count} reps, press the arrow to move on", category: .workoutFlow),
        SpeechPhrase(id: "workout_30_seconds_left", text: "30 Seconds Left", category: .workoutFlow),
        SpeechPhrase(id: "workout_10_seconds_left", text: "10 Seconds Left", category: .workoutFlow),
        
        // MARK: - Rest Announcements (Dynamic - will be pre-generated)
        // Basic rest announcements
        SpeechPhrase(id: "rest_basic", text: "Rest, {duration} Seconds", category: .workoutFlow),
        SpeechPhrase(id: "rest_you_deserve_it", text: "Rest, {duration} Seconds. You deserve it!", category: .workoutFlow),
        SpeechPhrase(id: "rest_stretch", text: "Rest, {duration} Seconds. Stretch out a bit.", category: .workoutFlow),
        SpeechPhrase(id: "rest_drink_water", text: "Rest, {duration} Seconds. Take a drink of water if you're thirsty.", category: .workoutFlow),
        SpeechPhrase(id: "rest_recover_next_set", text: "Rest, {duration} Seconds. Recover and then let's get this next set!", category: .workoutFlow),

        // MARK: - Begin-Set Affirmations (Track tab)
        SpeechPhrase(id: "affirmation_lets_go", text: "Let's go!", category: .encouragement),
        SpeechPhrase(id: "affirmation_youve_got_this", text: "You've got this!", category: .encouragement),
        SpeechPhrase(id: "affirmation_time_to_work", text: "Time to work!", category: .encouragement),
        SpeechPhrase(id: "affirmation_lets_crush_it", text: "Let's crush it!", category: .encouragement),
        SpeechPhrase(id: "affirmation_make_it_count", text: "Make it count!", category: .encouragement),

        // MARK: - Goal-Based Intent Cues (Track tab, first set per exercise)
        // Squat
        SpeechPhrase(id: "intent_squat_build_muscle", text: "Sit deep and pause at the bottom — that stretch is where your muscle grows.", category: .instruction),
        SpeechPhrase(id: "intent_squat_get_stronger", text: "Brace hard, control the descent, drive through the floor.", category: .instruction),
        SpeechPhrase(id: "intent_squat_athletic_performance", text: "Slow down, then explode up — this is your power builder.", category: .instruction),
        SpeechPhrase(id: "intent_squat_rehab", text: "Move slow through the full range, no bouncing at the bottom.", category: .instruction),
        SpeechPhrase(id: "intent_squat_lose_fat_toned", text: "Steady pace, tight form, feel every rep.", category: .instruction),
        SpeechPhrase(id: "intent_squat_endurance", text: "Find a clean, repeatable rhythm for the whole set.", category: .instruction),
        SpeechPhrase(id: "intent_squat_health_longevity", text: "Full range of motion, controlled all the way.", category: .instruction),
        // Bench Press
        SpeechPhrase(id: "intent_bench_build_muscle", text: "Slow on the way down, pause at your chest — that's where the chest grows.", category: .instruction),
        SpeechPhrase(id: "intent_bench_get_stronger", text: "Lock in tight, control the bar down, press with intent.", category: .instruction),
        SpeechPhrase(id: "intent_bench_athletic_performance", text: "Control down, press up fast and powerful.", category: .instruction),
        SpeechPhrase(id: "intent_bench_rehab", text: "Smooth and controlled, no bouncing off your chest.", category: .instruction),
        SpeechPhrase(id: "intent_bench_lose_fat_toned", text: "Steady tempo, tight form, squeeze the chest on every press.", category: .instruction),
        SpeechPhrase(id: "intent_bench_endurance", text: "Clean reps at a consistent tempo.", category: .instruction),
        SpeechPhrase(id: "intent_bench_health_longevity", text: "Full range of motion, move the bar with control.", category: .instruction),
        // Deadlift
        SpeechPhrase(id: "intent_deadlift_build_muscle", text: "Control the descent and feel your back and legs loading up.", category: .instruction),
        SpeechPhrase(id: "intent_deadlift_get_stronger", text: "Push the floor away — this is your whole-body strength builder.", category: .instruction),
        SpeechPhrase(id: "intent_deadlift_athletic_performance", text: "Explosive off the floor — hip drive is raw power.", category: .instruction),
        SpeechPhrase(id: "intent_deadlift_rehab", text: "Set your back, move slow, keep the bar close to your body.", category: .instruction),
        SpeechPhrase(id: "intent_deadlift_lose_fat_toned", text: "Tight form, controlled pulls, whole-body engagement.", category: .instruction),
        SpeechPhrase(id: "intent_deadlift_endurance", text: "Repeatable clean reps — never sacrifice form.", category: .instruction),
        SpeechPhrase(id: "intent_deadlift_health_longevity", text: "Neutral spine, smooth from the floor to lockout.", category: .instruction),
        // Romanian Deadlift
        SpeechPhrase(id: "intent_rdl_build_muscle", text: "Hinge deep and feel that hamstring stretch — let it load the muscle.", category: .instruction),
        SpeechPhrase(id: "intent_rdl_get_stronger", text: "Control the hinge, load the hamstrings, drive your hips forward.", category: .instruction),
        SpeechPhrase(id: "intent_rdl_athletic_performance", text: "Load the hamstrings deep, fire your hips on the way up.", category: .instruction),
        SpeechPhrase(id: "intent_rdl_rehab", text: "Soft knees, flat back, hinge only as far as control allows.", category: .instruction),
        SpeechPhrase(id: "intent_rdl_lose_fat_toned", text: "Tight core, clean hinge, steady pace.", category: .instruction),
        SpeechPhrase(id: "intent_rdl_endurance", text: "Smooth hinge, consistent rhythm, don't rush it.", category: .instruction),
        SpeechPhrase(id: "intent_rdl_health_longevity", text: "Controlled hinge to keep your spine safe.", category: .instruction),
        // Barbell Row
        SpeechPhrase(id: "intent_row_build_muscle", text: "Pull with your back, squeeze at the top — feel the muscle working.", category: .instruction),
        SpeechPhrase(id: "intent_row_get_stronger", text: "Solid hinge, drive the elbows back, own every rep.", category: .instruction),
        SpeechPhrase(id: "intent_row_athletic_performance", text: "Pull hard, stay tight, transfer power through your back.", category: .instruction),
        SpeechPhrase(id: "intent_row_rehab", text: "Flat back, no jerking, control both directions.", category: .instruction),
        SpeechPhrase(id: "intent_row_lose_fat_toned", text: "Controlled pulls, tight form, no momentum.", category: .instruction),
        SpeechPhrase(id: "intent_row_endurance", text: "Clean reps, steady pace, keep form through fatigue.", category: .instruction),
        SpeechPhrase(id: "intent_row_health_longevity", text: "Tall chest, flat back, move with control.", category: .instruction),

        // MARK: - Coaching Prompts
        SpeechPhrase(id: "coaching_prompt_which_exercise", text: "Which exercise would you like coaching on?", category: .instruction),

        // MARK: - Framing Reminder (Track tab)
        SpeechPhrase(id: "framing_reminder", text: "Prop your phone about four to six feet away. Ensure it's either in front of you or at about a 45 degree angle. Face it towards you, and step back until you see a green skeleton filter. When you're ready for your set, enter the weight you're lifting and press begin set.", category: .instruction),

        // MARK: - PR Celebration (Dynamic)
        SpeechPhrase(id: "pr_celebration_bodyweight", text: "Personal record — {reps} reps. Huge work.", category: .encouragement),
        SpeechPhrase(id: "pr_celebration_weighted", text: "Personal record — {descriptor}. Huge work.", category: .encouragement),

        // MARK: - Set Start (Dynamic)
        SpeechPhrase(id: "workout_starting_set", text: "Starting set {number}", category: .workoutFlow),

        // MARK: - Coaching Fallbacks
        // No-reps fallbacks (close-grip bench press)
        SpeechPhrase(id: "fallback_no_reps_get_ready_next", text: "Let's get ready for the next set!", category: .feedback),
        SpeechPhrase(id: "fallback_no_reps_take_your_time", text: "Take your time and focus on the next set.", category: .feedback),
        SpeechPhrase(id: "fallback_no_reps_rest_up", text: "Rest up and let's get after it!", category: .feedback),
        SpeechPhrase(id: "fallback_no_reps_get_ready", text: "Let's get ready!", category: .feedback),
        // Missing-analysis fallbacks
        SpeechPhrase(id: "fallback_good_effort_focus_form", text: "Good effort on that set. Keep focusing on your form.", category: .feedback),
        SpeechPhrase(id: "fallback_nice_control_more_depth", text: "Nice control there, but let's aim for a little more depth next set.", category: .feedback),
        // High-score rest fallbacks
        SpeechPhrase(id: "fallback_high_great_set_form_control", text: "Great set! Excellent form and control.", category: .feedback),
        SpeechPhrase(id: "fallback_high_nice_work_solid_set", text: "Nice work! That was a solid set.", category: .feedback),
        SpeechPhrase(id: "fallback_high_well_done_great_execution", text: "Well done! Great execution on that set.", category: .feedback),
        SpeechPhrase(id: "fallback_high_great_set", text: "Great set!", category: .feedback),
        // Low-score rest fallbacks
        SpeechPhrase(id: "fallback_low_elbows_tucked", text: "Nice effort there. Focus on keeping those elbows tucked.", category: .feedback),
        SpeechPhrase(id: "fallback_low_tighten_form", text: "Good work. Let's tighten up the form next set.", category: .feedback),
        SpeechPhrase(id: "fallback_low_good_effort", text: "Good effort!", category: .feedback),
        // Insufficient-data fallback (OpenAI coaching)
        SpeechPhrase(id: "fallback_insufficient_data", text: "Good set. When you're ready, start your next set.", category: .feedback),
    ]
    
    /// Deterministic-fallback `capitalizedBest` values produced by
    /// `OpenAICoachingManager.buildFallbackFeedback`. Each entry pairs the
    /// exact rendered string with a short stable key used to build phrase
    /// IDs. Keep this list aligned with the bestThing producers in
    /// `SetEndFeedbackPlanner.positivePhrase` / `CoachingContract.detectPositiveNote`.
    static let fallbackBestThings: [(text: String, key: String)] = [
        ("Nice effort there", "nice_effort"),
        ("Good depth on that set", "good_depth"),
        ("Chest stayed nice and tall", "chest_tall"),
        ("Knees tracked well over your toes", "knees_over_toes"),
        ("Solid lockout at the top", "solid_lockout_top"),
        ("Tempo stayed controlled", "tempo_controlled"),
        ("Back stayed nice and flat", "back_flat"),
        ("Solid hip position throughout", "solid_hip_position"),
        ("Elbows stayed tight to your sides", "elbows_tight"),
        ("Really clean rows", "clean_rows"),
        ("Back stayed flat the whole way up", "back_flat_pull"),
        ("Hips and shoulders moved together nicely", "hips_shoulders_together"),
        ("Strong lockout position", "strong_lockout"),
        ("Bar stayed tight to your body", "bar_tight_body"),
        ("Really clean pulls", "clean_pulls"),
        ("Smooth hip hinge with a flat back", "smooth_hinge"),
        ("Knees stayed nice and soft without bending", "soft_knees"),
        ("Good depth on that hinge", "good_depth_hinge"),
        ("Bar stayed right against your legs", "bar_against_legs"),
        ("Textbook Romanian deadlifts", "textbook_rdl"),
        ("Controlled tempo", "controlled_tempo"),
    ]

    /// Deterministic-fallback cues from `CoachingContract.definitions`, in
    /// the lowercased form that `buildFallbackFeedback` substitutes into
    /// `"{Best}, now {cue}"`. Keyed by `IssueCode.rawValue` so the resulting
    /// phrase ID stays stable across renames of the display strings.
    static let fallbackCues: [(lowercasedText: String, issueCode: String)] = [
        ("sit deeper until hips reach knee level", "insufficient_depth"),
        ("keep your chest tall and proud", "forward_lean"),
        ("push your knees out over your toes", "knee_valgus"),
        ("keep your knees tracking straight ahead", "knee_varus"),
        ("bring your grip in closer to your ribs", "grip_too_wide"),
        ("tuck those elbows to your sides", "elbows_flaring"),
        ("lock out fully at the top and touch your chest at the bottom", "incomplete_rom"),
        ("take more time lowering the bar", "eccentric_too_fast"),
        ("press up a little faster", "concentric_too_slow"),
        ("hold the stretch at the bottom for a full second", "insufficient_stretch_pause"),
        ("keep your back flat and close to parallel with the ground — don't stand up between reps", "row_momentum_drive"),
        ("brace your core and keep your spine flat — don't let your back round", "row_rounded_back"),
        ("point your toes and knees straight ahead", "row_knee_internal_rotation"),
        ("pull your elbows back toward your hips, not out to the sides", "row_elbow_flare"),
        ("brace hard and lock in a flat back from setup to lockout", "deadlift_rounded_back"),
        ("push through your legs first so hips and shoulders rise together", "deadlift_hip_shoot_up"),
        ("stand tall at the top without leaning back", "deadlift_hyperextension"),
        ("keep the bar tight to your body the whole way up", "deadlift_bar_drift"),
        ("brace your core and keep your spine flat all the way down", "rdl_rounded_back"),
        ("keep your knees at a soft fixed bend — push your hips back instead", "rdl_excessive_knee_bend"),
        ("hinge deeper until you feel a stretch in your hamstrings", "rdl_shallow_hinge"),
        ("keep the bar sliding along your thighs the whole way down", "rdl_bar_drift"),
    ]

    /// Spoken closers for a clean set. `buildFallbackFeedback` rotates through
    /// these so a clean set isn't always spoken as "that set was dialed in".
    /// Each entry is a full spoken clause — the builder prepends " — ". Keep
    /// these mutually distinct (no entry a trailing substring of another) so
    /// the reverse-matcher in `SpeechManager.constructFallbackPhraseId` can tell
    /// them apart. `dialed_in` stays first (see `cleanFallbackPhraseId`).
    ///
    /// IMPORTANT: mirror any change here in `scripts/generate_speech_assets.js`
    /// (its `cleanClosers`) or the baked audio and the matcher will drift.
    static let cleanClosers: [(text: String, key: String)] = [
        ("that set was dialed in", "dialed_in"),
        ("that one was perfect", "perfect"),
        ("you were locked in there", "locked_in"),
        ("clean work all the way", "clean_work"),
        ("that was textbook", "textbook"),
        ("really strong set", "strong_set"),
    ]

    /// The pre-baked phrase id for a clean fallback line (best × closer).
    /// `dialed_in` keeps the legacy un-suffixed id so audio baked before closers
    /// existed still resolves; every other closer appends `_<closerKey>`. This
    /// single rule is shared by the baking loop AND
    /// `SpeechManager.constructFallbackPhraseId`, so the writer and reader can
    /// never disagree. The JS bake script mirrors it.
    static func cleanFallbackPhraseId(bestKey: String, closerKey: String) -> String {
        closerKey == "dialed_in"
            ? "fallback_clean_\(bestKey)"
            : "fallback_clean_\(bestKey)_\(closerKey)"
    }

    /// Get phrase by ID
    static func phrase(id: String) -> SpeechPhrase? {
        return phrases.first { $0.id == id }
    }
    
    /// Get phrase by text (exact match)
    static func phrase(text: String) -> SpeechPhrase? {
        return phrases.first { $0.text == text }
    }
    
    /// Get all phrases in a category
    static func phrases(in category: SpeechPhraseCategory) -> [SpeechPhrase] {
        return phrases.filter { $0.category == category }
    }
    
    /// Generate phrase ID for dynamic phrases
    /// Example: rest_basic with duration 30 -> "rest_basic_30"
    static func dynamicPhraseId(baseId: String, values: [String: String]) -> String {
        var id = baseId
        for (_, value) in values.sorted(by: { $0.key < $1.key }) {
            let sanitized = value.lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: ".", with: "")
            id += "_\(sanitized)"
        }
        return id
    }
    
    /// Generate all exercise-specific phrases from workout library
    /// Returns array of (phraseId, text) tuples
    static func generateExercisePhrases() -> [(id: String, text: String)] {
        var phrases: [(id: String, text: String)] = []
        
        // Common rep/time formats
        let repTimeFormats = [
            "30 seconds",
            "45 seconds",
            "90 seconds",
            "21 seconds",
            "6-8 reps",
            "10-12 reps",
            "6 to 8 reps",
            "10 to 12 reps"
        ]
        
        // Exercise names from Python Wrangler workout (with and without side notes)
        let exercises = [
            ("Cross-Body Arm Swings", nil),
            ("Cross-Body Arm Swings", "Right Side"),
            ("Cross-Body Arm Swings", "Left Side"),
            ("Arm Circles", nil),
            ("Thread the Needle", "Right Side"),
            ("Thread the Needle", "Left Side"),
            ("Overhead Tricep Stretch", "Right Side"),
            ("Overhead Tricep Stretch", "Left Side"),
            ("Standing Wall Bicep Stretch", "Right Side"),
            ("Standing Wall Bicep Stretch", "Left Side"),
            ("Close-Grip Bench Press", nil),
            ("Alternating DB Curls", nil),
            ("Incline DB Curl", nil),
            ("Rope Tricep Pushdown", nil),
            ("EZ-Bar Drag Curl", nil),
            ("Overhead Rope Extension", nil),
            ("Barbell Bicep Curl", nil),
            ("Bench Dip", nil),
            ("Hammer Curl Hold", nil),
            ("Cross-body Tricep Stretch", "Right Side"),
            ("Cross-body Tricep Stretch", "Left Side"),
        ]
        
        // Generate "First up" phrases
        for (exerciseName, side) in exercises {
            let fullName = side != nil ? "\(exerciseName) - \(side!)" : exerciseName
            for repTime in repTimeFormats {
                let phraseId = "workout_first_up_\(sanitizeForId(fullName))_\(sanitizeForId(repTime))"
                let phraseText = "First up, \(fullName), \(repTime)"
                phrases.append((id: phraseId, text: phraseText))
            }
        }
        
        // Generate "Next up" phrases
        for (exerciseName, side) in exercises {
            let fullName = side != nil ? "\(exerciseName) - \(side!)" : exerciseName
            for repTime in repTimeFormats {
                let phraseId = "workout_next_up_\(sanitizeForId(fullName))_\(sanitizeForId(repTime))"
                let phraseText = "Next up, \(fullName), \(repTime)"
                phrases.append((id: phraseId, text: phraseText))
            }
        }
        
        // Generate exercise guide phrases (without "First up" or "Next up")
        for (exerciseName, side) in exercises {
            let fullName = side != nil ? "\(exerciseName) - \(side!)" : exerciseName
            for repTime in repTimeFormats {
                let phraseId = "workout_exercise_\(sanitizeForId(fullName))_\(sanitizeForId(repTime))"
                let phraseText = "\(fullName), \(repTime)"
                phrases.append((id: phraseId, text: phraseText))
            }
        }
        
        return phrases
    }
    
    /// Sanitize text for use in phrase ID
    private static func sanitizeForId(_ text: String) -> String {
        return text.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
    }
    
    /// Generate all pre-generated variations for dynamic phrases
    /// Returns array of (phraseId, text) tuples
    static func generateDynamicVariations() -> [(id: String, text: String)] {
        var variations: [(id: String, text: String)] = []
        
        // Add exercise-specific phrases
        variations.append(contentsOf: generateExercisePhrases())
        
        // Rest announcements: 5-300 seconds in 5-second increments
        // This ensures exact matches for common durations like 15, 21, 25, 30, 35, 45, 55, etc.
        let restDurations = stride(from: 5, through: 300, by: 5)
        for duration in restDurations {
            variations.append((
                id: "rest_basic_\(duration)",
                text: "Rest, \(duration) Seconds"
            ))
            variations.append((
                id: "rest_you_deserve_it_\(duration)",
                text: "Rest, \(duration) Seconds. You deserve it!"
            ))
            variations.append((
                id: "rest_stretch_\(duration)",
                text: "Rest, \(duration) Seconds. Stretch out a bit."
            ))
            variations.append((
                id: "rest_drink_water_\(duration)",
                text: "Rest, \(duration) Seconds. Take a drink of water if you're thirsty."
            ))
            variations.append((
                id: "rest_recover_next_set_\(duration)",
                text: "Rest, \(duration) Seconds. Recover and then let's get this next set!"
            ))
        }
        
        // Rep reminders: 1-20 reps
        for count in 1...20 {
            variations.append((
                id: "workout_rep_reminder_\(count)",
                text: "When you've completed \(count) reps, press the arrow to move on"
            ))
        }
        
        // Analysis score variations: 0-100 in increments of 5
        for score in stride(from: 0, through: 100, by: 5) {
            variations.append((
                id: "analysis_excellent_work_\(score)",
                text: "Excellent work! You scored \(score) percent. "
            ))
            variations.append((
                id: "analysis_good_job_\(score)",
                text: "Good job! Your form score was \(score) percent. "
            ))
            variations.append((
                id: "analysis_work_on_improving_\(score)",
                text: "Your form score was \(score) percent - let's work on improving that. "
            ))
        }
        
        // Analysis rep count variations: 1-20 reps
        for count in 1...20 {
            variations.append((
                id: "analysis_completed_solid_reps_\(count)",
                text: "You completed \(count) solid reps. "
            ))
            variations.append((
                id: "analysis_nice_work_reps_\(count)",
                text: "Nice work on those \(count) reps. "
            ))
        }

        // Set start variations: sets 1-20
        for setNumber in 1...20 {
            variations.append((
                id: "workout_starting_set_\(setNumber)",
                text: "Starting set \(setNumber)"
            ))
        }

        // PR celebration (bodyweight): 1-50 reps
        for reps in 1...50 {
            variations.append((
                id: "pr_celebration_bodyweight_\(reps)",
                text: "Personal record — \(reps) reps. Huge work."
            ))
        }

        // Deterministic LLM-fail fallback combinations. Mirrors the
        // `base` strings built in `OpenAICoachingManager.buildFallbackFeedback`
        // for the no-safety-prefix path. Without these, every fallback
        // line goes to OpenAI TTS at runtime and falls through to the
        // robotic AVSpeechSynthesizer when the network is degraded.
        for best in fallbackBestThings {
            for closer in cleanClosers {
                variations.append((
                    id: cleanFallbackPhraseId(bestKey: best.key, closerKey: closer.key),
                    text: "\(best.text) — \(closer.text)"
                ))
            }
            variations.append((
                id: "fallback_corrective_no_cue_\(best.key)",
                text: "\(best.text) — keep that same form"
            ))
            for cue in fallbackCues {
                variations.append((
                    id: "fallback_corrective_\(best.key)_\(cue.issueCode)",
                    text: "\(best.text), now \(cue.lowercasedText)"
                ))
            }
        }

        return variations
    }
    
    /// Export all phrases (including dynamic variations) as JSON for the build script
    static func exportForBuildScript() -> [[String: String]] {
        var allPhrases: [[String: String]] = []
        
        // Add static phrases
        for phrase in phrases {
            allPhrases.append([
                "id": phrase.id,
                "text": phrase.text,
                "category": phrase.category.rawValue
            ])
        }
        
        // Add dynamic variations
        for variation in generateDynamicVariations() {
            allPhrases.append([
                "id": variation.id,
                "text": variation.text,
                "category": "dynamic"
            ])
        }
        
        return allPhrases
    }
}
