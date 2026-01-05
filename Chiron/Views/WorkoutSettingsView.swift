//
//  WorkoutSettingsView.swift
//  Chiron
//
//  Settings view for workout preferences and configuration
//

import SwiftUI

/// Settings view for workout preferences, matching the reference design.
struct WorkoutSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Audio Section
                        audioSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Workout Settings")
                        .font(.neueMontrealSemiBold(size: 16))
                        .foregroundColor(.textPrimary)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.neueMontrealSemiBold(size: 16))
                            .foregroundColor(.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Sections
    
    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "AUDIO")
            
            VStack(spacing: 12) {
                SettingsToggleRow(
                    title: "Exercise Announcement",
                    description: "Recommended. When enabled, the name and quantity or duration of the exercise will be played at the beginning of each movement.",
                    isOn: .constant(true)
                )
                
                SettingsNavigationRow(
                    title: "Exercise Instructions",
                    value: "Periodic",
                    description: "Choose how often to hear detailed movement instructions during your workout.",
                    action: {}
                )
                
                SettingsToggleRow(
                    title: "Workout Tones",
                    description: nil,
                    isOn: .constant(true)
                )
                
                SettingsNavigationRow(
                    title: "Tone",
                    value: "Marimba (Default)",
                    description: "Recommended. When enabled, sounds will be played to indicate the beginning and end of exercises.",
                    action: {}
                )
                
                SettingsNavigationRow(
                    title: "Audio Volume",
                    value: nil,
                    description: nil,
                    action: {}
                )
            }
        }
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.neueMontrealBold(size: 13))
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 4)
    }
}

// MARK: - Settings Toggle Row

private struct SettingsToggleRow: View {
    let title: String
    let description: String?
    @Binding var isOn: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.neueMontrealRegular(size: 16))
                    .foregroundColor(.textPrimary)
                
                Spacer()
                
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(.green)
            }
            .padding(16)
            .background(Color.white.opacity(0.06))
            .cornerRadius(12)
            
            if let description = description {
                Text(description)
                    .font(.neueMontrealRegular(size: 13))
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

// MARK: - Settings Navigation Row

private struct SettingsNavigationRow: View {
    let title: String
    let value: String?
    let description: String?
    let action: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: action) {
                HStack {
                    Text(title)
                        .font(.neueMontrealRegular(size: 16))
                        .foregroundColor(.textPrimary)
                    
                    Spacer()
                    
                    if let value = value {
                        Text(value)
                            .font(.neueMontrealRegular(size: 16))
                            .foregroundColor(.textSecondary)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                }
                .padding(16)
                .background(Color.white.opacity(0.06))
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            
            if let description = description {
                Text(description)
                    .font(.neueMontrealRegular(size: 13))
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

#Preview {
    WorkoutSettingsView()
        .preferredColorScheme(.dark)
}

