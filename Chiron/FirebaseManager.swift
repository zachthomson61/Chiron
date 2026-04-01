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
    // OpenAI API key removed — the cloud service now handles LLM phrasing directly.
    
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
    
    /// Calls Cloud Run `/analyze-pose` which now runs the full pipeline:
    /// pose → metrics → flags → ranked issues → phrasing payload → LLM phrasing.
    /// The cloud returns `feedback` (already phrased), `issues` (stable IDs), and metrics.
    /// No second LLM call is needed — the cloud handles everything.
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
                guard error == nil, let data = data else { return }

                do {
                    if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let analysisResults: [String: Any] = [
                            "workout_id": workoutId,
                            "openai_feedback": jsonResponse["feedback"] as? String ?? "",
                            "issues": jsonResponse["issues"] as? [String] ?? [],
                            "phrasing_payload": jsonResponse["phrasing_payload"] as? [String: Any] ?? [:],
                            "form_score": jsonResponse["form_score"] as? Double ?? 0.0,
                            "rep_count": jsonResponse["rep_count"] as? Int ?? 0,
                            "timestamp": Date().timeIntervalSince1970,
                            "analysis_type": "mediapipe_phrasing_pipeline"
                        ]
                        self?.storeAnalysisResults(results: analysisResults, workoutId: workoutId)
                    }
                } catch { }
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
            
            resultsRef.putData(jsonData, metadata: metadata) { _, _ in }
        } catch { }
    }
    
    // MARK: - Results Retrieval
    
    func getAnalysisResults(workoutId: String) -> [String: Any]? {
        let storageRef = storage.reference()
        let resultsRef = storageRef.child("analysis-results/\(workoutId)/results.json")
        
        
        var results: [String: Any]?
        let semaphore = DispatchSemaphore(value: 0)
        
        resultsRef.getData(maxSize: 10 * 1024 * 1024) { data, error in
            if error == nil, let data = data {
                do {
                    if let jsonResults = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        results = jsonResults
                    }
                } catch { }
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 10.0)
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