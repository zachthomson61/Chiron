//
//  FlagOptionsSheet.swift
//  Chiron
//
//  Sheet for flagging pain or not in control during an exercise set
//

import SwiftUI

struct FlagOptionsSheet: View {
    @Binding var isPresented: Bool
    @Binding var flaggedPain: Bool
    @Binding var flaggedNotInControl: Bool
    let onSave: (Bool, Bool) -> Void
    
    @State private var selectedPain: Bool = false
    @State private var selectedNotInControl: Bool = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.background.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Title
                    VStack(spacing: 8) {
                        Text("Flag Issues")
                            .font(.neueMontrealBold(size: 28))
                            .foregroundColor(.textPrimary)
                        
                        Text("Mark any issues with this set")
                            .font(.neueMontrealRegular(size: 16))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.top, 20)
                    
                    // Flag options
                    VStack(spacing: 16) {
                        // Pain flag
                        FlagOptionRow(
                            title: "Pain",
                            description: "Experienced pain during this set",
                            icon: "exclamationmark.triangle.fill",
                            isSelected: $selectedPain,
                            color: .expertRed
                        )
                        
                        // Not in control flag
                        FlagOptionRow(
                            title: "Not in Control",
                            description: "Felt unstable or not in control",
                            icon: "hand.raised.fill",
                            isSelected: $selectedNotInControl,
                            color: .intermediateYellow
                        )
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    // Save button
                    Button(action: {
                        onSave(selectedPain, selectedNotInControl)
                        isPresented = false
                    }) {
                        Text("Save")
                            .font(.neueMontrealSemiBold(size: 18))
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.primaryPurple)
                            .cornerRadius(16)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.textPrimary)
                }
            }
            .onAppear {
                selectedPain = flaggedPain
                selectedNotInControl = flaggedNotInControl
            }
            .preferredColorScheme(.dark)
        }
    }
}

private struct FlagOptionRow: View {
    let title: String
    let description: String
    let icon: String
    @Binding var isSelected: Bool
    let color: Color
    
    var body: some View {
        Button(action: {
            isSelected.toggle()
        }) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(isSelected ? color : .textSecondary)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? color.opacity(0.2) : Color.white.opacity(0.1))
                    .clipShape(Circle())
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.neueMontrealSemiBold(size: 18))
                        .foregroundColor(.textPrimary)
                    
                    Text(description)
                        .font(.neueMontrealRegular(size: 14))
                        .foregroundColor(.textSecondary)
                }
                
                Spacer()
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(color)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(.textSecondary)
                }
            }
            .padding(16)
            .background(isSelected ? color.opacity(0.1) : Color.white.opacity(0.05))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? color.opacity(0.5) : Color.clear, lineWidth: 2)
            )
        }
    }
}

#Preview {
    FlagOptionsSheet(
        isPresented: .constant(true),
        flaggedPain: .constant(false),
        flaggedNotInControl: .constant(false),
        onSave: { _, _ in }
    )
}
