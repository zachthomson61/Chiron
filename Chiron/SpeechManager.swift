import Foundation
import AVFoundation
import Speech

class SpeechManager: NSObject, ObservableObject {
    static let shared = SpeechManager()
    
    // Core speech state
    private var synthesizer: AVSpeechSynthesizer?
    private var speechRecognizer: SFSpeechRecognizer?
    private var isAudioSessionActive = false
    
    // OpenAI TTS Integration
    private var audioPlayer: AVAudioPlayer?
    private var audioCache: [String: Data] = [:]
    private let audioCacheQueue = DispatchQueue(label: "speech.audioCache.queue", attributes: .concurrent)
    private var currentTask: URLSessionDataTask?
    private let openAIAPIKey: String?
    private let openAITTSURL = "https://api.openai.com/v1/audio/speech"
    private var didSchedulePrewarm = false
    
    // Common phrases for caching
    private let commonPhrases = [
        "Great job!", "Perfect form!", "Keep it up!", "Nice work!",
        "Excellent!", "Good depth", "Perfect tempo", "Well done!",
        "Keep going!", "You're doing great!", "Stay focused!",
        "Good form", "Excellent depth", "Perfect alignment",
        // Add natural coaching phrases
        "Nice work there", "Good control", "Solid effort",
        "That was better", "Keep that up", "I like that",
        "Much better", "Getting stronger", "Nice improvement"
    ]
    
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
        // Get OpenAI API key from environment or Info.plist
        self.openAIAPIKey = Bundle.main.object(forInfoDictionaryKey: "Chiron Voice Key") as? String ??
                           ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        
        super.init()
        
        // Skip voice asset queries to prevent errors (using OpenAI TTS as primary)
        print("🎤 Skipping voice asset queries - using OpenAI TTS as primary")
        
        // Setup audio session interruption handling
        setupAudioSessionInterruptionHandling()
        
