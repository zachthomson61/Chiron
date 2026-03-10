import Foundation
import FirebaseStorage
import FirebaseCore
import UIKit

/// Ensures Firebase is configured once, on the main thread, right before first use.
private enum FirebaseConfigurator {
    static func ensureConfigured() {
        guard FirebaseApp.app() == nil else { return }

        if Thread.isMainThread {
            FirebaseApp.configure()
        } else {
            DispatchQueue.main.sync {
                if FirebaseApp.app() == nil {
                    FirebaseApp.configure()
                }
            }
        }
    }
}

/// Handles Firebase Storage uploads and related cloud orchestration for workouts.
class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()
    private lazy var storage: Storage = {
        FirebaseConfigurator.ensureConfigured()
        return Storage.storage()
    }()
    
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0.0
    
    // Cloud Run configuration - Update this to your actual deployed service URL
    private let cloudRunURL: String = "https://chiron-6c955.wl.r.appspot.com"
    private let openAIAPIKey: String = "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"
    
    // Firebase configuration for your project
    private let firebaseProjectID: String = "chiron-6c955"
    private let firebaseStorageBucket: String = "chiron-6c955.firebasestorage.app"
    
    private init() {}
    
    func uploadWorkoutVideo(videoURL: URL, workoutId: String, completion: @escaping (Result<String, Error>) -> Void) {
        
        // Enhanced file checking
        let fileExists = FileManager.default.fileExists(atPath: videoURL.path)
        
        guard fileExists else {
            completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video file does not exist"])))
            return
        }
        
        // Check file size
        guard let fileSize = try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int64, fileSize > 0 else {
            completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video file is empty or cannot be read"])))
            return
        }
        
        
        isUploading = true
        uploadProgress = 0.0
        
        let storageRef = storage.reference()
        let videoFileName = videoURL.lastPathComponent
        let videoRef = storageRef.child("workout-videos/\(workoutId)/\(videoFileName)")
        
        
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        
        // Add a delay to ensure file is fully written and accessible
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let uploadTask = videoRef.putFile(from: videoURL, metadata: metadata) { [weak self] metadata, error in
                DispatchQueue.main.async {
                    self?.isUploading = false
                    
                    if let error = error {
                        
                        // Try again with a delay if it's a file access error
                        if (error as NSError).domain == "FIRStorageErrorDomain" && (error as NSError).code == -13021 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                self?.retryUpload(videoURL: videoURL, videoRef: videoRef, metadata: metadata ?? StorageMetadata(), workoutId: workoutId, videoFileName: videoFileName, completion: completion)
                            }
                        } else {
                            completion(.failure(error))
                        }
                        return
                    }
                    
                    
                    // Get download URL
                    videoRef.downloadURL { url, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                completion(.failure(error))
                            } else if let downloadURL = url {
                                // Trigger the new architecture flow
                                self?.triggerMediaPipeAnalysis(downloadURL: downloadURL.absoluteString, workoutId: workoutId, videoFileName: videoFileName)
                                completion(.success(downloadURL.absoluteString))
                            } else {
                                completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL"])))
                            }
                        }
                    }
                }
            }
            
            // Monitor upload progress
            uploadTask.observe(.progress) { [weak self] (snapshot: StorageTaskSnapshot) in
                DispatchQueue.main.async {
                    let progress = Double(snapshot.progress!.completedUnitCount) / Double(snapshot.progress!.totalUnitCount)
                    self?.uploadProgress = progress
                }
            }
        }
    }
    
    private func retryUpload(videoURL: URL, videoRef: StorageReference, metadata: StorageMetadata, workoutId: String, videoFileName: String, completion: @escaping (Result<String, Error>) -> Void) {
        
        let retryTask = videoRef.putFile(from: videoURL, metadata: metadata) { [weak self] metadata, error in
            DispatchQueue.main.async {
                self?.isUploading = false
                
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                
                // Get download URL
                videoRef.downloadURL { url, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            completion(.failure(error))
                        } else if let downloadURL = url {
                            // Trigger the new architecture flow
                            self?.triggerMediaPipeAnalysis(downloadURL: downloadURL.absoluteString, workoutId: workoutId, videoFileName: videoFileName)
                            completion(.success(downloadURL.absoluteString))
                        } else {
                            completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL"])))
                        }
                    }
                }
            }
        }
        
        // Monitor retry upload progress
        retryTask.observe(.progress) { [weak self] (snapshot: StorageTaskSnapshot) in
            DispatchQueue.main.async {
                let progress = Double(snapshot.progress!.completedUnitCount) / Double(snapshot.progress!.totalUnitCount)
                self?.uploadProgress = progress
            }
        }
    }
    
    func uploadWorkoutData(workoutData: [String: Any], workoutId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let storageRef = storage.reference()
        let dataRef = storageRef.child("workout-data/\(workoutId)/workout.json")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: workoutData)
            let metadata = StorageMetadata()
            metadata.contentType = "application/json"
            
            dataRef.putData(jsonData, metadata: metadata) { metadata, error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    // MARK: - New Architecture Methods
    
    private func triggerMediaPipeAnalysis(downloadURL: String, workoutId: String, videoFileName: String) {
        
        // Prepare request for Cloud Run MediaPipe service
        let analysisRequest: [String: Any] = [
            "video_url": downloadURL,
            "workout_id": workoutId,
            "video_file_name": videoFileName,
            "exercise_type": "squat", // Can be made configurable
            "timestamp": Date().timeIntervalSince1970
        ]
        
        callCloudRunMediaPipe(request: analysisRequest, workoutId: workoutId)
    }
    
    private func callCloudRunMediaPipe(request: [String: Any], workoutId: String) {
        
        guard let url = URL(string: "\(cloudRunURL)/analyze-pose") else {
            return
        }
        
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: request)
        } catch {
            return
        }
        
        
        URLSession.shared.dataTask(with: urlRequest) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                }
                
                guard let data = data else {
                    return
                }
                
                
                do {
                    if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // Trigger OpenAI analysis with MediaPipe results
                        self?.triggerOpenAIAnalysis(mediaPipeResults: jsonResponse, workoutId: workoutId)
                    }
                } catch {
                    if let responseString = String(data: data, encoding: .utf8) {
                    }
                }
            }
        }.resume()
    }
    
    private func triggerOpenAIAnalysis(mediaPipeResults: [String: Any], workoutId: String) {
        
        // Prepare OpenAI request with MediaPipe results
        let openAIRequest: [String: Any] = [
            "model": "gpt-4",
            "messages": [
                [
                    "role": "system",
                    "content": "You are a professional fitness coach and form analyzer. Analyze the provided pose data and give constructive feedback on form, technique, and areas for improvement. Focus on safety, effectiveness, and actionable advice."
                ],
                [
                    "role": "user",
                    "content": generateOpenAIPrompt(from: mediaPipeResults)
                ]
            ],
            "max_tokens": 500,
            "temperature": 0.7
        ]
        
        callOpenAIAPI(request: openAIRequest, workoutId: workoutId)
    }
    
    private func generateOpenAIPrompt(from mediaPipeResults: [String: Any]) -> String {
        // Extract key information from MediaPipe results
        let repCount = mediaPipeResults["rep_count"] as? Int ?? 0
        let averageScore = mediaPipeResults["average_score"] as? Double ?? 0.0
        let issues = mediaPipeResults["issues"] as? [String] ?? []
        let poseData = mediaPipeResults["pose_data"] as? [[String: Any]] ?? []
        
        let prompt = """
        Analyze this workout session with the following data:
        
        - Total reps: \(repCount)
        - Average form score: \(String(format: "%.1f", averageScore * 100))%
        - Detected issues: \(issues.joined(separator: ", "))
        
        Pose analysis data: \(poseData.count) frames analyzed
        
        Please provide:
        1. Overall form assessment
        2. Specific feedback on technique
        3. Safety recommendations
        4. 3 actionable improvements
        5. Encouragement and motivation
        
        Keep the response concise, professional, and encouraging.
        """
        
        return prompt
    }
    
    private func callOpenAIAPI(request: [String: Any], workoutId: String) {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            return
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")
        
        do {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: request)
        } catch {
            return
        }
        
        URLSession.shared.dataTask(with: urlRequest) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    return
                }
                
                guard let data = data else {
                    return
                }
                
                do {
                    if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = jsonResponse["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        
                        
                        // Store the complete analysis results
                        let analysisResults: [String: Any] = [
                            "workout_id": workoutId,
                            "openai_feedback": content,
                            "timestamp": Date().timeIntervalSince1970,
                            "analysis_type": "mediapipe_openai"
                        ]
                        
                        // Store results in Firebase for the app to retrieve
                        self?.storeAnalysisResults(results: analysisResults, workoutId: workoutId)
                    }
                } catch {
                }
            }
        }.resume()
    }
    
    private func storeAnalysisResults(results: [String: Any], workoutId: String) {
        let storageRef = storage.reference()
        let resultsRef = storageRef.child("analysis-results/\(workoutId)/results.json")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: results)
            let metadata = StorageMetadata()
            metadata.contentType = "application/json"
            
            resultsRef.putData(jsonData, metadata: metadata) { metadata, error in
                DispatchQueue.main.async {
                    if let error = error {
                    } else {
                    }
                }
            }
        } catch {
        }
    }
    
    // MARK: - Results Retrieval
    
    func getAnalysisResults(workoutId: String) -> [String: Any]? {
        let storageRef = storage.reference()
        let resultsRef = storageRef.child("analysis-results/\(workoutId)/results.json")
        
        
        var results: [String: Any]?
        let semaphore = DispatchSemaphore(value: 0)
        
        resultsRef.getData(maxSize: 10 * 1024 * 1024) { data, error in
            if let error = error {
            } else if let data = data {
                do {
                    if let jsonResults = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        results = jsonResults
                    }
                } catch {
                }
            } else {
            }
            semaphore.signal()
        }
        
        let waitResult = semaphore.wait(timeout: .now() + 10.0)
        if waitResult == .timedOut {
        }
        return results
    }
    
    // MARK: - Legacy Methods (for backward compatibility)
    
    func callCloudAnalysis(downloadURL: String, workoutId: String, videoFileName: String) {
        // This now triggers the new architecture
        triggerMediaPipeAnalysis(downloadURL: downloadURL, workoutId: workoutId, videoFileName: videoFileName)
    }
    
    func triggerCloudAnalysis(workoutData: [String: Any], workoutId: String) {
        // This method is now handled by the new architecture
    }
} 