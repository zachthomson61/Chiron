import Foundation
import AVFoundation
import Speech
import UIKit

class SpeechManager: NSObject, ObservableObject {
    static let shared = SpeechManager()
    
    // Core speech state
    private var synthesizer: AVSpeechSynthesizer?
    private var speechRecognizer: SFSpeechRecognizer?
    private var isAudioSessionActive = false
    
    // Local audio file playback
    private var audioPlayer: AVAudioPlayer?
    private var phraseManifest: [String: String] = [:]
    
    // OpenAI TTS fallback for phrases not in catalog
    private let openAIAPIKey: String?
    private let openAITTSURL = "https://api.openai.com/v1/audio/speech"
    private var audioCache: [String: Data] = [:]
    private let audioCacheQueue = DispatchQueue(label: "speech.audioCache.queue", attributes: .concurrent)
    
    // Published state
    @Published var isSpeaking = false
    @Published var isListening = false
    @Published var speechEnabled = true
    
    // Speech recognition plumbing (disabled for now)
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // Enhanced queue system with priority handling
    private var speakQueue: [(text: String, priority: SpeechPriority)] = []
    private let queueLock = NSLock() // Thread-safe queue operations
    
    // Track current speech context to prevent inappropriate interruptions
    private var currentSpeechContext: SpeechContext = .none
    private var lastSpeechTime: Date = Date()
    // Guard: when true, do not allow non-critical speech to interrupt a running sequence
    private var isSequenceActive: Bool = false
    
    private override init() {
        // Get OpenAI API key from environment or Info.plist (for fallback TTS)
        self.openAIAPIKey = Bundle.main.object(forInfoDictionaryKey: "Chiron Voice Key") as? String ??
                           ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        
        super.init()
        
        // Load phrase manifest from bundle
        loadPhraseManifest()
        
        // Setup audio session interruption handling
        setupAudioSessionInterruptionHandling()
        
        // Setup app lifecycle notifications
        setupAppLifecycleHandling()
        
    }
    
