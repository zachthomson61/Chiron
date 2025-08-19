import SwiftUI

struct SpeechControlView: View {
    @ObservedObject var speechManager = SpeechManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Voice Feedback")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Manage speech settings and voice commands")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .padding(.top)
                
                // Speech Status
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: speechManager.isSpeaking ? "speaker.wave.2.fill" : "speaker.slash")
                            .foregroundColor(speechManager.isSpeaking ? .green : .gray)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(speechManager.isSpeaking ? "Speaking" : "Silent")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(speechManager.isSpeaking ? "Voice feedback active" : "Voice feedback disabled")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemGray6).opacity(0.3))
                    .cornerRadius(12)
                }
                
                // Speech Controls
                VStack(spacing: 16) {
                    // Toggle Speech
                    Button(action: {
                        speechManager.toggleSpeech()
                    }) {
                        HStack {
                            Image(systemName: speechManager.speechEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                                .foregroundColor(speechManager.speechEnabled ? .green : .red)
                            Text(speechManager.speechEnabled ? "Disable Speech" : "Enable Speech")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color(.systemGray6).opacity(0.3))
                        .cornerRadius(12)
                    }
                    
                    // Stop Speaking
                    if speechManager.isSpeaking {
                        Button(action: {
                            speechManager.stopSpeaking()
                        }) {
                            HStack {
                                Image(systemName: "stop.fill")
                                    .foregroundColor(.red)
                                Text("Stop Speaking")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(Color(.systemGray6).opacity(0.3))
                            .cornerRadius(12)
                        }
                    }
                    
                    // Voice Commands
                    Button(action: {
                        if speechManager.isListening {
                            speechManager.stopListening()
                        } else {
                            speechManager.startListening()
                        }
                    }) {
                        HStack {
                            Image(systemName: speechManager.isListening ? "mic.fill" : "mic")
                                .foregroundColor(speechManager.isListening ? .green : .blue)
                            Text(speechManager.isListening ? "Stop Listening" : "Start Voice Commands")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color(.systemGray6).opacity(0.3))
                        .cornerRadius(12)
                    }
                }
                
                // Voice Commands Help
                VStack(alignment: .leading, spacing: 12) {
                    Text("Voice Commands")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        VoiceCommandRow(command: "Stop", description: "Stop current exercise")
                        VoiceCommandRow(command: "Pause", description: "Pause the workout")
                        VoiceCommandRow(command: "Next", description: "Continue to next set")
                        VoiceCommandRow(command: "Continue", description: "Resume workout")
                    }
                }
                .padding()
                .background(Color(.systemGray6).opacity(0.3))
                .cornerRadius(12)
                
                // Speech Settings
                VStack(alignment: .leading, spacing: 12) {
                    Text("Speech Settings")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        SpeechSettingRow(title: "Analysis Results", description: "Speak AI analysis results")
                        SpeechSettingRow(title: "Form Feedback", description: "Real-time form corrections")
                        SpeechSettingRow(title: "Workout Events", description: "Set completion and rep counts")
                        SpeechSettingRow(title: "Voice Commands", description: "Control app with voice")
                    }
                }
                .padding()
                .background(Color(.systemGray6).opacity(0.3))
                .cornerRadius(12)
                
                Spacer()
            }
            .padding(.horizontal)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color(red: 18/255, green: 32/255, blue: 47/255), Color(red: 36/255, green: 52/255, blue: 71/255)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }
}

struct VoiceCommandRow: View {
    let command: String
    let description: String
    
    var body: some View {
        HStack {
            Text(command)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.blue)
                .frame(width: 80, alignment: .leading)
            
            Text(description)
                .font(.subheadline)
                .foregroundColor(.white)
            
            Spacer()
        }
    }
}

struct SpeechSettingRow: View {
    let title: String
    let description: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        }
    }
} 