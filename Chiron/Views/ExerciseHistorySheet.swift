//
//  ExerciseHistorySheet.swift
//  Chiron
//
//  Modal sheet for displaying exercise history from previous workouts.
//  Shows all logged sets for a specific exercise with weight, reps, flags, and dates.
//

import SwiftUI

/// Modal sheet displaying exercise history from previous workouts.
///
/// Features:
/// - Fetches set logs from Firestore for the specified exercise
/// - Displays date, set number, weight, reps, and flags
/// - Shows loading state while fetching
/// - Handles empty state (no history yet)
/// - Handles error state with retry option
struct ExerciseHistorySheet: View {
    @Binding var isPresented: Bool
    let exerciseName: String
    @StateObject private var workoutLogService = WorkoutLogService.shared
    
    @State private var setLogs: [ExerciseSetLog] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.background.ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .primaryPurple))
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.textSecondary)
                        
                        Text("Error Loading History")
                            .font(.neueMontrealBold(size: 20))
                            .foregroundColor(.textPrimary)
                        
                        Text(error)
                            .font(.neueMontrealRegular(size: 16))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        
                        Button("Retry") {
                            loadHistory()
                        }
                        .font(.neueMontrealSemiBold(size: 16))
                        .foregroundColor(.textPrimary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.primaryPurple)
                        .cornerRadius(12)
                    }
                } else if setLogs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 48))
                            .foregroundColor(.textSecondary)
                        
                        Text("No History Yet")
                            .font(.neueMontrealBold(size: 20))
                            .foregroundColor(.textPrimary)
                        
                        Text("Start logging sets to see your progress here")
                            .font(.neueMontrealRegular(size: 16))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Header
                            VStack(spacing: 8) {
                                Text(exerciseName)
                                    .font(.neueMontrealBold(size: 24))
                                    .foregroundColor(.textPrimary)
                                
                                Text("\(setLogs.count) logged sets")
                                    .font(.neueMontrealRegular(size: 14))
                                    .foregroundColor(.textSecondary)
                            }
                            .padding(.top, 20)
                            .padding(.bottom, 24)
                            
                            // History list
                            LazyVStack(spacing: 12) {
                                ForEach(setLogs) { setLog in
                                    HistoryRow(setLog: setLog)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundColor(.textPrimary)
                }
            }
            .onAppear {
                loadHistory()
            }
            .preferredColorScheme(.dark)
        }
    }
    
    private func loadHistory() {
        isLoading = true
        errorMessage = nil
        
        workoutLogService.getHistoryForExercise(exerciseName) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let logs):
                    setLogs = logs
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    print("❌ Error loading history: \(error.localizedDescription)")
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let setLog: ExerciseSetLog
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Date
            VStack(alignment: .leading, spacing: 4) {
                Text(dateFormatter.string(from: setLog.timestamp))
                    .font(.neueMontrealRegular(size: 12))
                    .foregroundColor(.textSecondary)
                
                Text("Set \(setLog.setNumber)")
                    .font(.neueMontrealSemiBold(size: 14))
                    .foregroundColor(.textPrimary)
            }
            
            Spacer()
            
            // Weight and reps
            HStack(spacing: 16) {
                if let weight = setLog.weight {
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f", weight))
                            .font(.neueMontrealBold(size: 16))
                            .foregroundColor(.textPrimary)
                        Text("lbs")
                            .font(.neueMontrealRegular(size: 12))
                            .foregroundColor(.textSecondary)
                    }
                }
                
                if let reps = setLog.reps {
                    HStack(spacing: 4) {
                        Text("\(reps)")
                            .font(.neueMontrealBold(size: 16))
                            .foregroundColor(.textPrimary)
                        Text("reps")
                            .font(.neueMontrealRegular(size: 12))
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            
            // Flags
            HStack(spacing: 8) {
                if setLog.flaggedPain {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.expertRed)
                }
                
                if setLog.flaggedNotInControl {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.intermediateYellow)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}

#Preview {
    ExerciseHistorySheet(
        isPresented: .constant(true),
        exerciseName: "Barbell Back Squat"
    )
}
