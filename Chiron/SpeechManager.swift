import Foundation
import AVFoundation
import Speech

class SpeechManager: NSObject, ObservableObject {
    static let shared = SpeechManager()
    
    private var synthesizer: AVSpeechSynthesizer?
    private var speechRecognizer: SFSpeechRecognizer?
    private var isAudioSessionActive = false
    
    // OpenAI TTS Integration
    private var audioPlayer: AVAudioPlayer?
    private var audioCache: [String: Data] = [:]
    private var currentTask: URLSessionDataTask?
    private let openAIAPIKey: String?
    private let openAITTSURL = "https://api.openai.com/v1/audio/speech"
    
    // Common phrases for caching
    private let commonPhrases = [
        "Great job!", "Perfect form!", "Keep it up!", "Nice work!", 
        "Excellent!", "Good depth", "Perfect tempo", "Well done!",
        "Keep going!", "You're doing great!", "Stay focused!",
        "Good form", "Excellent depth", "Perfect alignment"
    ]
    
    @Published var isSpeaking = false
    @Published var isListening = false
    @Published var speechEnabled = true
    
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private override init() {
        // Get OpenAI API key from environment or Info.plist
        self.openAIAPIKey = Bundle.main.object(forInfoDictionaryKey: "Chiron Voice Key") as? String ?? 
                           ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        
        super.init()
        
        // Setup audio session for speech synthesis
        setupAudioSession()
        
        // Skip voice asset queries to prevent errors (using OpenAI TTS as primary)
        print("🎤 Skipping voice asset queries - using OpenAI TTS as primary")
        
        // Pre-cache common phrases
        Task {
            await cacheCommonPhrases()
        }
        
        // Setup audio session interruption handling
        setupAudioSessionInterruptionHandling()
        
        // Suppress voice asset errors (common in iOS development)
        #if targetEnvironment(simulator)
        print("🎤 Running in simulator - voice asset errors are expected")
        #else
        print("🎤 Running on device - voice asset errors may occur but won't affect functionality")
        #endif
    }
    