        // Device/simulator info
        #if targetEnvironment(simulator)
        print("🎤 Running in simulator - voice asset errors are expected")
        #else
        print("🎤 Running on device - voice asset errors may occur but won't affect functionality")
        #endif
    }
    
    // MARK: - Public Speech APIs
    func speak(_ text: String, priority: SpeechPriority = .normal, context: SpeechContext = .feedback) {
        guard speechEnabled else {
            print("🎤 Speech disabled - would speak: \(text)")
            return
        }
        
        print("🎤 Attempting to speak: \(text) [Priority: \(priority), Context: \(context)]")
        
        queueLock.lock()
        defer { queueLock.unlock() }
        
        // Handle priority-based interruption logic
        let shouldInterrupt = shouldInterruptCurrentSpeech(newPriority: priority, newContext: context)
        if shouldInterrupt {
            print("🎤 High priority speech interrupting current speech")
            speakQueue.removeAll { $0.priority.rawValue < priority.rawValue }
            stopSpeaking()
        }
        
        if (isSpeaking || audioPlayer != nil || (synthesizer?.isSpeaking ?? false)) && !shouldInterrupt {
            print("🎤 Queuing utterance: \(text)")
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
    
    func stopSpeaking() {
        audioPlayer?.stop()
        audioPlayer = nil
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
        currentTask?.cancel()
        currentTask = nil
        isSpeaking = false
        currentSpeechContext = .none
        print("🎤 Speech stopped and cleaned up")
        if speakQueue.isEmpty && !(synthesizer?.isSpeaking ?? false) && audioPlayer == nil {
            setDuckingEnabled(false)
        }
    }
    
    func clearSpeechQueue() {
        queueLock.lock(); defer { queueLock.unlock() }
        speakQueue.removeAll()
        print("🎤 Speech queue cleared")
    }
    
    // MARK: - Internal Helpers
    private func startSpeaking(_ text: String, priority: SpeechPriority, context: SpeechContext) {
        currentSpeechContext = context
        lastSpeechTime = Date()
        prepareForSpeechIfNeeded()
        
        if !isAudioSessionActive {
            print("🎤 Reactivating audio session")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self.continueSpeaking(text, priority: priority)
            }
        } else {
            continueSpeaking(text, priority: priority)
        }
    }
    
    private func continueSpeaking(_ text: String, priority: SpeechPriority) {
        guard let apiKey = openAIAPIKey, !apiKey.isEmpty else {
            print("🎤 No OpenAI API key available, using fallback")
            fallbackToSystemVoice(text)
            return
        }
        Task { await speakWithOpenAI(text, priority: priority) }
    }
    
    private func prepareForSpeechIfNeeded() {
        if !isAudioSessionActive {
            setupAudioSession()
        }
        
        guard !didSchedulePrewarm else { return }
        didSchedulePrewarm = true
        
        guard let apiKey = openAIAPIKey, !apiKey.isEmpty else { return }
        
        Task.detached(priority: .utility) { [weak self] in
            await self?.cacheCommonPhrases()
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
    
    private func playNextFromQueueIfAvailable() {
        queueLock.lock(); defer { queueLock.unlock() }
        guard speechEnabled else { speakQueue.removeAll(); return }
        guard !speakQueue.isEmpty else { return }
        speakQueue.sort { $0.priority.rawValue > $1.priority.rawValue }
        let next = speakQueue.removeFirst()
        print("🎤 Dequeued utterance: \(next.text)")
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
        do {
            let audioSession = AVAudioSession.sharedInstance()
            if audioSession.category == .playback && audioSession.categoryOptions.contains(.mixWithOthers) {
                print("🎤 Audio session already properly configured (mixing only)")
                isAudioSessionActive = true
                return
            }
            try audioSession.setActive(false, options: [])
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                do {
                    try audioSession.setActive(true, options: [])
                    self.isAudioSessionActive = true
                    print("🎤 Audio session setup successful (mixing enabled, no duck)")
                } catch {
                    print("❌ Failed to activate audio session: \(error)")
                    self.isAudioSessionActive = false
                    self.setupAudioSessionFallback()
                }
            }
        } catch {
            print("❌ Failed to setup audio session: \(error)")
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
                    print("🎤 Audio session fallback setup successful (mixing enabled, no duck)")
                } catch {
                    print("❌ Audio session fallback also failed: \(error)")
                    self.isAudioSessionActive = false
                }
            }
        } catch {
            print("❌ Audio session fallback setup failed: \(error)")
            isAudioSessionActive = false
        }
    }
    
    private func setDuckingEnabled(_ enabled: Bool) {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            if enabled {
                try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
                if !isAudioSessionActive {
                    try audioSession.setActive(true, options: [])
                    isAudioSessionActive = true
                }
                print("🎤 Ducking ENABLED")
            } else {
                try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                print("🎤 Ducking DISABLED (mixing only)")
            }
        } catch {
            print("❌ Failed to toggle ducking: \(error)")
        }
    }
    
    private func setupAudioSessionInterruptionHandling() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioSessionInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioSessionRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }
    
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            print("🎤 Audio session interruption began")
            stopSpeaking()
        case .ended:
            print("🎤 Audio session interruption ended")
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) { setupAudioSession() }
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioSessionRouteChange(notification: Notification) {
        print("🎤 Audio session route changed")
        setupAudioSession()
    }
    
    // MARK: - OpenAI TTS
    private func speakWithOpenAI(_ text: String, priority: SpeechPriority) async {
        let cachedAudio: Data? = audioCacheQueue.sync { audioCache[text] }
        if let cachedAudio = cachedAudio {
            print("🎤 Playing cached audio for: \(text)")
            DispatchQueue.main.async { self.playAudioData(cachedAudio) }
            return
        }
        
        do {
            let audioData = try await fetchOpenAITTS(text)
            print("🎤 Received OpenAI TTS audio data: \(audioData.count) bytes")
            audioCacheQueue.async(flags: .barrier) { self.audioCache[text] = audioData }
            DispatchQueue.main.async { self.playAudioData(audioData) }
        } catch {
            print("🎤 OpenAI TTS failed: \(error), falling back to system voice")
            fallbackToSystemVoice(text)
        }
    }
    
    private func fetchOpenAITTS(_ text: String) async throws -> Data {
        guard let apiKey = openAIAPIKey, !apiKey.isEmpty else { throw SpeechError.noAPIKey }
        guard let url = URL(string: openAITTSURL) else { throw SpeechError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        let requestBody = ["model": "tts-1", "input": text, "voice": "nova"]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        print("🎤 Making OpenAI TTS request for: \(text)")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw SpeechError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("🎤 OpenAI API error: \(httpResponse.statusCode) - \(errorMessage)")
            throw SpeechError.apiError(httpResponse.statusCode, errorMessage)
        }
        return data
    }
    
    private func playAudioData(_ data: Data) {
        do {
            audioPlayer?.stop()
            setDuckingEnabled(true)
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            isSpeaking = true
            audioPlayer?.play()
            print("🎤 Playing OpenAI TTS audio")
        } catch {
            print("🎤 Failed to play audio data: \(error)")
            fallbackToSystemVoice("Audio playback failed")
        }
    }
    
    private func fallbackToSystemVoice(_ text: String) {
        print("🎤 Using system voice fallback for: \(text)")
        if synthesizer != nil { synthesizer?.stopSpeaking(at: .immediate); synthesizer = nil }
        synthesizer = AVSpeechSynthesizer()
        synthesizer?.delegate = self
        let utterance = AVSpeechUtterance(string: text)
        if let defaultVoice = AVSpeechSynthesisVoice.speechVoices().first { utterance.voice = defaultVoice } else { utterance.voice = nil }
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.1
        utterance.volume = 0.95
        utterance.preUtteranceDelay = 0.2
        utterance.postUtteranceDelay = 0.1
        setDuckingEnabled(true)
        synthesizer?.speak(utterance)
        isSpeaking = true
    }
    
    // MARK: - Higher-level Speech APIs used across the app
    func speakAnalysisResults(_ feedback: CloudAnalysisFeedback) {
        guard speechEnabled else { return }
        var speechText = "Analysis complete. "
        let scorePercentage = Int(feedback.averageFormScore * 100)
        if scorePercentage >= 85 {
            speechText += "Excellent work! You scored \(scorePercentage) percent. "
        } else if scorePercentage >= 70 {
            speechText += "Good job! Your form score was \(scorePercentage) percent. "
        } else {
            speechText += "Your form score was \(scorePercentage) percent - let's work on improving that. "
        }
        if feedback.totalReps > 1 {
            speechText += "You completed \(feedback.totalReps) solid reps. "
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
            fallback += "Nice work on those \(totalReps) reps. "
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

    // MARK: - Cache common phrases for snappier playback
    private func cacheCommonPhrases() async {
        print("🎤 Pre-caching common phrases...")
        for phrase in commonPhrases {
            do {
                let audioData = try await fetchOpenAITTS(phrase)
                audioCacheQueue.async(flags: .barrier) {
                    self.audioCache[phrase] = audioData
                }
                print("🎤 Cached phrase: \(phrase)")
            } catch {
                print("🎤 Failed to cache phrase '\(phrase)': \(error)")
            }
        }
        // Read count using the thread-safe queue to avoid concurrent access
        let cachedCount = audioCacheQueue.sync { audioCache.count }
        print("🎤 Finished caching \(cachedCount) phrases")
    }
    
    // MARK: - Minimal Speech Recognition (disabled)
    func startListening() {
        print("🎤 Speech recognition disabled to avoid voice asset errors")
    }
    
    func stopListening() {
        audioEngine?.stop()
        recognitionRequest?.endAudio()
        isListening = false
    }
    
    private func beginListening() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("Speech recognition not available")
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
            print("Audio engine failed to start: \(error)")
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
            print("Voice command: Stop")
        } else if lowercased.contains("next") || lowercased.contains("continue") {
            print("Voice command: Next")
        }
    }
    
    // MARK: - Cache Management
    func clearAudioCache() {
        print("🎤 Clearing audio cache...")
        audioCacheQueue.async(flags: .barrier) { self.audioCache.removeAll() }
    }
    
    func getCacheSize() -> Int {
        let totalBytes = audioCacheQueue.sync { audioCache.values.reduce(0) { $0 + $1.count } }
        return totalBytes
    }
    
    func getCachedPhrases() -> [String] { audioCacheQueue.sync { Array(audioCache.keys) } }
    
    // MARK: - Cleanup
    func cleanup() {
        print("🎤 Cleaning up speech system")
        stopSpeaking()
        clearSpeechQueue()
        synthesizer = nil
        audioPlayer = nil
        currentTask?.cancel(); currentTask = nil
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
            print("🎤 Audio session deactivated")
        } catch {
            print("❌ Failed to deactivate audio session: \(error)")
        }
        isAudioSessionActive = false
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
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

