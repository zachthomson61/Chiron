import SwiftUI

struct CloudConfigView: View {
    @ObservedObject var cloudConfig = CloudConfig.shared
    @State private var cloudRunURL: String = ""
    @State private var openAIAPIKey: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                // Dark background
                Color(red: 18/255, green: 32/255, blue: 47/255)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Cloud Configuration")
                            .font(.neueMontrealBold(size: 34))
                            .foregroundColor(.white)
                        Text("Configure your Cloud Run and OpenAI API settings")
                            .font(.neueMontrealRegular(size: 15))
                            .foregroundColor(.gray)
                    }
                    .padding(.top)
                    
                    // Configuration Form
                    VStack(spacing: 20) {
                        // Cloud Run Configuration
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Cloud Run URL")
                                .font(.neueMontrealBold(size: 17))
                                .foregroundColor(.white)
                            TextField("https://your-service.run.app", text: $cloudRunURL)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            Text("Your Cloud Run service URL for MediaPipe pose analysis")
                                .font(.neueMontrealRegular(size: 12))
                                .foregroundColor(.gray)
                        }
                        
                        // OpenAI API Configuration
                        VStack(alignment: .leading, spacing: 8) {
                            Text("OpenAI API Key")
                                .font(.neueMontrealBold(size: 17))
                                .foregroundColor(.white)
                            SecureField("sk-...", text: $openAIAPIKey)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            Text("Your OpenAI API key for LLM feedback generation")
                                .font(.neueMontrealRegular(size: 12))
                                .foregroundColor(.gray)
                        }
                        
                        // Architecture Diagram
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Architecture Flow")
                                .font(.neueMontrealBold(size: 17))
                                .foregroundColor(.white)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                ArchitectureStep(number: "1", title: "iOS App", description: "Capture Video")
                                ArchitectureStep(number: "2", title: "Firebase Storage", description: "Upload Video")
                                ArchitectureStep(number: "3", title: "Cloud Run", description: "MediaPipe Pose Extraction")
                                ArchitectureStep(number: "4", title: "OpenAI API", description: "LLM Feedback Generation")
                                ArchitectureStep(number: "5", title: "App", description: "Voice + Visual Feedback")
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button(action: saveConfiguration) {
                            Text("Save Configuration")
                                .font(.neueMontrealSemiBold(size: 17))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                        
                        Button(action: testConfiguration) {
                            Text("Test Configuration")
                                .font(.neueMontrealSemiBold(size: 17))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.green)
                                .cornerRadius(12)
                        }
                        
                        Button(action: clearConfiguration) {
                            Text("Clear Configuration")
                                .font(.neueMontrealSemiBold(size: 17))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.red)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            loadCurrentConfiguration()
        }
        .alert("Configuration", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func loadCurrentConfiguration() {
        cloudRunURL = cloudConfig.cloudRunURL
        openAIAPIKey = cloudConfig.openAIAPIKey
    }
    
    private func saveConfiguration() {
        guard !cloudRunURL.isEmpty else {
            alertMessage = "Please enter a Cloud Run URL"
            showingAlert = true
            return
        }
        
        guard !openAIAPIKey.isEmpty else {
            alertMessage = "Please enter an OpenAI API key"
            showingAlert = true
            return
        }
        
        cloudConfig.configure(cloudRunURL: cloudRunURL, openAIAPIKey: openAIAPIKey)
        alertMessage = "Configuration saved successfully!"
        showingAlert = true
    }
    
    private func testConfiguration() {
        guard cloudConfig.isConfigured else {
            alertMessage = "Please save configuration first"
            showingAlert = true
            return
        }
        
        // Test Cloud Run connection
        testCloudRunConnection()
    }
    
    private func testCloudRunConnection() {
        guard let url = URL(string: "\(cloudConfig.cloudRunURL)/health") else {
            alertMessage = "Invalid Cloud Run URL"
            showingAlert = true
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    alertMessage = "Cloud Run test failed: \(error.localizedDescription)"
                } else if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        alertMessage = "Configuration test successful! Cloud Run is accessible."
                    } else {
                        alertMessage = "Cloud Run test failed: Status \(httpResponse.statusCode)"
                    }
                } else {
                    alertMessage = "Cloud Run test failed: No response"
                }
                showingAlert = true
            }
        }.resume()
    }
    
    private func clearConfiguration() {
        cloudConfig.clearConfiguration()
        cloudRunURL = ""
        openAIAPIKey = ""
        alertMessage = "Configuration cleared"
        showingAlert = true
    }
}

struct ArchitectureStep: View {
    let number: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 30, height: 30)
                Text(number)
                    .font(.neueMontrealBold(size: 12))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.neueMontrealSemiBold(size: 15))
                    .foregroundColor(.white)
                Text(description)
                    .font(.neueMontrealRegular(size: 12))
                    .foregroundColor(.gray)
            }
            
            Spacer()
        }
    }
}

#Preview {
    CloudConfigView()
} 