    // MARK: - Text to Speech
    func speak(_ text: String, priority: SpeechPriority = .normal) {
        guard speechEnabled else {
            print("🎤 Speech disabled - would speak: \(text)")
            return
        }
        
        print("🎤 Attempting to speak: \(text)")
        
        // Stop any current speech
        stopSpeaking()
        
        // Ensure audio session is active
        if !isAudioSessionActive {
            print("🎤 Reactivating audio session")
            setupAudioSession()
            
            // Add a small delay to allow audio session to setup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.continueSpeaking(text, priority: priority)
            }
        } else {
            continueSpeaking(text, priority: priority)
        }
    }
    
    private func continueSpeaking(_ text: String, priority: SpeechPriority) {
        // Check if we have OpenAI API key
        guard let apiKey = openAIAPIKey, !apiKey.isEmpty else {
            print("🎤 No OpenAI API key available, using fallback")
            fallbackToSystemVoice(text)
            return
        }
        
        // Try OpenAI TTS first, with fallback to system voice
        Task {
            await speakWithOpenAI(text, priority: priority)
        }
    }
    
    func stopSpeaking() {
        // Stop OpenAI TTS audio
        audioPlayer?.stop()
        audioPlayer = nil
        
        // Stop system voice
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
        
        // Cancel any ongoing requests
        currentTask?.cancel()
        currentTask = nil
        
        isSpeaking = false
        print("🎤 Speech stopped and cleaned up")
    }
    
    // MARK: - Feedback Speech
    func speakAnalysisResults(_ feedback: CloudAnalysisFeedback) {
        guard speechEnabled else { return }
        
        var speechText = "Analysis complete. "
        
        // Overall score
        let scorePercentage = Int(feedback.averageFormScore * 100)
        speechText += "Your overall form score is \(scorePercentage) percent. "
        
        // Rep count
        speechText += "You completed \(feedback.totalReps) reps. "
        
        // Best and worst reps
        if feedback.bestRep > 0 && feedback.worstRep > 0 {
            speechText += "Your best rep was number \(feedback.bestRep), and your worst was number \(feedback.worstRep). "
        }
        
        // Overall feedback
        if !feedback.overallFeedback.isEmpty {
            speechText += "Overall feedback: \(feedback.overallFeedback.joined(separator: ". ")). "
        }
        
        // Key recommendations
        if !feedback.recommendations.isEmpty {
            let keyRecommendations = Array(feedback.recommendations.prefix(2))
            speechText += "Key recommendations: \(keyRecommendations.joined(separator: ". ")). "
        }
        
        speak(speechText, priority: .high)
    }
    
    func speakOpenAIFeedback(_ analysisResults: [String: Any]) {
        guard speechEnabled else {
            print("🎤 Speech disabled, not speaking")
            return
        }
        
        print("🎤 speakOpenAIFeedback called with results: \(analysisResults)")
        
        var speechText = "AI Coach Analysis. "
        
        // Extract OpenAI feedback if available (try both old and new field names)
        if let openAIFeedback = analysisResults["openai_feedback"] as? String {
            print("🎤 Found openai_feedback: \(openAIFeedback)")
            let cleanedFeedback = openAIFeedback
                .replacingOccurrences(of: "\n", with: ". ")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            speechText += cleanedFeedback
        } else if let feedback = analysisResults["feedback"] as? String {
            print("🎤 Found feedback: \(feedback)")
            // New MediaPipe analysis format
            let cleanedFeedback = feedback
                .replacingOccurrences(of: "\n", with: ". ")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            speechText += cleanedFeedback
        } else {
            print("🎤 No feedback found, using fallback")
            // Fallback to basic analysis data
            if let totalReps = analysisResults["total_reps"] as? Int {
                speechText += "You completed \(totalReps) reps. "
            }
            
            if let averageScore = analysisResults["average_form_score"] as? Double {
                let scorePercentage = Int(averageScore * 100)
                speechText += "Your average form score was \(scorePercentage) percent. "
            }
            
            if let issues = analysisResults["issues"] as? [String], !issues.isEmpty {
                speechText += "Areas for improvement: \(issues.joined(separator: ". ")). "
            }
            
            if let recommendations = analysisResults["recommendations"] as? [String], !recommendations.isEmpty {
                let keyRecommendations = Array(recommendations.prefix(2))
                speechText += "Key recommendations: \(keyRecommendations.joined(separator: ". ")). "
            }
        }
        
        print("🎤 Final speech text: \(speechText)")
        speak(speechText, priority: .high)
    }
    
    func speakRepAnalysis(_ repAnalysis: RepAnalysis) {
        guard speechEnabled else { return }
        
        let scorePercentage = Int(repAnalysis.overallScore * 100)
        var speechText = "Rep \(repAnalysis.repNumber): \(scorePercentage) percent. "
        
        // Depth feedback
        if repAnalysis.depthScore < 0.6 {
            speechText += "Depth needs improvement. "
        } else {
            speechText += "Good depth. "
        }
        
        // Posture feedback
        if repAnalysis.postureScore < 0.6 {
            speechText += "Posture needs work. "
        } else {
            speechText += "Good posture. "
        }
        
        // Issues
        if !repAnalysis.issues.isEmpty {
            speechText += "Issues: \(repAnalysis.issues.joined(separator: ". ")). "
        }
        
        speak(speechText, priority: .normal)
    }
    
    func speakFormFeedback(_ feedback: FormFeedback) {
        guard speechEnabled else { return }
        
        var speechText = ""
        
        // Depth status
        switch feedback.depthStatus {
        case .perfect:
            speechText += "Perfect depth! "
        case .good:
            speechText += "Good depth. "
        case .watch:
            speechText += "Go deeper. "
        case .poor:
            speechText += "Depth needs work. "
        }
        
        // Posture status
        switch feedback.postureStatus {
        case .perfect:
            speechText += "Excellent posture. "
        case .good:
            speechText += "Good posture. "
        case .watch:
            speechText += "Watch your posture. "
        case .poor:
            speechText += "Posture needs improvement. "
        }
        
        // Tempo status
        switch feedback.tempoStatus {
        case .perfect:
            speechText += "Perfect tempo. "
        case .good:
            speechText += "Good tempo. "
        case .watch:
            speechText += "Slow down. "
        case .poor:
            speechText += "Tempo needs work. "
        }
        
        if !speechText.isEmpty {
            speak(speechText, priority: .normal)
        }
    }
    
    func speakWorkoutEvent(_ event: String, details: String? = nil) {
        guard speechEnabled else { return }
        
        var speechText = event
        if let details = details {
            speechText += ". \(details)"
        }
        
        speak(speechText, priority: .low)
    }
    
    // MARK: - Speech Recognition
    func startListening() {
        // Speech recognition disabled to avoid voice asset errors
        print("🎤 Speech recognition disabled to avoid voice asset errors")
        return
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
            
            if error != nil {
                self?.stopListening()
            }
        }
    }
    
    private func handleSpeechInput(_ transcript: String) {
        // Handle voice commands
        let lowercased = transcript.lowercased()
        
        if lowercased.contains("stop") || lowercased.contains("pause") {
            // Handle stop command
            print("Voice command: Stop")
        } else if lowercased.contains("next") || lowercased.contains("continue") {
            // Handle next command
            print("Voice command: Next")
        }
    }
    
    // MARK: - Audio Session Setup
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Check if audio session is already active and properly configured
            if audioSession.category == .playback && audioSession.isOtherAudioPlaying == false {
                print("🎤 Audio session already properly configured")
                isAudioSessionActive = true
                return
            }
            
            // Deactivate first to ensure clean state
            try audioSession.setActive(false, options: [])
            
            // Set category with minimal options to avoid conflicts
            try audioSession.setCategory(.playback, mode: .default, options: [])
            
            // Add a longer delay before activating to ensure clean state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                do {
                    try audioSession.setActive(true, options: [])
                    self.isAudioSessionActive = true
                    print("🎤 Audio session setup successful")
                } catch {
                    print("❌ Failed to activate audio session: \(error)")
                    self.isAudioSessionActive = false
                    // Try a simpler setup as fallback
                    self.setupAudioSessionFallback()
                }
            }
        } catch {
            print("❌ Failed to setup audio session: \(error)")
            isAudioSessionActive = false
            // Try a simpler setup as fallback
            setupAudioSessionFallback()
        }
    }
    
    private func setupAudioSessionFallback() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Try the simplest possible setup
            try audioSession.setCategory(.playback, mode: .default, options: [])
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                do {
                    try audioSession.setActive(true, options: [])
                    self.isAudioSessionActive = true
                    print("🎤 Audio session fallback setup successful")
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
    
    // MARK: - Audio Session Interruption Handling
    private func setupAudioSessionInterruptionHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            print("🎤 Audio session interruption began")
            stopSpeaking()
        case .ended:
            print("🎤 Audio session interruption ended")
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    setupAudioSession()
                }
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioSessionRouteChange(notification: Notification) {
        print("🎤 Audio session route changed")
        // Re-setup audio session when route changes
        setupAudioSession()
    }
    

    
    // MARK: - Settings
    func toggleSpeech() {
        speechEnabled.toggle()
        if !speechEnabled {
            stopSpeaking()
            stopListening()
        }
    }
    
    func setSpeechEnabled(_ enabled: Bool) {
        speechEnabled = enabled
        if !enabled {
            stopSpeaking()
            stopListening()
        }
    }
    

    
    // MARK: - Test Speech
    func testSpeech() {
        print("🎤 Testing speech synthesis...")
        speak("Hello, this is a test of the speech synthesis system.", priority: .high)
    }
    
    // MARK: - OpenAI TTS
    private func speakWithOpenAI(_ text: String, priority: SpeechPriority) async {
        // Check cache first
        if let cachedAudio = audioCache[text] {
            print("🎤 Playing cached audio for: \(text)")
            DispatchQueue.main.async {
                self.playAudioData(cachedAudio)
            }
            return
        }
        
        do {
            let audioData = try await fetchOpenAITTS(text)
            print("🎤 Received OpenAI TTS audio data: \(audioData.count) bytes")
            
            // Cache the audio data
            audioCache[text] = audioData
            
            // Play the audio
            DispatchQueue.main.async {
                self.playAudioData(audioData)
            }
        } catch {
            print("🎤 OpenAI TTS failed: \(error), falling back to system voice")
            fallbackToSystemVoice(text)
        }
    }
    
    private func fetchOpenAITTS(_ text: String) async throws -> Data {
        guard let apiKey = openAIAPIKey, !apiKey.isEmpty else {
            throw SpeechError.noAPIKey
        }
        
        guard let url = URL(string: openAITTSURL) else {
            throw SpeechError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        
        let requestBody = [
            "model": "tts-1",
            "input": text,
            "voice": "nova"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        print("🎤 Making OpenAI TTS request for: \(text)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("🎤 OpenAI API error: \(httpResponse.statusCode) - \(errorMessage)")
            throw SpeechError.apiError(httpResponse.statusCode, errorMessage)
        }
        
        return data
    }
    
    private func playAudioData(_ data: Data) {
        do {
            // Stop any current audio
            audioPlayer?.stop()
            
            // Create audio player with the received data
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            
            // Update speaking state
            isSpeaking = true
            
            // Play the audio
            audioPlayer?.play()
            print("🎤 Playing OpenAI TTS audio")
        } catch {
            print("🎤 Failed to play audio data: \(error)")
            fallbackToSystemVoice("Audio playback failed")
        }
    }
    
    private func fallbackToSystemVoice(_ text: String) {
        print("🎤 Using system voice fallback for: \(text)")
        
        // Clean up any existing synthesizer
        if synthesizer != nil {
            synthesizer?.stopSpeaking(at: .immediate)
            synthesizer = nil
        }
        
        // Create new synthesizer
        synthesizer = AVSpeechSynthesizer()
        synthesizer?.delegate = self
        
        let utterance = AVSpeechUtterance(string: text)
        
        // Use system default voice without triggering asset queries
        // This approach avoids the voice asset errors
        if let defaultVoice = AVSpeechSynthesisVoice.speechVoices().first {
            utterance.voice = defaultVoice
        } else {
            // If no voices available, use nil (system will use default)
            utterance.voice = nil
        }
        
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.1
        utterance.volume = 0.95
        utterance.preUtteranceDelay = 0.2
        utterance.postUtteranceDelay = 0.1
        
        synthesizer?.speak(utterance)
        isSpeaking = true
    }
    
    private func cacheCommonPhrases() async {
        print("🎤 Pre-caching common phrases...")
        
        for phrase in commonPhrases {
            do {
                let audioData = try await fetchOpenAITTS(phrase)
                audioCache[phrase] = audioData
                print("🎤 Cached phrase: \(phrase)")
            } catch {
                print("🎤 Failed to cache phrase '\(phrase)': \(error)")
            }
        }
        
        print("🎤 Finished caching \(audioCache.count) phrases")
    }
    

    
    // MARK: - Cache Management
    func clearAudioCache() {
        print("🎤 Clearing audio cache...")
        audioCache.removeAll()
    }
    
    func getCacheSize() -> Int {
        let totalBytes = audioCache.values.reduce(0) { $0 + $1.count }
        return totalBytes
    }
    
    func getCachedPhrases() -> [String] {
        return Array(audioCache.keys)
    }
    
    // MARK: - Cleanup
    func cleanup() {
        print("🎤 Cleaning up speech system")
        
        // Stop all speech and audio
        stopSpeaking()
        synthesizer = nil
        audioPlayer = nil
        currentTask?.cancel()
        currentTask = nil
        
        // Deactivate audio session with proper options
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
        // Remove notification observers
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: nil)
        
        // Clean up audio session
        cleanup()
    }
}

