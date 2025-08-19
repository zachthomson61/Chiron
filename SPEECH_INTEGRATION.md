# Speech Integration Guide

This guide covers the complete speech integration for providing voice feedback to users during workouts.

## 🎤 Speech Features

### **Text-to-Speech (TTS)**
- **Analysis Results**: Speaks AI analysis results after cloud processing
- **Form Feedback**: Real-time voice feedback during exercises
- **Workout Events**: Announces set completion, rep counts, and workout status
- **Voice Commands**: Speech recognition for hands-free app control

## 🚀 Speech Integration Flow

```
Cloud Analysis → Speech Synthesis → User Alert
Real-time Feedback → Voice Announcement → Form Correction
Voice Command → Speech Recognition → App Control
```

## 📱 Implementation Details

### **SpeechManager.swift** - Core Speech Functionality

#### **Text-to-Speech Features:**
✅ **Analysis Results Speech**: Comprehensive AI analysis feedback  
✅ **Form Feedback Speech**: Real-time form corrections  
✅ **Workout Event Speech**: Set completion and rep announcements  
✅ **Priority System**: High, normal, and low priority speech  
✅ **Voice Control**: Enable/disable speech functionality  

#### **Speech Recognition Features:**
✅ **Voice Commands**: Hands-free app control  
✅ **Command Processing**: Stop, pause, next, continue  
✅ **Real-time Recognition**: Continuous voice input  
✅ **Audio Session Management**: Proper audio routing  

### **Speech Triggers:**

#### **1. Cloud Analysis Results**
```swift
// After cloud analysis completes
speechManager.speakAnalysisResults(cloudFeedback)
```
**Example Output:**
> "Analysis complete. Your overall form score is 85 percent. You completed 5 reps. Your best rep was number 3, and your worst was number 1. Overall feedback: Excellent form overall! Keep up the great work. Key recommendations: Practice box squats to build depth confidence."

#### **2. Real-time Form Feedback**
```swift
// During exercise performance
speechManager.speakFormFeedback(feedback)
```
**Example Output:**
> "Perfect depth! Good posture. Perfect tempo."

#### **3. Workout Events**
```swift
// Set completion, rep counts, etc.
speechManager.speakWorkoutEvent("Set complete", details: "5 reps with 92% form score")
```
**Example Output:**
> "Set complete. 5 reps with 92 percent form score."

#### **4. Rep Completion**
```swift
// After each rep
speechManager.speakWorkoutEvent("Good form rep 3")
```
**Example Output:**
> "Good form rep 3"

## 🎯 User Experience

### **Speech Priority System:**

#### **High Priority** (Interrupts current speech)
- Cloud analysis results
- Critical form corrections
- Important workout events

#### **Normal Priority** (Queued speech)
- Real-time form feedback
- Rep completion announcements
- General workout status

#### **Low Priority** (Background speech)
- Workout start/end events
- Non-critical notifications

### **Voice Commands:**

#### **Available Commands:**
- **"Stop"** - Stop current exercise
- **"Pause"** - Pause the workout
- **"Next"** - Continue to next set
- **"Continue"** - Resume workout

#### **Command Processing:**
```swift
private func handleSpeechInput(_ transcript: String) {
    let lowercased = transcript.lowercased()
    
    if lowercased.contains("stop") || lowercased.contains("pause") {
        // Handle stop command
    } else if lowercased.contains("next") || lowercased.contains("continue") {
        // Handle next command
    }
}
```

## 🎛️ Speech Control UI

### **SpeechControlView.swift** - Speech Settings Interface

#### **Features:**
✅ **Speech Status**: Shows current speaking/listening state  
✅ **Toggle Controls**: Enable/disable speech functionality  
✅ **Voice Commands**: Start/stop voice recognition  
✅ **Settings Display**: Shows available speech features  
✅ **Help Section**: Voice command instructions  

#### **UI Components:**
- **Speech Status Card**: Shows current speech state
- **Toggle Buttons**: Enable/disable speech features
- **Voice Command Help**: Lists available commands
- **Settings Overview**: Shows speech capabilities

### **ActiveWorkoutView Integration:**

#### **Speech Button:**
- Dynamic icon (speaker.wave.2.fill when speaking)
- Color-coded status (green when active, gray when inactive)
- Opens speech control panel

#### **Speech Indicators:**
- Visual feedback during speech
- Status indicators in workout views
- Progress indicators during analysis

## 🔧 Technical Implementation

