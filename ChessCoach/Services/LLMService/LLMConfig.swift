import Foundation

struct LLMConfig: Sendable {
    var ollamaBaseURL: URL? {
        let host = UserDefaults.standard.string(forKey: AppSettings.Key.ollamaHost) ?? AppConfig.llm.defaultOllamaHost
        // Strip any scheme the user may have entered (e.g. "http://...")
        let cleaned = host
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
        return URL(string: "http://\(cleaned)")
    }
    var ollamaModel: String {
        UserDefaults.standard.string(forKey: AppSettings.Key.ollamaModel) ?? AppConfig.llm.defaultOllamaModel
    }
    var claudeBaseURL: URL { AppConfig.llm.claudeBaseURL }

    var claudeAPIKey: String {
        KeychainService.load(key: "claude_api_key") ?? ""
    }

    /// Detect the best available provider, in priority order:
    /// on-device → Ollama → Claude
    func detectProvider() async -> LLMProvider {
        if OnDeviceLLMService.isModelAvailable {
            return .onDevice
        }

        if let baseURL = ollamaBaseURL {
            let url = baseURL.appendingPathComponent("api/tags")
            var req = URLRequest(url: url)
            req.timeoutInterval = 2.0
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                    return .ollama
                }
            } catch {
                #if DEBUG
                print("[ChessCoach] Ollama not reachable: \(error.localizedDescription)")
                #endif
            }
        }
        return .claude
    }
}