// MARK: - Speech Priority
enum SpeechPriority {
    case low
    case normal
    case high
}

// MARK: - Speech Errors
enum SpeechError: Error, LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case apiError(Int, String)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No OpenAI API key available"
        case .invalidURL:
            return "Invalid OpenAI API URL"
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .apiError(let code, let message):
            return "OpenAI API error \(code): \(message)"
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension SpeechManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("🎤 Speech synthesis finished: \(utterance.speechString)")
        DispatchQueue.main.async {
            self.isSpeaking = false
            // Clean up synthesizer after speech finishes
            self.synthesizer = nil
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("🎤 Speech synthesis started: \(utterance.speechString)")
        DispatchQueue.main.async {
            self.isSpeaking = true
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("🎤 Speech synthesis cancelled: \(utterance.speechString)")
        DispatchQueue.main.async {
            self.isSpeaking = false
            // Clean up synthesizer after speech is cancelled
            self.synthesizer = nil
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        print("🎤 Speech synthesis will speak range: \(characterRange) of: \(utterance.speechString)")
    }
}

// MARK: - AVAudioPlayerDelegate
extension SpeechManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("🎤 OpenAI TTS audio finished playing")
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.audioPlayer = nil
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("🎤 OpenAI TTS audio decode error: \(error?.localizedDescription ?? "Unknown error")")
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.audioPlayer = nil
        }
    }
} 
