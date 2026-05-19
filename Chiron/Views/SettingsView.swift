import SwiftUI

/// App-level preferences that aren't surfaced anywhere else in the user profile:
/// audio, haptics, camera coaching, and weight units. Account, name/email, coach
/// persona, intensity, and bodyweight live on `ProfileView` itself, so this screen
/// deliberately doesn't repeat them.
struct SettingsView: View {
    @StateObject private var speech = SpeechManager.shared
    @StateObject private var haptics = HapticsManager.shared
    @StateObject private var cameraCoaching = CameraCoachingPreferencesManager.shared
    @StateObject private var volumeTrigger = VolumeTriggerPreferences.shared
    @StateObject private var telemetryPrefs = TelemetryPreferencesManager.shared
    @State private var preferredUnits: UnitSystem = .imperial
    @State private var profileMissing = false

    private let profileStore = UserDefaultsUserProfileStore()

    var body: some View {
        Form {
            audioSection
            hapticsSection
            cameraCoachingSection
            volumeTriggerSection
            unitsSection
            helpImproveChironSection
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadPreferredUnits)
    }

    // MARK: - Audio & Voice

    private var audioSection: some View {
        Section {
            Toggle("Spoken Cues", isOn: $speech.speechEnabled)
        } header: {
            Text("Audio & Voice")
        } footer: {
            Text("When off, the coach stays silent, including PR call-outs, set wrap-ups, and rest reminders. Sound effects from local audio still play.")
        }
    }

    // MARK: - Haptics

    private var hapticsSection: some View {
        Section {
            Toggle("Haptic Feedback", isOn: $haptics.isEnabled)
        } header: {
            Text("Haptics")
        } footer: {
            Text("Disables tab switches, weight scroller snaps, set start/end, and badge unlock taps.")
        }
    }

    // MARK: - Camera Coaching

    private var cameraCoachingSection: some View {
        Section {
            Toggle("Camera Coaching", isOn: $cameraCoaching.masterEnabled)
        } header: {
            Text("Camera Coaching")
        } footer: {
            Text("Master switch for on-device form analysis during sets. When off, no exercise will run rep counting or form cues, regardless of per-exercise settings.")
        }
    }

    // MARK: - Volume Button Set Control

    private var volumeTriggerSection: some View {
        Section {
            Toggle("Volume Button Set Control", isOn: $volumeTrigger.isEnabled)
        } header: {
            Text("Hands-Free Set Control")
        } footer: {
            Text("When on, pressing the volume up or down button (on your phone or on connected headphones) starts your next set and ends the current one while you're on the Track tab. Music keeps playing; you'll see a brief volume blip before it settles back.")
        }
    }

    // MARK: - Units

    private var unitsSection: some View {
        Section {
            Picker("Weight Units", selection: $preferredUnits) {
                ForEach(UnitSystem.allCases) { system in
                    Text(system.displayName).tag(system)
                }
            }
            .pickerStyle(.segmented)
            .disabled(profileMissing)
            .onChange(of: preferredUnits) { _, newValue in
                persistPreferredUnits(newValue)
            }
        } header: {
            Text("Units")
        } footer: {
            Text(profileMissing
                 ? "Finish onboarding to choose your display units."
                 : "Affects how weights are shown across the app. Stored values aren't converted, only the display.")
        }
    }

    // MARK: - Help Improve Chiron

    private var helpImproveChironSection: some View {
        Section {
            Toggle("Share Workout Data", isOn: $telemetryPrefs.shareDataToImproveChiron)
        } header: {
            Text("Help Improve Chiron")
        } footer: {
            Text("Share anonymous form data and short clips of your sets so we can keep tuning the coaching. Tied to an opaque device handle. No name, no email.")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section(header: Text("About")) {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersionString)
                    .foregroundColor(.textSecondary)
            }
        }
    }

    // MARK: - Persistence

    private func loadPreferredUnits() {
        guard let profile = profileStore.load() else {
            profileMissing = true
            return
        }
        profileMissing = false
        preferredUnits = profile.preferredUnits
    }

    private func persistPreferredUnits(_ newValue: UnitSystem) {
        guard var profile = profileStore.load() else { return }
        guard profile.preferredUnits != newValue else { return }
        profile.preferredUnits = newValue
        try? profileStore.save(profile)
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .preferredColorScheme(.dark)
}