enum SpeechError: Error, LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case apiError(Int, String)
    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No OpenAI API key available"
        case .invalidURL: return "Invalid OpenAI API URL"
        case .invalidResponse: return "Invalid response from OpenAI API"
        case .apiError(let code, let message): return "OpenAI API error \(code): \(message)"
        }
    }
}

// MARK: - Delegates
extension SpeechManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("🎤 Speech synthesis finished: \(utterance.speechString)")
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.synthesizer = nil
            self.currentSpeechContext = .none
            if self.speakQueue.isEmpty && self.audioPlayer == nil { self.setDuckingEnabled(false) }
            self.playNextFromQueueIfAvailable()
        }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("🎤 Speech synthesis started: \(utterance.speechString)")
        DispatchQueue.main.async { self.isSpeaking = true }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("🎤 Speech synthesis cancelled: \(utterance.speechString)")
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.synthesizer = nil
            self.currentSpeechContext = .none
            if self.speakQueue.isEmpty && self.audioPlayer == nil { self.setDuckingEnabled(false) }
            self.playNextFromQueueIfAvailable()
        }
    }
}

extension SpeechManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("🎤 OpenAI TTS audio finished playing")
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.audioPlayer = nil
            self.currentSpeechContext = .none
            if self.speakQueue.isEmpty && !(self.synthesizer?.isSpeaking ?? false) { self.setDuckingEnabled(false) }
            self.playNextFromQueueIfAvailable()
        }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("🎤 OpenAI TTS audio decode error: \(error?.localizedDescription ?? "Unknown error")")
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.audioPlayer = nil
            self.currentSpeechContext = .none
            if self.speakQueue.isEmpty && !(self.synthesizer?.isSpeaking ?? false) { self.setDuckingEnabled(false) }
            self.playNextFromQueueIfAvailable()
        }
    }
}