    // MARK: - Manifest Loading
    private func loadPhraseManifest() {
        // Try multiple paths in case folder structure differs
        var manifestPath: String?
        
        // Try 1: SpeechAssets subdirectory
        manifestPath = Bundle.main.path(forResource: "manifest", ofType: "json", inDirectory: "SpeechAssets")
        
        // Try 2: Direct in bundle root
        if manifestPath == nil {
            manifestPath = Bundle.main.path(forResource: "manifest", ofType: "json")
        }
        
        // Try 3: Look for manifest.json in SpeechAssets folder reference
        if manifestPath == nil, let assetsURL = Bundle.main.resourceURL?.appendingPathComponent("SpeechAssets") {
            let potentialPath = assetsURL.appendingPathComponent("manifest.json").path
            if FileManager.default.fileExists(atPath: potentialPath) {
                manifestPath = potentialPath
            }
        }
        
        guard let path = manifestPath,
              let manifestData = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: String] else {
            return
        }
        phraseManifest = manifest
    }
    
    // MARK: - Public Speech APIs
    func speak(_ text: String, priority: SpeechPriority = .normal, context: SpeechContext = .feedback) {
        guard speechEnabled else {
            return
        }
        
        
        queueLock.lock()
        defer { queueLock.unlock() }
        
        // Handle priority-based interruption logic
        let shouldInterrupt = shouldInterruptCurrentSpeech(newPriority: priority, newContext: context)
        if shouldInterrupt {
            speakQueue.removeAll { $0.priority.rawValue < priority.rawValue }
            stopSpeaking()
        }
        
        if (isSpeaking || audioPlayer != nil || (synthesizer?.isSpeaking ?? false)) && !shouldInterrupt {
            speakQueue.append((text, priority))
            return
        }
        
        startSpeaking(text, priority: priority, context: context)
    }
    
    func speakSequentially(_ messages: [String], delayBetweenMessages: TimeInterval = 1.5, priority: SpeechPriority = .normal, context: SpeechContext = .sequence) {
        guard !messages.isEmpty else { return }
        // Prevent other speech from interrupting until the sequence completes
        isSequenceActive = true
        speak(messages[0], priority: priority, context: context)
        for (index, message) in messages.dropFirst().enumerated() {
            let delay = delayBetweenMessages * Double(index + 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.speak(message, priority: priority, context: context)
            }
        }
        // Release the sequence lock a bit after the last message is scheduled
        let releaseDelay = delayBetweenMessages * Double(max(0, messages.count - 1)) + 0.8
        DispatchQueue.main.asyncAfter(deadline: .now() + releaseDelay) {
            self.isSequenceActive = false
        }
    }
    
    func speakCoachingFeedback(_ feedback: String) {
        speak(feedback, priority: .high, context: .coaching)
    }
    
    func speakEncouragement(_ encouragement: String) {
        speak(encouragement, priority: .normal, context: .encouragement)
    }
    
    func speakWorkoutInstruction(_ instruction: String) {
        speak(instruction, priority: .high, context: .instruction)
    }
    
    // MARK: - Settings helpers (used by UI)
    func toggleSpeech() {
        speechEnabled.toggle()
        if !speechEnabled {
            stopSpeaking()
            clearSpeechQueue()
        }
    }
    
    func setSpeechEnabled(_ enabled: Bool) {
        speechEnabled = enabled
        if !enabled {
            stopSpeaking()
            clearSpeechQueue()
        }
    }
    
    func stopSpeaking() {        // Safely stop audio player - defensive handling to avoid crashes during session interruptions
        if let player = audioPlayer {
            // Remove delegate first to prevent callbacks during cleanup
            player.delegate = nil
            
            // Only attempt to stop if player is actually playing
            // During interruptions, calling stop() on an invalid player can crash
            if player.isPlaying {
                do {
                    // Only try to activate session if it's not already active
                    // This avoids errors during interruption recovery
                    let audioSession = AVAudioSession.sharedInstance()
                    if !audioSession.isOtherAudioPlaying {
                        try audioSession.setActive(true, options: [])
                    }
                    player.stop()
                } catch {
                    // If we can't stop cleanly (session interrupted), just nil out
                    // This prevents crashes during rapid navigation after interruptions
                }
            }
            audioPlayer = nil
        }
        
        // Stop synthesizer if it exists - defensive cleanup
        if let synth = synthesizer {
            synth.delegate = nil
            synth.stopSpeaking(at: .immediate)
            synthesizer = nil
        }
        
        isSpeaking = false
        currentSpeechContext = .none
        
        // Disable ducking if nothing is playing
        if speakQueue.isEmpty && synthesizer == nil && audioPlayer == nil {
            setDuckingEnabled(false)
        }
    }
    
    func clearSpeechQueue() {
        queueLock.lock(); defer { queueLock.unlock() }
        speakQueue.removeAll()
    }
    
    // MARK: - Internal Helpers
    private func startSpeaking(_ text: String, priority: SpeechPriority, context: SpeechContext) {
        currentSpeechContext = context
        lastSpeechTime = Date()
        
        if !isAudioSessionActive {
            setupAudioSession()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self.continueSpeaking(text, priority: priority)
            }
        } else {
            continueSpeaking(text, priority: priority)
        }
    }
    
    /// Attempts to speak the given text using local audio files, falling back to OpenAI TTS if needed.
    ///
    /// This method first checks for an exact text match in the phrase catalog, then attempts to construct
    /// a phrase ID for dynamic phrases (like rest announcements, rep reminders, etc.). If neither approach
    /// succeeds, it falls back to OpenAI TTS (preferred) or system voice (if no API key is available).
    ///
    /// - Parameters:
    ///   - text: The text to speak
    ///   - priority: The priority level for the speech
    private func continueSpeaking(_ text: String, priority: SpeechPriority) {
        // Try to find phrase ID by exact text match first
        if let phrase = SpeechPhraseCatalog.phrase(text: text) {
            playPhrase(id: phrase.id, fallbackText: text)
            return
        }
        
        // Try to construct phrase ID for dynamic phrases (rest announcements, rep reminders, etc.)
        if let phraseId = constructPhraseId(from: text) {
            playPhrase(id: phraseId, fallbackText: text)
            return
        }
        
        // Fallback to OpenAI TTS for unknown phrases
        if let apiKey = openAIAPIKey, !apiKey.isEmpty {
            Task { await speakWithOpenAITTS(text, priority: priority) }
        } else {
            fallbackToSystemVoice(text)
        }
    }
    
    /// Constructs a phrase ID from text for dynamic phrases.
    ///
    /// This method handles various dynamic phrase patterns:
    /// - Exercise phrases ("First up, ...", "Next up, ...", exercise guides)
    /// - Rest announcements ("Rest, X Seconds", with optional variations)
    /// - Rep reminders ("When you've completed X reps...", including ranges like "6 to 8 reps")
    /// - Time reminders ("30 Seconds Left", "10 Seconds Left")
    /// - Analysis phrases (scores, rep counts, etc.)
    ///
    /// Returns the constructed phrase ID if a match is found, nil otherwise.
    private func constructPhraseId(from text: String) -> String? {
        // Check for "First up" exercise phrases
        if text.hasPrefix("First up, ") {
            if let phraseId = constructExercisePhraseId(from: text, prefix: "workout_first_up_") {
                return phraseId
            }
        }
        
        // Check for "Next up" exercise phrases
        if text.hasPrefix("Next up, ") {
            if let phraseId = constructExercisePhraseId(from: text, prefix: "workout_next_up_") {
                return phraseId
            }
        }
        
        // Check for rest announcements (case-insensitive check)
        // Handles variations like "Rest, 45 Seconds", "Rest, 45 Seconds. You deserve it!", etc.
        // NOTE: This must come BEFORE the generic exercise guide check, otherwise "Rest, 45 Seconds"
        // would be incorrectly matched as workout_exercise_rest_45_seconds
        let lowerText = text.lowercased()
        if lowerText.hasPrefix("rest, ") && lowerText.contains(" seconds") {
            if let duration = extractDuration(from: text) {
                // Check for variation suffixes and construct appropriate phrase ID
                if text.contains("You deserve it!") {
                    return "rest_you_deserve_it_\(duration)"
                } else if text.contains("Stretch out") {
                    return "rest_stretch_\(duration)"
                } else if text.contains("drink of water") {
                    return "rest_drink_water_\(duration)"
                } else if text.contains("Recover and then") {
                    return "rest_recover_next_set_\(duration)"
                } else {
                    // Basic rest announcement (e.g., "Rest, 45 Seconds")
                    return "rest_basic_\(duration)"
                }
            }
        }
        
        // Check for rep reminders
        // NOTE: This must come BEFORE the generic exercise guide check, otherwise
        // "When you've completed 6 to 8 reps, press the arrow to move on" would be
        // incorrectly matched as workout_exercise_when_you've_completed_6_to_8_reps...
        if text.hasPrefix("When you've completed ") && text.contains(" reps, press the arrow") {
            // Check for range phrases like "6 to 8 reps"
            if text.contains(" to ") {
                let pattern = #"(\d+)\s+to\s+(\d+)\s+reps"#
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   match.numberOfRanges > 2,
                   let range1 = Range(match.range(at: 1), in: text),
                   let range2 = Range(match.range(at: 2), in: text),
                   let start = Int(text[range1]),
                   let end = Int(text[range2]) {
                    return "workout_rep_reminder_\(start)_to_\(end)"
                }
            }
            // Check for single count phrases
            if let count = extractRepCount(from: text) {
                return "workout_rep_reminder_\(count)"
            }
        }
        
        // Check for exercise guide phrases (without prefix)
        if let phraseId = constructExercisePhraseId(from: text, prefix: "workout_exercise_") {
            return phraseId
        }
        
        // Check for time reminders
        if text == "30 Seconds Left" {
            return "workout_30_seconds_left"
        }
        if text == "10 Seconds Left" {
            return "workout_10_seconds_left"
        }
        
        // Check for analysis phrases
        if text.hasPrefix("Excellent work! You scored ") {
            if let score = extractScore(from: text) {
                return "analysis_excellent_work_\(score)"
            }
        }
        if text.hasPrefix("Good job! Your form score was ") {
            if let score = extractScore(from: text) {
                return "analysis_good_job_\(score)"
            }
        }
        if text.contains("percent - let's work on improving") {
            if let score = extractScore(from: text) {
                return "analysis_work_on_improving_\(score)"
            }
        }
        if text.hasPrefix("You completed ") && text.contains(" solid reps") {
            if let count = extractRepCount(from: text) {
                return "analysis_completed_solid_reps_\(count)"
            }
        }
        if text.hasPrefix("Nice work on those ") && text.contains(" reps") {
            if let count = extractRepCount(from: text) {
                return "analysis_nice_work_reps_\(count)"
            }
        }
        
        return nil
    }
    
    /// Construct exercise phrase ID from text
    private func constructExercisePhraseId(from text: String, prefix: String) -> String? {
        // Remove prefix if present
        var remaining = text
        if remaining.hasPrefix("First up, ") {
            remaining = String(remaining.dropFirst("First up, ".count))
        } else if remaining.hasPrefix("Next up, ") {
            remaining = String(remaining.dropFirst("Next up, ".count))
        }
        
        // Split by comma to get exercise name and rep/time
        let parts = remaining.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { return nil }
        
        let exerciseName = parts[0]
        let repTime = parts[1]
        
        // Sanitize for ID
        let sanitizedName = exerciseName.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
        
        let sanitizedRepTime = repTime.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
        
        return "\(prefix)\(sanitizedName)_\(sanitizedRepTime)"
    }
    
    /// Extracts duration from rest announcement text.
    ///
    /// Handles case-insensitive matching for patterns like:
    /// - "Rest, 45 Seconds"
    /// - "rest, 45 seconds"
    /// - "Rest, 45 seconds"
    ///
    /// - Parameter text: The rest announcement text
    /// - Returns: The duration in seconds, or nil if not found
    private func extractDuration(from text: String) -> Int? {
        // Case-insensitive pattern to match both "Seconds" and "seconds"
        let pattern = #"(?i)Rest, (\d+) Seconds"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: text) {
            return Int(text[range])
        }
        return nil
    }
    
    private func extractRepCount(from text: String) -> Int? {
        let pattern = #"(\d+) rep"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: text) {
            return Int(text[range])
        }
        return nil
    }
    
    private func extractScore(from text: String) -> Int? {
        let pattern = #"(\d+) percent"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           match.numberOfRanges > 1,
           let range = Range(match.range(at: 1), in: text) {
            return Int(text[range])
        }
        return nil
    }
    
    /// Play audio file for a phrase ID
    ///
    /// Quickly checks manifest and file existence, then falls back to OpenAI TTS if file not found.
    /// Uses async file operations to avoid blocking the main thread.
    private func playPhrase(id: String, fallbackText: String) {        // Quick check: Get filename from manifest (in-memory lookup, very fast)
        guard let filename = phraseManifest[id] else {
            // Use OpenAI TTS instead of system voice for better quality
            if let apiKey = openAIAPIKey, !apiKey.isEmpty {
                Task { await speakWithOpenAITTS(fallbackText, priority: .normal) }
            } else {
                fallbackToSystemVoice(fallbackText)
            }
            return
        }
        
        // Quick file existence check - try all paths synchronously (fast, in-memory)
        let baseName = filename.replacingOccurrences(of: ".mp3", with: "")
        var audioPath: String?
        
        // Try 1: SpeechAssets subdirectory (most common)
        audioPath = Bundle.main.path(forResource: baseName, ofType: "mp3", inDirectory: "SpeechAssets")
        
        // Try 2: Root bundle
        if audioPath == nil {
            audioPath = Bundle.main.path(forResource: baseName, ofType: "mp3")
        }
        
        // Try 3: Direct file path check
        if audioPath == nil, let assetsURL = Bundle.main.resourceURL?.appendingPathComponent("SpeechAssets") {
            let potentialPath = assetsURL.appendingPathComponent(filename).path
            if FileManager.default.fileExists(atPath: potentialPath) {
                audioPath = potentialPath
            }
        }
        
        // If file path found, try to load it (should be fast for small audio files)
        if let path = audioPath {
            // Try to load file on background queue with timeout fallback
            let fallbackTextCopy = fallbackText
            let loadCompleted = NSLock()
            var hasCompleted = false
            
            DispatchQueue.global(qos: .userInitiated).async {
                let data = try? Data(contentsOf: URL(fileURLWithPath: path))
                
                loadCompleted.lock()
                let shouldProceed = !hasCompleted
                hasCompleted = true
                loadCompleted.unlock()
                
                if !shouldProceed {
                    // Timeout already triggered, don't proceed
                    return
                }
                
                if let audioData = data {
                    DispatchQueue.main.async {
                        self.playAudioData(audioData)
                    }
                } else {
                    // File read failed - fallback to system voice (don't use OpenAI TTS to avoid network errors)
                    DispatchQueue.main.async {
                        self.fallbackToSystemVoice(fallbackTextCopy)
                    }
                }
            }
            
            // Set timeout: if file doesn't load within 500ms, fallback to system voice
            // Increased from 100ms to 500ms to avoid premature fallback and network errors
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                
                loadCompleted.lock()
                let shouldFallback = !hasCompleted
                hasCompleted = true
                loadCompleted.unlock()
                
                if shouldFallback {
                    // Use system voice instead of OpenAI TTS to avoid network errors when offline
                    self.fallbackToSystemVoice(fallbackTextCopy)
                }
            }
        } else {
            // File not found - use OpenAI TTS immediately (better than system voice)
            if let apiKey = openAIAPIKey, !apiKey.isEmpty {
                Task { await speakWithOpenAITTS(fallbackText, priority: .normal) }
            } else {
                fallbackToSystemVoice(fallbackText)
            }
        }
    }
    
    private func shouldInterruptCurrentSpeech(newPriority: SpeechPriority, newContext: SpeechContext) -> Bool {
        // If a sequence is in progress, only CRITICAL can interrupt
        if isSequenceActive || currentSpeechContext == .sequence {
            return newPriority == .critical
        }
        if newPriority == .critical { return true }
        if newPriority == .high && (currentSpeechContext == .feedback || currentSpeechContext == .encouragement) { return true }
        if currentSpeechContext == .coaching && newContext == .feedback { return false }
        let speechAge = Date().timeIntervalSince(lastSpeechTime)
        if speechAge > 3.0 { return true }
        return false
    }
    
    private func playNextFromQueueIfAvailable() {        queueLock.lock(); defer { queueLock.unlock() }
        guard speechEnabled else { speakQueue.removeAll(); return }
        guard !speakQueue.isEmpty else { return }
        speakQueue.sort { $0.priority.rawValue > $1.priority.rawValue }
        let next = speakQueue.removeFirst()
        let delay: TimeInterval = 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if !self.isAudioSessionActive {
                self.setupAudioSession()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.continueSpeaking(next.text, priority: next.priority)
                }
            } else {
                self.continueSpeaking(next.text, priority: next.priority)
            }
        }
    }
    
    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        // Don't setup if already active and properly configured
        let audioSession = AVAudioSession.sharedInstance()
        if isAudioSessionActive && audioSession.category == .playback && audioSession.categoryOptions.contains(.mixWithOthers) {
            return
        }
        
        do {
            // Set category first - only change if needed to avoid interrupting video playback
            // Don't deactivate the session first as that would interrupt video playback
            let needsCategoryUpdate = audioSession.category != .playback || !audioSession.categoryOptions.contains(.mixWithOthers)
            if needsCategoryUpdate {
                try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
            
            // Activate without deactivating first - this preserves video playback with .mixWithOthers
            // The session should already be active from AudioSessionManager at app startup
            if !isAudioSessionActive {
                try audioSession.setActive(true, options: [])
                isAudioSessionActive = true
            } else {
            }
        } catch {
            isAudioSessionActive = false
            setupAudioSessionFallback()
        }
    }
    
    private func setupAudioSessionFallback() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                do {
                    try audioSession.setActive(true, options: [])
                    self.isAudioSessionActive = true
                } catch {
                    self.isAudioSessionActive = false
                }
            }
        } catch {
            isAudioSessionActive = false
        }
    }
    
    private func setDuckingEnabled(_ enabled: Bool) {
        let audioSession = AVAudioSession.sharedInstance()
        let currentHasDucking = audioSession.categoryOptions.contains(.duckOthers)
        
        // Only change category if ducking state actually needs to change
        // This prevents interrupting video playback unnecessarily
        guard enabled != currentHasDucking else {
            // Already in desired state, no change needed - preserve video playback
            return
        }
        
        do {
            let desiredOptions: AVAudioSession.CategoryOptions = enabled ? [.mixWithOthers, .duckOthers] : [.mixWithOthers]
            // Set category with desired options - preserves video playback due to .mixWithOthers
            try audioSession.setCategory(.playback, mode: .default, options: desiredOptions)
            
            if enabled && !isAudioSessionActive {
                try audioSession.setActive(true, options: [])
                isAudioSessionActive = true
            }
            
        } catch {
        }
    }
    
    private func setupAudioSessionInterruptionHandling() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioSessionInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioSessionRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    private func setupAppLifecycleHandling() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    @objc private func handleAppWillEnterForeground() {
        // Stop any current playback
        stopSpeaking()
        // Reset audio session state
        isAudioSessionActive = false
    }
    
    @objc private func handleAppDidBecomeActive() {
        // Reinitialize audio session when app becomes active
        isAudioSessionActive = false
        setupAudioSession()
    }
    
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            // Immediately nil out player and synthesizer to prevent access during interruption
            // Don't call stop() as the session is already interrupted
            audioPlayer?.delegate = nil
            audioPlayer = nil
            synthesizer?.delegate = nil
            synthesizer = nil
            isSpeaking = false
            isAudioSessionActive = false
            
            // Clear queue to prevent queued items from playing after interruption
            clearSpeechQueue()
        case .ended:
            // Ensure player and synthesizer are nil before resetting session
            audioPlayer?.delegate = nil
            audioPlayer = nil
            synthesizer?.delegate = nil
            synthesizer = nil
            isSpeaking = false
            isAudioSessionActive = false
            
            // Wait a brief moment before reinitializing to ensure interruption is fully complete
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    // Delay reinitialization slightly to ensure session is ready
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.setupAudioSession()
                    }
                }
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioSessionRouteChange(notification: Notification) {
        setupAudioSession()
    }
    
    // MARK: - Audio Playback
    private func playAudioData(_ data: Data) {
        // Ensure audio session is active before playing
        guard isAudioSessionActive else {
            setupAudioSession()
            // Wait a bit for session to activate, then try again
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.playAudioData(data)
            }
            return
        }
        
        // Defensively clean up any existing player first
        audioPlayer?.delegate = nil
        audioPlayer?.stop()
        audioPlayer = nil
        
        do {
            // Verify audio session is still active before creating player
            let audioSession = AVAudioSession.sharedInstance()
            guard audioSession.isOtherAudioPlaying == false || audioSession.categoryOptions.contains(.mixWithOthers) else {
                setupAudioSession()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.playAudioData(data)
                }
                return
            }
            
            // Set ducking before creating new player
            setDuckingEnabled(true)
            
            // Create new player
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            
            // Prepare to play (this validates the audio data)
            guard player.prepareToPlay() else {
                player.delegate = nil
                fallbackToSystemVoice("Audio preparation failed")
                return
            }
            
            // Store player and play
            audioPlayer = player
            isSpeaking = true
            
            // Play with error handling
            guard player.play() else {
                audioPlayer?.delegate = nil
                audioPlayer = nil
                isSpeaking = false
                fallbackToSystemVoice("Audio playback failed")
                return
            }
            
        } catch {
            audioPlayer?.delegate = nil
            audioPlayer = nil
            isSpeaking = false
            fallbackToSystemVoice("Audio playback failed")
        }
    }
    
    // MARK: - OpenAI TTS Fallback
    private func speakWithOpenAITTS(_ text: String, priority: SpeechPriority) async {        // Check cache first
        let cachedAudio: Data? = audioCacheQueue.sync { audioCache[text] }
        if let cachedAudio = cachedAudio {
            DispatchQueue.main.async { self.playAudioData(cachedAudio) }
            return
        }
        
        do {
            let startTime = Date()
            let audioData = try await fetchOpenAITTS(text)
            let duration = Date().timeIntervalSince(startTime)
            audioCacheQueue.async(flags: .barrier) { self.audioCache[text] = audioData }
            DispatchQueue.main.async { self.playAudioData(audioData) }
        } catch {
            fallbackToSystemVoice(text)
        }
    }
    
    private func fetchOpenAITTS(_ text: String) async throws -> Data {
        guard let apiKey = openAIAPIKey, !apiKey.isEmpty else {
            throw NSError(domain: "SpeechManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No OpenAI API key available"])
        }
        guard let url = URL(string: openAITTSURL) else {
            throw NSError(domain: "SpeechManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI API URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        let requestBody = ["model": "tts-1", "input": text, "voice": "nova"]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "SpeechManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid response from OpenAI API"])
        }
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "SpeechManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "OpenAI API error: \(errorMessage)"])
        }
        return data
    }
    
    private func fallbackToSystemVoice(_ text: String) {
        
        // Ensure audio session is active before using synthesizer
        guard isAudioSessionActive else {
            setupAudioSession()
            // Retry after session is set up
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.fallbackToSystemVoice(text)
            }
            return
        }
        
        // Clean up any existing synthesizer
        if let synth = synthesizer {
            synth.delegate = nil
            synth.stopSpeaking(at: .immediate)
            synthesizer = nil
        }
        
        // Wait a brief moment to ensure cleanup is complete
        DispatchQueue.main.async {
            // Verify session is still active before creating new synthesizer
            guard self.isAudioSessionActive else {
                return
            }
            
            // Create new synthesizer
            let synth = AVSpeechSynthesizer()
            synth.delegate = self
            self.synthesizer = synth
            
            // Configure utterance
            let utterance = AVSpeechUtterance(string: text)
            if let defaultVoice = AVSpeechSynthesisVoice.speechVoices().first {
                utterance.voice = defaultVoice
            } else {
                utterance.voice = nil
            }
            utterance.rate = 0.5
            utterance.pitchMultiplier = 1.1
            utterance.volume = 0.95
            utterance.preUtteranceDelay = 0.2
            utterance.postUtteranceDelay = 0.1
            
            // Enable ducking and start speaking
            self.setDuckingEnabled(true)
            synth.speak(utterance)
            self.isSpeaking = true
        }
    }
    
    // MARK: - Higher-level Speech APIs used across the app
    func speakAnalysisResults(_ feedback: CloudAnalysisFeedback) {
        guard speechEnabled else { return }
        var speechText = "Analysis complete. "
        let scorePercentage = Int(feedback.averageFormScore * 100)
        // Round to nearest 5 for pre-generated variations
        let roundedScore = (scorePercentage / 5) * 5
        if scorePercentage >= 85 {
            speechText += "Excellent work! You scored \(roundedScore) percent. "
        } else if scorePercentage >= 70 {
            speechText += "Good job! Your form score was \(roundedScore) percent. "
        } else {
            speechText += "Your form score was \(roundedScore) percent - let's work on improving that. "
        }
        if feedback.totalReps > 1 {
            let clampedReps = min(feedback.totalReps, 20) // Clamp to pre-generated range
            speechText += "You completed \(clampedReps) solid reps. "
        } else if feedback.totalReps == 1 {
            speechText += "You completed one rep - let's build on that. "
        }
        if !feedback.recommendations.isEmpty {
            let topRecommendation = feedback.recommendations.first!
            speechText += "Key focus for next time: \(topRecommendation). "
        }
        speakCoachingFeedback(speechText)
    }

    func speakOpenAIFeedback(_ analysisResults: [String: Any]) {
        guard speechEnabled else { return }
        if let openAIFeedback = analysisResults["openai_feedback"] as? String {
            let cleaned = openAIFeedback
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            speakCoachingFeedback(cleaned)
            return
        }
        if let feedback = analysisResults["feedback"] as? String {
            let cleaned = feedback
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            speakCoachingFeedback(cleaned)
            return
        }
        var fallback = ""
        if let totalReps = analysisResults["total_reps"] as? Int, totalReps > 0 {
            let clampedReps = min(totalReps, 20) // Clamp to pre-generated range
            fallback += "Nice work on those \(clampedReps) reps. "
        }
        if let issues = analysisResults["issues"] as? [String], let first = issues.first {
            fallback += "Let's focus on improving \(first.lowercased()) next time. "
        } else {
            fallback += "Keep up the good work. "
        }
        speakCoachingFeedback(fallback)
    }

    func speakRepAnalysis(_ repAnalysis: RepAnalysis) {
        guard speechEnabled else { return }
        let scorePercentage = Int(repAnalysis.overallScore * 100)
        var speechText = scorePercentage >= 85 ? "Great rep! " : (scorePercentage >= 70 ? "Good rep. " : "Rep \(repAnalysis.repNumber): ")
        if repAnalysis.depthScore < 0.6 {
            speechText += "Try going deeper next time. "
        } else if repAnalysis.postureScore < 0.6 {
            speechText += "Keep that chest up. "
        } else if let first = repAnalysis.issues.first {
            speechText += "Watch your \(first.lowercased()). "
        } else {
            speechText += "Keep that form! "
        }
        speak(speechText, priority: .normal, context: .feedback)
    }

    func speakFormFeedback(_ feedback: FormFeedback) {
        guard speechEnabled else { return }
        if !feedback.message.isEmpty {
            speak(feedback.message, priority: .normal, context: .feedback)
        }
    }

    func speakWorkoutEvent(_ event: String, details: String? = nil) {
        guard speechEnabled else { return }
        var text = event
        if let details = details { text += ". \(details)" }
        speak(text, priority: .low, context: .event)
    }

    
    // MARK: - Minimal Speech Recognition (disabled)
    func startListening() {
    }
    
    func stopListening() {
        audioEngine?.stop()
        recognitionRequest?.endAudio()
        isListening = false
    }
    
    private func beginListening() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            return
        }
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch {
        }
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let result = result {
                let transcript = result.bestTranscription.formattedString
                self?.handleSpeechInput(transcript)
            }
            if error != nil { self?.stopListening() }
        }
    }
    
    private func handleSpeechInput(_ transcript: String) {
        let lowercased = transcript.lowercased()
        if lowercased.contains("stop") || lowercased.contains("pause") {
        } else if lowercased.contains("next") || lowercased.contains("continue") {
        }
    }
    
    // MARK: - Phrase Management
    func getLoadedPhraseCount() -> Int {
        return phraseManifest.count
    }
    
    func getLoadedPhrases() -> [String] {
        return Array(phraseManifest.keys)
    }
    
    // MARK: - Cleanup
    func cleanup() {
        stopSpeaking()
        clearSpeechQueue()
        synthesizer = nil
        audioPlayer = nil
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
        }
        isAudioSessionActive = false
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        cleanup()
    }
}

