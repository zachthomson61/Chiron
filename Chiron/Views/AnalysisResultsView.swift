import SwiftUI

struct AnalysisResultsView: View {
    let analysisResults: [String: Any]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Form Analysis")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("AI-powered form feedback")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top)
                    
                    // Overall Score
                    if let averageScore = analysisResults["average_form_score"] as? Double {
                        VStack(spacing: 12) {
                            Text("Overall Form Score")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                                    .frame(width: 120, height: 120)
                                
                                Circle()
                                    .trim(from: 0, to: averageScore)
                                    .stroke(scoreColor(averageScore), lineWidth: 8)
                                    .frame(width: 120, height: 120)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.easeInOut(duration: 1.0), value: averageScore)
                                
                                VStack {
                                    Text("\(Int(averageScore * 100))")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                    Text("%")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6).opacity(0.3))
                        .cornerRadius(16)
                    }
                    
                    // Rep Analysis
                    if let repAnalyses = analysisResults["rep_analyses"] as? [[String: Any]] {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Rep Breakdown")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                            
                            LazyVStack(spacing: 12) {
                                ForEach(Array(repAnalyses.enumerated()), id: \.offset) { index, rep in
                                    RepAnalysisCard(rep: rep, repNumber: index + 1)
                                }
                            }
                        }
                    }
                    
                    // Overall Feedback
                    if let feedback = analysisResults["overall_feedback"] as? [String] {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Overall Feedback")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                            
                            VStack(spacing: 8) {
                                ForEach(feedback, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                        Text(item)
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                        Spacer()
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6).opacity(0.3))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }
                    
                    // Recommendations
                    if let recommendations = analysisResults["recommendations"] as? [String] {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recommendations")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                            
                            VStack(spacing: 8) {
                                ForEach(recommendations, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "lightbulb.fill")
                                            .foregroundColor(.yellow)
                                            .font(.caption)
                                        Text(item)
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                        Spacer()
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6).opacity(0.3))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }
                    
                    Spacer()
                }
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

struct RepAnalysisCard: View {
    let rep: [String: Any]
    let repNumber: Int
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Rep \(repNumber)")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Spacer()
                
                if let overallScore = rep["overall_score"] as? Double {
                    Text("\(Int(overallScore * 100))%")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(scoreColor(overallScore))
                }
            }
            
            // Score breakdown
            HStack(spacing: 16) {
                ScoreIndicator(
                    title: "Depth",
                    score: rep["depth_score"] as? Double ?? 0.0
                )
                
                ScoreIndicator(
                    title: "Posture",
                    score: rep["posture_score"] as? Double ?? 0.0
                )
                
                ScoreIndicator(
                    title: "Tempo",
                    score: rep["tempo_score"] as? Double ?? 0.0
                )
            }
            
            // Issues
            if let issues = rep["issues"] as? [String], !issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(issues, id: \.self) { issue in
                        HStack(alignment: .top, spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text(issue)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(12)
        .padding(.horizontal)
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

struct ScoreIndicator: View {
    let title: String
    let score: Double
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
            
            Text("\(Int(score * 100))%")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(scoreColor(score))
        }
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