import Foundation
import SwiftUI

// MARK: - Form Status
enum FormStatus {
    case good, perfect, watch, poor
    
    var color: Color {
        switch self {
        case .good: return .green
        case .perfect: return .green
        case .watch: return .orange
        case .poor: return .red
        }
    }
    
    var text: String {
        switch self {
        case .good: return "Good"
        case .perfect: return "Perfect"
        case .watch: return "Watch"
        case .poor: return "Poor"
        }
    }
}

// MARK: - Feedback Types
enum FeedbackType: String, CaseIterable, Codable {
    case realTime = "real_time"
    case set = "set"
    case workout = "workout"
    case cloudAnalysis = "cloud_analysis"
    
    var displayName: String {
        switch self {
        case .realTime: return "Real-time"
        case .set: return "Set"
        case .workout: return "Workout"
        case .cloudAnalysis: return "AI Analysis"
        }
    }
    
    var icon: String {
        switch self {
        case .realTime: return "bolt.fill"
        case .set: return "list.bullet"
        case .workout: return "chart.bar.fill"
        case .cloudAnalysis: return "brain.head.profile"
        }
    }
    
    var color: Color {
        switch self {
        case .realTime: return .blue
        case .set: return .green
        case .workout: return .orange
        case .cloudAnalysis: return .purple
        }
    }
}

// MARK: - Feedback Severity
enum FeedbackSeverity: String, CaseIterable, Codable {
    case info = "info"
    case warning = "warning"
    case error = "error"
    case success = "success"
    
    var displayName: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        case .success: return "Success"
        }
    }
    
    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .success: return "checkmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }
}

// MARK: - Feedback Item
struct FeedbackItem: Identifiable, Codable {
    let id: UUID
    let type: FeedbackType
    let severity: FeedbackSeverity
    let title: String
    let message: String
    let timestamp: Date
    let repNumber: Int?
    let exerciseType: String?
    let formScore: Double?
    let recommendations: [String]?
    
    init(type: FeedbackType, severity: FeedbackSeverity, title: String, message: String, repNumber: Int? = nil, exerciseType: String? = nil, formScore: Double? = nil, recommendations: [String]? = nil) {
        self.id = UUID()
        self.type = type
        self.severity = severity
        self.title = title
        self.message = message
        self.timestamp = Date()
        self.repNumber = repNumber
        self.exerciseType = exerciseType
        self.formScore = formScore
        self.recommendations = recommendations
    }
}

// MARK: - Cloud Analysis Feedback
struct CloudAnalysisFeedback: Codable {
    let workoutId: String
    let exerciseType: String
    let totalReps: Int
    let averageFormScore: Double
    let bestRep: Int
    let worstRep: Int
    let repAnalyses: [RepAnalysis]
    let overallFeedback: [String]
    let recommendations: [String]
    let analysisTimestamp: Date
    
    init(from analysisResults: [String: Any]) {
        self.workoutId = analysisResults["workout_id"] as? String ?? ""
        self.exerciseType = analysisResults["exercise_type"] as? String ?? "squat"
        self.totalReps = analysisResults["total_reps"] as? Int ?? 0
        self.averageFormScore = analysisResults["average_form_score"] as? Double ?? 0.0
        self.bestRep = analysisResults["best_rep"] as? Int ?? 0
        self.worstRep = analysisResults["worst_rep"] as? Int ?? 0
        
        // Parse rep analyses
        if let repAnalysesData = analysisResults["rep_analyses"] as? [[String: Any]] {
            self.repAnalyses = repAnalysesData.map { RepAnalysis(from: $0) }
        } else {
            self.repAnalyses = []
        }
        
        self.overallFeedback = analysisResults["overall_feedback"] as? [String] ?? []
        self.recommendations = analysisResults["recommendations"] as? [String] ?? []
        self.analysisTimestamp = Date()
    }
}

// MARK: - Rep Analysis
struct RepAnalysis: Identifiable, Codable {
    let id: UUID
    let repNumber: Int
    let startFrame: Int
    let endFrame: Int
    let duration: Double
    let depthScore: Double
    let postureScore: Double
    let tempoScore: Double
    let overallScore: Double
    let issues: [String]
    let landmarksCount: Int
    
    init(from data: [String: Any]) {
        self.id = UUID()
        self.repNumber = data["rep_number"] as? Int ?? 0
        self.startFrame = data["start_frame"] as? Int ?? 0
        self.endFrame = data["end_frame"] as? Int ?? 0
        self.duration = data["duration"] as? Double ?? 0.0
        self.depthScore = data["depth_score"] as? Double ?? 0.0
        self.postureScore = data["posture_score"] as? Double ?? 0.0
        self.tempoScore = data["tempo_score"] as? Double ?? 0.0
        self.overallScore = data["overall_score"] as? Double ?? 0.0
        self.issues = data["issues"] as? [String] ?? []
        self.landmarksCount = data["landmarks_count"] as? Int ?? 0
    }
}

// MARK: - Feedback Manager
class FeedbackManager: ObservableObject {
    static let shared = FeedbackManager()
    
    @Published var allFeedback: [FeedbackItem] = []
    @Published var feedbackByType: [FeedbackType: [FeedbackItem]] = [:]
    
    private init() {}
    
    func addFeedback(_ feedback: FeedbackItem) {
        allFeedback.append(feedback)
        
        if feedbackByType[feedback.type] == nil {
            feedbackByType[feedback.type] = []
        }
        feedbackByType[feedback.type]?.append(feedback)
        
        // Sort by timestamp (newest first)
        allFeedback.sort { $0.timestamp > $1.timestamp }
        feedbackByType[feedback.type]?.sort { $0.timestamp > $1.timestamp }
    }
    
    func getFeedback(for type: FeedbackType) -> [FeedbackItem] {
        return feedbackByType[type] ?? []
    }
    
    func getFeedback(for severity: FeedbackSeverity) -> [FeedbackItem] {
        return allFeedback.filter { $0.severity == severity }
    }
    
    func clearFeedback(for type: FeedbackType? = nil) {
        if let type = type {
            feedbackByType[type] = []
            allFeedback.removeAll { $0.type == type }
        } else {
            allFeedback.removeAll()
            feedbackByType.removeAll()
        }
    }
    
    func getFeedbackSummary() -> FeedbackSummary {
        let totalFeedback = allFeedback.count
        let realTimeCount = getFeedback(for: .realTime).count
        let setCount = getFeedback(for: .set).count
        let workoutCount = getFeedback(for: .workout).count
        let cloudCount = getFeedback(for: .cloudAnalysis).count
        
        let severityCounts = FeedbackSeverity.allCases.reduce(into: [:]) { result, severity in
            result[severity] = getFeedback(for: severity).count
        }
        
        return FeedbackSummary(
            totalFeedback: totalFeedback,
            feedbackByType: [
                .realTime: realTimeCount,
                .set: setCount,
                .workout: workoutCount,
                .cloudAnalysis: cloudCount
            ],
            feedbackBySeverity: severityCounts
        )
    }
}

// MARK: - Feedback Summary
struct FeedbackSummary {
    let totalFeedback: Int
    let feedbackByType: [FeedbackType: Int]
    let feedbackBySeverity: [FeedbackSeverity: Int]
    
    var hasIssues: Bool {
        return (feedbackBySeverity[.warning] ?? 0) > 0 || (feedbackBySeverity[.error] ?? 0) > 0
    }
    
    var hasSuccess: Bool {
        return (feedbackBySeverity[.success] ?? 0) > 0
    }
} 