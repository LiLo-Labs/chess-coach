import Foundation

actor LLMService {
    private let config = LLMConfig()
    private var provider: LLMProvider = .claude

    func detectProvider() async {
        let pref = UserDefaults.standard.string(forKey: "llm_provider_preference") ?? "auto"
        switch pref {
        case "ollama":
            provider = .ollama
        case "claude":
            provider = .claude
        default:
            provider = await config.detectProvider()
        }
    }

    static func buildPrompt(for context: CoachingContext) -> String {
        let level: String
        switch context.userELO {
        case ..<600: level = "complete beginner"
        case ..<800: level = "beginner"
        case ..<1000: level = "improving beginner"
        default: level = "intermediate"
        }

        let change = context.scoreAfter - context.scoreBefore

        let categoryInstruction: String
        switch context.moveCategory {
        case .goodMove:
            categoryInstruction = "The player made a good move. Explain WHY it's strong — what does it control, threaten, or set up? Be specific and encouraging."
        case .okayMove:
            categoryInstruction = "The player made an okay but not optimal move. Gently suggest what might be better without being discouraging."
        case .mistake:
            categoryInstruction = "The player made a mistake. Explain what went wrong and what would have been better. Be encouraging."
        case .opponentMove:
            categoryInstruction = "Explain the opponent's move and what threats or ideas it creates. Help the player understand how to respond."
        case .deviation:
            categoryInstruction = "The opponent deviated from the expected opening line. Explain what changed and how the player should adapt their plan."
        }

        let whoMoved = context.isUserMove ? "the student's move" : "the opponent's move"

        return """
        You are a friendly chess coach teaching a \(level) (ELO ~\(context.userELO)).
        Opening: \(context.openingName)
        Moves so far: \(context.moveHistory)
        Position after move (FEN): \(context.fen)
        Last move played: \(context.lastMove) — this was \(whoMoved)
        Score change: \(change > 0 ? "+" : "")\(change) centipawns

        \(categoryInstruction)

        Give ONE short sentence (max 15 words) explaining why this move matters.
        Use simple language. Reference concrete pieces and squares.
        Do not use chess notation symbols. Spell out piece names.
        Do not start with "This move" or "The move".
        """
    }

    func getCoaching(for context: CoachingContext) async throws -> String {
        let prompt = Self.buildPrompt(for: context)
        switch provider {
        case .ollama:
            return try await callOllama(prompt: prompt)
        case .claude:
            return try await callClaude(prompt: prompt)
        }
    }

    func getExplanation(prompt: String) async throws -> String {
        switch provider {
        case .ollama:
            return try await callOllama(prompt: prompt, maxTokens: 500)
        case .claude:
            return try await callClaude(prompt: prompt, maxTokens: 500)
        }
    }

    private func callOllama(prompt: String, maxTokens: Int = 200) async throws -> String {
        let url = config.ollamaBaseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": "qwen2.5:7b",
            "messages": [["role": "user", "content": prompt]],
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let resp = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return resp.message.content
    }

    private func callClaude(prompt: String, maxTokens: Int = 200) async throws -> String {
        let url = config.claudeBaseURL.appendingPathComponent("v1/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.claudeAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let resp = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        return resp.content.first?.text ?? ""
    }
}

struct OllamaResponse: Codable {
    struct Message: Codable {
        let content: String
    }
    let message: Message
}

struct ClaudeResponse: Codable {
    struct Content: Codable {
        let text: String
    }
    let content: [Content]
}