### **Audio Session Configuration:**
```swift
private func setupAudioSession() {
    try AVAudioSession.sharedInstance().setCategory(
        .playAndRecord, 
        mode: .default, 
        options: [.defaultToSpeaker, .allowBluetooth]
    )
}
```

### **Speech Synthesis Settings:**
```swift
let utterance = AVSpeechUtterance(string: text)
utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
utterance.rate = 0.5
utterance.pitchMultiplier = 1.0
utterance.volume = 0.8
```

### **Speech Recognition Setup:**
```swift
private func beginListening() {
    // Setup audio engine
    // Configure recognition request
    // Start listening for commands
}
```

## 📱 Integration Points

### **WorkoutViewModel Integration:**

#### **Cloud Analysis Speech:**
```swift
func addCloudAnalysisFeedback(from analysisResults: [String: Any]) {
    let cloudFeedback = CloudAnalysisFeedback(from: analysisResults)
    speechManager.speakAnalysisResults(cloudFeedback)
    // ... rest of feedback processing
}
```

#### **Form Feedback Speech:**
```swift
func formFeedbackUpdated(_ feedback: FormFeedback) {
    speechManager.speakFormFeedback(feedback)
    // ... rest of feedback processing
}
```

#### **Workout Event Speech:**
```swift
func startWorkout() {
    speechManager.speakWorkoutEvent("Workout started", details: "\(selectedExercise) exercise")
    // ... rest of workout start
}
```

### **UI Integration:**

#### **ActiveWorkoutView:**
- Speech control button in bottom controls
- Dynamic speech status indicators
- Speech control sheet presentation

#### **SetCompleteView:**
- Speech status during analysis
- Visual indicators for speaking state
- Progress tracking for speech feedback

## 🔒 Permissions Required

### **Info.plist Entries:**
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app uses the microphone for voice commands during workouts.</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>This app uses speech recognition to understand voice commands for workout control.</string>
```

### **Permission Flow:**
1. **Microphone Permission**: Requested when voice commands are enabled
2. **Speech Recognition Permission**: Requested when voice recognition starts
3. **Camera Permission**: Already required for pose detection

## 🎯 Speech Content Examples

### **Analysis Results:**
> "Analysis complete. Your overall form score is 85 percent. You completed 5 reps. Your best rep was number 3, and your worst was number 1. Overall feedback: Excellent form overall! Keep up the great work. Key recommendations: Practice box squats to build depth confidence."

### **Form Feedback:**
> "Perfect depth! Good posture. Perfect tempo."

### **Workout Events:**
> "Set complete. 5 reps with 92 percent form score."
> "Good form rep 3"
> "Workout started. Squat exercise"

### **Voice Commands:**
> User: "Stop"
> App: Processes stop command

> User: "Next"
> App: Continues to next set

## 🚀 Usage Instructions

### **For Users:**

#### **1. Enable Speech:**
- Tap the speaker icon in workout view
- Toggle "Enable Speech" in speech control panel
- Grant microphone permissions when prompted

#### **2. Voice Commands:**
- Tap "Start Voice Commands" in speech control
- Say commands like "Stop", "Next", "Continue"
- Commands are processed in real-time

#### **3. Speech Feedback:**
- Analysis results are automatically spoken
- Form feedback is announced during exercises
- Workout events are announced as they occur

### **For Developers:**

#### **1. Speech Integration:**
```swift
// Add to WorkoutViewModel
private let speechManager = SpeechManager.shared

// Trigger speech for events
speechManager.speakWorkoutEvent("Event message")
```

#### **2. Custom Speech:**
```swift
// Custom speech with priority
speechManager.speak("Custom message", priority: .high)
```

#### **3. Voice Commands:**
```swift
// Start listening for commands
speechManager.startListening()

// Stop listening
speechManager.stopListening()
```

## 🎉 Benefits

### **User Experience:**
- **Hands-free Operation**: Voice commands during workouts
- **Immediate Feedback**: Real-time voice form corrections
- **Comprehensive Analysis**: Detailed spoken analysis results
- **Accessibility**: Voice feedback for all users

### **Technical Benefits:**
- **Priority System**: Important messages interrupt less critical ones
- **Audio Session Management**: Proper audio routing and mixing
- **Error Handling**: Graceful handling of speech failures
- **Performance Optimized**: Efficient speech synthesis and recognition

The speech integration provides a comprehensive voice feedback system that enhances the workout experience with hands-free operation and immediate audio feedback! 🎤 