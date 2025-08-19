import Foundation

class CloudConfig: ObservableObject {
    static let shared = CloudConfig()
    
    @Published var cloudRunURL: String = "https://nodal-descent-467821-t2.uc.r.appspot.com"
    @Published var openAIAPIKey: String = "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"
    @Published var isConfigured: Bool = true
    
    private init() {
        loadConfiguration()
    }
    
    func configure(cloudRunURL: String, openAIAPIKey: String) {
        self.cloudRunURL = cloudRunURL
        self.openAIAPIKey = openAIAPIKey
        UserDefaults.standard.set(cloudRunURL, forKey: "CloudRunURL")
        UserDefaults.standard.set(openAIAPIKey, forKey: "OpenAIAPIKey")
        isConfigured = true
    }
    
    func getCloudRunURL() -> String? {
        return cloudRunURL.isEmpty ? nil : cloudRunURL
    }
    
    func getOpenAIAPIKey() -> String? {
        return openAIAPIKey.isEmpty ? nil : openAIAPIKey
    }
    
    private func loadConfiguration() {
        if let cloudRunURL = UserDefaults.standard.string(forKey: "CloudRunURL"),
           let openAIAPIKey = UserDefaults.standard.string(forKey: "OpenAIAPIKey") {
            self.cloudRunURL = cloudRunURL
            self.openAIAPIKey = openAIAPIKey
            isConfigured = true
        }
    }
    
    func clearConfiguration() {
        cloudRunURL = ""
        openAIAPIKey = ""
        UserDefaults.standard.removeObject(forKey: "CloudRunURL")
        UserDefaults.standard.removeObject(forKey: "OpenAIAPIKey")
        isConfigured = false
    }
    
    // MARK: - Legacy Support
    @Published var cloudFunctionURL: String = ""
    
    func configure(cloudFunctionURL: String) {
        self.cloudFunctionURL = cloudFunctionURL
        UserDefaults.standard.set(cloudFunctionURL, forKey: "CloudFunctionURL")
        isConfigured = true
    }
    
    func getCloudFunctionURL() -> String? {
        return cloudFunctionURL.isEmpty ? nil : cloudFunctionURL
    }
} 