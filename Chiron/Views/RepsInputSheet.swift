//
//  RepsInputSheet.swift
//  Chiron
//
//  Modal sheet for inputting number of reps completed for an exercise set.
//  Provides text field input and quick adjust buttons (±1 and ±5).
//

import SwiftUI

/// Modal sheet for logging number of reps completed in an exercise set.
///
/// Features:
/// - Large text field for manual reps entry
/// - Quick adjust buttons: ±1 rep and ±5 reps (with "5" label on ±5 buttons)
/// - Validates numeric input
/// - Saves reps via callback when user taps Save
struct RepsInputSheet: View {
    @Binding var isPresented: Bool
    @Binding var reps: Int?
    let onSave: (Int) -> Void
    
    @State private var selectedReps: Int = 0
    @State private var repsString: String = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.background.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Title
                    VStack(spacing: 8) {
                        Text("Log Reps")
                            .font(.neueMontrealBold(size: 28))
                            .foregroundColor(.textPrimary)
                        
                        Text("Enter the number of reps completed")
                            .font(.neueMontrealRegular(size: 16))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.top, 20)
                    
                    // Reps input
                    VStack(spacing: 16) {
                        // Text field for manual input
                        TextField("Reps", text: $repsString)
                            .keyboardType(.numberPad)
                            .font(.neueMontrealBold(size: 48))
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(16)
                            .onChange(of: repsString) { oldValue, newValue in
                                if let value = Int(newValue) {
                                    selectedReps = value
                                }
                            }
                            .onAppear {
                                if let reps = reps {
                                    repsString = String(reps)
                                    selectedReps = reps
                                }
                            }
                        
                        // Quick adjust buttons
                        HStack(spacing: 12) {
                            QuickAdjustButton(icon: "minus", label: "5", action: {
                                selectedReps = max(0, selectedReps - 5)
                                repsString = String(selectedReps)
                            })
                            
                            QuickAdjustButton(icon: "minus.circle.fill", action: {
                                selectedReps = max(0, selectedReps - 1)
                                repsString = String(selectedReps)
                            })
                            
                            Spacer()
                            
                            QuickAdjustButton(icon: "plus.circle.fill", action: {
                                selectedReps += 1
                                repsString = String(selectedReps)
                            })
                            
                            QuickAdjustButton(icon: "plus", label: "5", action: {
                                selectedReps += 5
                                repsString = String(selectedReps)
                            })
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    // Save button
                    Button(action: {
                        onSave(selectedReps)
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
            .preferredColorScheme(.dark)
        }
    }
}

private struct QuickAdjustButton: View {
    let icon: String
    let label: String?
    let action: () -> Void
    
    init(icon: String, label: String? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.textPrimary)
                
                if let label = label {
                    Text(label)
                        .font(.neueMontrealBold(size: 10))
                        .foregroundColor(.textPrimary)
                        .offset(y: 18)
                }
            }
            .frame(width: 50, height: 50)
            .background(Color.white.opacity(0.1))
            .clipShape(Circle())
        }
    }
}

#Preview {
    RepsInputSheet(
        isPresented: .constant(true),
        reps: .constant(nil),
        onSave: { _ in }
    )
}
