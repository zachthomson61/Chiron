import Foundation
import FirebaseStorage
import FirebaseCore
import UIKit

class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()
    private let storage = Storage.storage()
    
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
        print("🔥 FirebaseManager: Starting video upload for workout: \(workoutId)")
        print("📁 Video file path: \(videoURL.path)")
        
        // Enhanced file checking
        let fileExists = FileManager.default.fileExists(atPath: videoURL.path)
        print("📁 Local file exists: \(fileExists)")
        
        guard fileExists else {
            print("❌ Video file does not exist at path: \(videoURL.path)")
            completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video file does not exist"])))
            return
        }
        
        // Check file size
        guard let fileSize = try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int64, fileSize > 0 else {
            print("❌ Video file is empty or cannot be read")
            completion(.failure(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video file is empty or cannot be read"])))
            return
        }
        
        print("📊 Local file size: \(fileSize) bytes")
        
        isUploading = true
        uploadProgress = 0.0
        
        let storageRef = storage.reference()
        let videoFileName = videoURL.lastPathComponent
        let videoRef = storageRef.child("workout-videos/\(workoutId)/\(videoFileName)")
        
        print("📤 Uploading to Firebase path: workout-videos/\(workoutId)/\(videoFileName)")
        
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        
        // Add a delay to ensure file is fully written and accessible
        print("⏳ Waiting 2 seconds before starting Firebase upload...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("🚀 Starting Firebase upload after delay...")
            let uploadTask = videoRef.putFile(from: videoURL, metadata: metadata) { [weak self] metadata, error in
                DispatchQueue.main.async {
                    self?.isUploading = false
                    
                    if let error = error {
                        print("❌ Firebase upload failed: \(error.localizedDescription)")
                        print("❌ Error details: \(error)")
                        
                        // Try again with a delay if it's a file access error
                        if (error as NSError).domain == "FIRStorageErrorDomain" && (error as NSError).code == -13021 {
                            print("🔄 Retrying upload with delay...")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                self?.retryUpload(videoURL: videoURL, videoRef: videoRef, metadata: metadata ?? StorageMetadata(), workoutId: workoutId, videoFileName: videoFileName, completion: completion)
                            }
                        } else {
                            completion(.failure(error))
                        }
                        return
                    }
                    
                    print("✅ Firebase upload completed successfully")
                    
                    // Get download URL
                    videoRef.downloadURL { url, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                print("❌ Failed to get download URL: \(error.localizedDescription)")
                                completion(.failure(error))
                            } else if let downloadURL = url {
                                print("🔗 Download URL obtained: \(downloadURL.absoluteString)")
                                // Trigger the new architecture flow
                                self?.triggerMediaPipeAnalysis(downloadURL: downloadURL.absoluteString, workoutId: workoutId, videoFileName: videoFileName)
                                completion(.success(downloadURL.absoluteString))
                            } else {
                                print("❌ Download URL is nil")
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
                    print("📊 Upload progress: \(Int(progress * 100))%")
                }
            }
        }
    }
    
    private func retryUpload(videoURL: URL, videoRef: StorageReference, metadata: StorageMetadata, workoutId: String, videoFileName: String, completion: @escaping (Result<String, Error>) -> Void) {
        print("🔄 Retrying Firebase upload...")
        
        let retryTask = videoRef.putFile(from: videoURL, metadata: metadata) { [weak self] metadata, error in
            DispatchQueue.main.async {
                self?.isUploading = false
                
                if let error = error {
                    print("❌ Firebase retry upload failed: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                print("✅ Firebase retry upload completed successfully")
                
                // Get download URL
                videoRef.downloadURL { url, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("❌ Failed to get download URL: \(error.localizedDescription)")
                            completion(.failure(error))
                        } else if let downloadURL = url {
                            print("🔗 Download URL obtained: \(downloadURL.absoluteString)")
                            // Trigger the new architecture flow
                            self?.triggerMediaPipeAnalysis(downloadURL: downloadURL.absoluteString, workoutId: workoutId, videoFileName: videoFileName)
                            completion(.success(downloadURL.absoluteString))
                        } else {
                            print("❌ Download URL is nil")
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
                print("📊 Retry upload progress: \(Int(progress * 100))%")
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
        print("🤖 Triggering MediaPipe analysis for workout: \(workoutId)")
        print("🔗 Video URL: \(downloadURL)")
        
        // Prepare request for Cloud Run MediaPipe service
        let analysisRequest: [String: Any] = [
            "video_url": downloadURL,
            "workout_id": workoutId,
            "video_file_name": videoFileName,
            "exercise_type": "squat", // Can be made configurable
            "timestamp": Date().timeIntervalSince1970
        ]
        
        print("📤 Sending request to Cloud Run: \(analysisRequest)")
        callCloudRunMediaPipe(request: analysisRequest, workoutId: workoutId)
    }
    
    private func callCloudRunMediaPipe(request: [String: Any], workoutId: String) {
        print("🌐 Calling Cloud Run MediaPipe service")
        
        guard let url = URL(string: "\(cloudRunURL)/analyze-pose") else {
            print("❌ Invalid Cloud Run URL: \(cloudRunURL)")
            return
        }
        
        print("🔗 Cloud Run URL: \(url)")
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: request)
            print("✅ Request body serialized successfully")
        } catch {
            print("❌ Error serializing request: \(error)")
            return
        }
        
        print("📡 Making HTTP request to Cloud Run...")
        
        URLSession.shared.dataTask(with: urlRequest) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Cloud Run MediaPipe error: \(error)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("📡 HTTP Response Status: \(httpResponse.statusCode)")
                }
                
                guard let data = data else {
                    print("❌ No data received from Cloud Run")
                    return
                }
                
                print("📦 Received \(data.count) bytes from Cloud Run")
                
                do {
                    if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("✅ MediaPipe analysis completed: \(jsonResponse)")
                        // Trigger OpenAI analysis with MediaPipe results
                        self?.triggerOpenAIAnalysis(mediaPipeResults: jsonResponse, workoutId: workoutId)
                    }
                } catch {
                    print("❌ Error parsing Cloud Run response: \(error)")
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("📄 Raw response: \(responseString)")
                    }
                }
            }
        }.resume()
    }
    
    private func triggerOpenAIAnalysis(mediaPipeResults: [String: Any], workoutId: String) {
        print("Triggering OpenAI analysis for workout: \(workoutId)")
        
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
            print("Invalid OpenAI API URL")
            return
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")
        
        do {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: request)
        } catch {
            print("Error serializing OpenAI request: \(error)")
            return
        }
        
        URLSession.shared.dataTask(with: urlRequest) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("OpenAI API error: \(error)")
                    return
                }
                
                guard let data = data else {
                    print("No data received from OpenAI")
                    return
                }
                
                do {
                    if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = jsonResponse["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        
                        print("OpenAI analysis completed")
                        
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
                    print("Error parsing OpenAI response: \(error)")
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
                        print("Error storing analysis results: \(error)")
                    } else {
                        print("Analysis results stored successfully for workout: \(workoutId)")
                    }
                }
            }
        } catch {
            print("Error serializing analysis results: \(error)")
        }
    }
    
    // MARK: - Results Retrieval
    
    func getAnalysisResults(workoutId: String) -> [String: Any]? {
        let storageRef = storage.reference()
        let resultsRef = storageRef.child("analysis-results/\(workoutId)/results.json")
        
        print("🔍 Attempting to retrieve analysis results for workout: \(workoutId)")
        print("📁 Looking for file at: analysis-results/\(workoutId)/results.json")
        
        var results: [String: Any]?
        let semaphore = DispatchSemaphore(value: 0)
        
        resultsRef.getData(maxSize: 10 * 1024 * 1024) { data, error in
            if let error = error {
                print("❌ Error retrieving analysis results: \(error)")
                print("❌ Error details: \(error.localizedDescription)")
            } else if let data = data {
                print("📦 Received \(data.count) bytes of analysis data")
                do {
                    if let jsonResults = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        results = jsonResults
                        print("✅ Successfully retrieved analysis results for workout: \(workoutId)")
                        print("📊 Results keys: \(jsonResults.keys)")
                    }
                } catch {
                    print("❌ Error parsing analysis results: \(error)")
                }
            } else {
                print("❌ No data received for analysis results")
            }
            semaphore.signal()
        }
        
        let waitResult = semaphore.wait(timeout: .now() + 10.0)
        if waitResult == .timedOut {
            print("❌ Timeout waiting for analysis results")
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
        print("Cloud analysis triggered via new architecture")
    }
} 