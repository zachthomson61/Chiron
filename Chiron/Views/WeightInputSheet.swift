//
//  WeightInputSheet.swift
//  Chiron
//
//  Sheet for inputting weight for an exercise set
//

import SwiftUI

struct WeightInputSheet: View {
    @Binding var isPresented: Bool
    @Binding var weight: Double?
    let onSave: (Double) -> Void
    
    @State private var selectedWeight: Double = 0.0
    @State private var weightString: String = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.background.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Title
                    VStack(spacing: 8) {
                        Text("Log Weight")
                            .font(.neueMontrealBold(size: 28))
                            .foregroundColor(.textPrimary)
                        
                        Text("Enter the weight used for this set")
                            .font(.neueMontrealRegular(size: 16))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.top, 20)
                    
                    // Weight input
                    VStack(spacing: 16) {
                        // Text field for manual input
                        TextField("Weight (lbs)", text: $weightString)
                            .keyboardType(.decimalPad)
                            .font(.neueMontrealBold(size: 48))
                            .foregroundColor(.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(16)
                            .onChange(of: weightString) { newValue in
                                if let value = Double(newValue) {
                                    selectedWeight = value
                                }
                            }
                            .onAppear {
                                if let weight = weight {
                                    weightString = String(format: "%.1f", weight)
                                    selectedWeight = weight
                                }
                            }
                        
                        // Quick adjust buttons
                        HStack(spacing: 12) {
                            QuickAdjustButton(icon: "minus", label: "5", action: {
                                selectedWeight = max(0, selectedWeight - 5)
                                weightString = String(format: "%.1f", selectedWeight)
                            })
                            
                            QuickAdjustButton(icon: "minus.circle.fill", action: {
                                selectedWeight = max(0, selectedWeight - 1)
                                weightString = String(format: "%.1f", selectedWeight)
                            })
                            
                            Spacer()
                            
                            QuickAdjustButton(icon: "plus.circle.fill", action: {
                                selectedWeight += 1
                                weightString = String(format: "%.1f", selectedWeight)
                            })
                            
                            QuickAdjustButton(icon: "plus", label: "5", action: {
                                selectedWeight += 5
                                weightString = String(format: "%.1f", selectedWeight)
                            })
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    // Save button
                    Button(action: {
                        onSave(selectedWeight)
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
    WeightInputSheet(
        isPresented: .constant(true),
        weight: .constant(nil),
        onSave: { _ in }
    )
}
