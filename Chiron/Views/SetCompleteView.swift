import SwiftUI
import AVFoundation

struct SetCompleteView: View {
    @ObservedObject var viewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAnalysisResults = false
    
    private let feedbackItems = [
        FeedbackItem(
            type: .set,
            severity: .warning,
            title: "Tempo too fast",
            message: "2 reps - Try slowing down the descent"
        ),
        FeedbackItem(
            type: .set,
            severity: .success,
            title: "Excellent depth",
            message: "Consistent throughout the set"
        )
    ]
    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                VStack(spacing: 24) {
                    // Header
                    HStack {
                        Text("Set Complete!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Spacer()
                        Button("Done") {
                            dismiss()
                        }
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal)
                    // Stats Card
                    VStack(spacing: 20) {
                        HStack(spacing: 40) {
                            VStack {
                                Text("\(viewModel.currentSetReps)")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                                Text("Total Reps")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            VStack {
                                Text("\(viewModel.goodFormReps)")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                                Text("Good Form")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        VStack(spacing: 8) {
                            HStack {
                                Text("Form Score")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("\(viewModel.currentSetScore)%")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                            }
                            // Progress Bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(height: 8)
                                        .cornerRadius(4)
                                    Rectangle()
                                        .fill(Color.green)
                                        .frame(width: geometry.size.width * CGFloat(viewModel.currentSetScore) / 100.0, height: 8)
                                        .cornerRadius(4)
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                    .padding(24)
                    .background(Color(.systemGray6).opacity(0.3))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    // Feedback Summary
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Feedback Summary")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                        LazyVStack(spacing: 12) {
                            ForEach(feedbackItems) { feedback in
                                FeedbackCardView(feedback: feedback)
                            }
                        }
                        .padding(.horizontal)
                    }
                    Spacer()
                    
                    // Upload Progress
                    if viewModel.isUploading {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Uploading workout video...")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("\(Int(viewModel.uploadProgress * 100))%")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                            ProgressView(value: viewModel.uploadProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                    }
                    
                    // Analysis Progress
                    if viewModel.isAnalyzing {
                        VStack(spacing: 8) {
                            HStack {
                                Text("Analyzing workout form...")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                    }
                    
                    // Speech Status
                    if SpeechManager.shared.isSpeaking {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundColor(.green)
                                    .font(.subheadline)
                                Text("Speaking analysis results...")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                                Spacer()
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 16)
                    }
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button(action: {
                            if viewModel.analysisResults != nil {
                                showAnalysisResults = true
                            } else {
                                viewModel.startNextSet()
                                dismiss()
                            }
                        }) {
                            HStack {
                                if viewModel.analysisResults != nil {
                                    Image(systemName: "chart.bar.fill")
                                        .font(.headline)
                                }
                                Text(viewModel.analysisResults != nil ? "View Analysis" : "Start Next Set")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.blue)
                            .cornerRadius(16)
                        }
                        .disabled(viewModel.isUploading || viewModel.isAnalyzing)
                        Button(action: {
                            // TODO: Finish workout and save data
                            dismiss()
                        }) {
                            Text("Finish Workout")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color(.systemGray6).opacity(0.3))
                                .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showAnalysisResults) {
            if let analysisResults = viewModel.analysisResults {
                AnalysisResultsView(analysisResults: analysisResults)
            }
        }
    }
} 