import SwiftUI

/// Settings view with coaching style selection and preferences.
struct SettingsView: View {
    @StateObject private var viewModel = WorkoutViewModel()
    @StateObject private var preferencesManager = UserPreferencesManager.shared
    @State private var selectedCoachingStyle: String = "Supportive"
    
    let coachingStyles = ["Supportive", "Direct", "Encouraging", "Technical", "Motivational"]
    
    var body: some View {
        Form {
            Section(header: Text("Coaching")) {
                Picker("Coaching Style", selection: $selectedCoachingStyle) {
                    ForEach(coachingStyles, id: \.self) { style in
                        Text(style).tag(style)
                    }
                }
                .onChange(of: selectedCoachingStyle) { oldValue, newValue in
                    viewModel.coachingStyle = newValue
                    // TODO: Persist coaching style preference
                }
                
                Text("Choose how you want to receive feedback during workouts")
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            
            Section(header: Text("Account")) {
                Text("Name")
                Text("Email")
            }
            
            Section(header: Text("Preferences")) {
                Toggle("Haptics", isOn: .constant(true))
            }
            
            Section(header: Text("Training")) {
                NavigationLink("Training Log") {
                    Text("Training Log")
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedCoachingStyle = viewModel.coachingStyle
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .preferredColorScheme(.dark)
}

