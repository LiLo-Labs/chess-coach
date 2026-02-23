import Foundation

struct LLMConfig: Sendable {
    var ollamaBaseURL: URL { URL(string: "http://192.168.4.62:11434")! }
    var claudeBaseURL: URL { URL(string: "https://api.anthropic.com")! }

    var claudeAPIKey: String {
        UserDefaults.standard.string(forKey: "claude_api_key") ?? ""
    }

    func detectProvider() async -> LLMProvider {
        let url = ollamaBaseURL.appendingPathComponent("api/tags")
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.0
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                return .ollama
            }
        } catch {
            print("[ChessCoach] Ollama not reachable: \(error.localizedDescription)")
        }
        return .claude
    }
}
