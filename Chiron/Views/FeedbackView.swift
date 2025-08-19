import SwiftUI

struct FeedbackView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @State private var selectedFeedbackType: FeedbackType = .realTime
    @State private var selectedSeverity: FeedbackSeverity? = nil
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    Text("Feedback History")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    // Feedback Summary
                    FeedbackSummaryCard(summary: viewModel.getFeedbackSummary())
                }
                .padding()
                
                // Filter Controls
                HStack(spacing: 12) {
                    // Feedback Type Filter
                    Picker("Type", selection: $selectedFeedbackType) {
                        ForEach(FeedbackType.allCases, id: \.self) { type in
                            HStack {
                                Image(systemName: type.icon)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    // Severity Filter
                    Menu {
                        Button("All Severities") {
                            selectedSeverity = nil
                        }
                        ForEach(FeedbackSeverity.allCases, id: \.self) { severity in
                            Button(severity.displayName) {
                                selectedSeverity = severity
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: selectedSeverity?.icon ?? "line.3.horizontal")
                            Text(selectedSeverity?.displayName ?? "All")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6).opacity(0.3))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal)
                
                // Feedback List
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredFeedback) { feedback in
                            FeedbackCardView(feedback: feedback)
                        }
                    }
                    .padding()
                }
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button(action: clearSelectedFeedback) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear \(selectedFeedbackType.displayName)")
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(.systemGray6).opacity(0.3))
                        .cornerRadius(8)
                    }
                    
                    Button(action: clearAllFeedback) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Clear All")
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(.systemGray6).opacity(0.3))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
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
    
    private var filteredFeedback: [FeedbackItem] {
        var feedback = viewModel.getFeedback(for: selectedFeedbackType)
        
        if let severity = selectedSeverity {
            feedback = feedback.filter { $0.severity == severity }
        }
        
        return feedback
    }
    
    private func clearSelectedFeedback() {
        viewModel.clearFeedback(for: selectedFeedbackType)
    }
    
    private func clearAllFeedback() {
        viewModel.clearFeedback()
    }
}

struct FeedbackSummaryCard: View {
    let summary: FeedbackSummary
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Feedback")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("\(summary.totalFeedback) items")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        if summary.hasSuccess {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                        if summary.hasIssues {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                    }
                    Text(summary.hasIssues ? "Issues Found" : "All Good")
                        .font(.caption)
                        .foregroundColor(summary.hasIssues ? .orange : .green)
                }
            }
            
            // Feedback by type
            HStack(spacing: 16) {
                ForEach(FeedbackType.allCases, id: \.self) { type in
                    VStack(spacing: 4) {
                        Image(systemName: type.icon)
                            .foregroundColor(type.color)
                            .font(.title2)
                        Text("\(summary.feedbackByType[type] ?? 0)")
                            .font(.caption)
                            .foregroundColor(.white)
                        Text(type.displayName)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(12)
    }
}

struct FeedbackDetailCard: View {
    let feedback: FeedbackItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: feedback.type.icon)
                    .foregroundColor(feedback.type.color)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(feedback.title)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 8) {
                        Text(feedback.type.displayName)
                            .font(.caption)
                            .foregroundColor(feedback.type.color)
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text(feedback.severity.displayName)
                            .font(.caption)
                            .foregroundColor(feedback.severity.color)
                        
                        if let repNumber = feedback.repNumber {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Text("Rep \(repNumber)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Spacer()
                
                Text(feedback.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            // Message
            Text(feedback.message)
                .font(.subheadline)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
            
            // Form Score (if available)
            if let formScore = feedback.formScore {
                HStack {
                    Text("Form Score:")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    Text("\(Int(formScore * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(scoreColor(formScore))
                    
                    Spacer()
                }
            }
            
            // Recommendations (if available)
            if let recommendations = feedback.recommendations, !recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recommendations:")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    ForEach(recommendations, id: \.self) { recommendation in
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                            Text(recommendation)
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(12)
    }
    
    private func scoreColor(_ score: Double) -> Color {
        if score >= 0.8 {
            return .green
        } else if score >= 0.6 {
            return .orange
        } else {
            return .red
        }
    }
} 