// MARK: - Priority, Context, Errors
enum SpeechPriority: Int, Comparable {
    case low = 1
    case normal = 2
    case high = 3
    case critical = 4
    static func < (lhs: SpeechPriority, rhs: SpeechPriority) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum SpeechContext {
    case none
    case coaching
    case feedback
    case encouragement
    case instruction
    case event
    case sequence
}


// MARK: - Delegates
extension SpeechManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            // Only process if this is still the current synthesizer (avoid race conditions)
            guard self.synthesizer === synthesizer else { return }
            self.isSpeaking = false
            self.synthesizer?.delegate = nil
            self.synthesizer = nil
            self.currentSpeechContext = .none
            if self.speakQueue.isEmpty && self.audioPlayer == nil { 
                self.setDuckingEnabled(false) 
            }
            self.playNextFromQueueIfAvailable()
        }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { 
            // Only update if this is still the current synthesizer
            guard self.synthesizer === synthesizer else { return }
            self.isSpeaking = true 
        }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            // Only process if this is still the current synthesizer (avoid race conditions)
            guard self.synthesizer === synthesizer else { return }
            self.isSpeaking = false
            self.synthesizer?.delegate = nil
            self.synthesizer = nil
            self.currentSpeechContext = .none
            if self.speakQueue.isEmpty && self.audioPlayer == nil { 
                self.setDuckingEnabled(false) 
            }
            self.playNextFromQueueIfAvailable()
        }
    }
}

extension SpeechManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            // Only process if this is still the current player (avoid race conditions)
            guard self.audioPlayer === player else { return }
            self.isSpeaking = false
            self.audioPlayer?.delegate = nil
            self.audioPlayer = nil
            self.currentSpeechContext = .none
            if self.speakQueue.isEmpty && !(self.synthesizer?.isSpeaking ?? false) { 
                self.setDuckingEnabled(false) 
            }
            self.playNextFromQueueIfAvailable()
        }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            // Only process if this is still the current player (avoid race conditions)
            guard self.audioPlayer === player else { return }
            self.isSpeaking = false
            self.audioPlayer?.delegate = nil
            self.audioPlayer = nil
            self.currentSpeechContext = .none
            if self.speakQueue.isEmpty && !(self.synthesizer?.isSpeaking ?? false) { 
                self.setDuckingEnabled(false) 
            }
            self.playNextFromQueueIfAvailable()
        }
    }
}
