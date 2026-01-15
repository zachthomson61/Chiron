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
    ]
    
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
