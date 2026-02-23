import Foundation

actor LLMService {
    private let config = LLMConfig()
    private var provider: LLMProvider = .claude
    private var onDeviceLLM: OnDeviceLLMService?

    func detectProvider() async {
        let pref = UserDefaults.standard.string(forKey: "llm_provider_preference") ?? "auto"
        switch pref {
        case "onDevice":
            provider = .onDevice
        case "ollama":
            provider = .ollama
        case "claude":
            provider = .claude
        default:
            provider = await config.detectProvider()
        }

        // Don't pre-load on-device model — it's loaded lazily on first callProvider()
        // to avoid blocking session start with a 2.5GB model load.
        print("[ChessCoach] LLM provider: \(provider)")
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
        let studentColor = context.studentColor ?? "White"

        return """
        You are a friendly chess coach teaching a \(level) (ELO ~\(context.userELO)).
        The student plays \(studentColor). When you say "you" or "your", always mean the student (\(studentColor)).
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
        return try await callProvider(prompt: prompt, maxTokens: 200, useThinking: false)
    }

    func getExplanation(prompt: String) async throws -> String {
        return try await callProvider(prompt: prompt, maxTokens: 500, useThinking: true)
    }

    // MARK: - Private

    /// Try the current provider, fall back through the chain: onDevice → ollama → claude
    private func callProvider(prompt: String, maxTokens: Int, useThinking: Bool) async throws -> String {
        var lastError: Error?

        // Try on-device first if selected
        if provider == .onDevice {
            do {
                return try await callOnDevice(prompt: prompt, maxTokens: maxTokens, useThinking: useThinking)
            } catch {
                print("[ChessCoach] On-device LLM failed, trying Ollama: \(error.localizedDescription)")
                lastError = error
            }
        }

        // Try Ollama
        if provider == .onDevice || provider == .ollama {
            do {
                return try await callOllama(prompt: prompt, maxTokens: maxTokens)
            } catch {
                print("[ChessCoach] Ollama failed, trying Claude: \(error.localizedDescription)")
                lastError = error
            }
        }

        // Try Claude
        do {
            return try await callClaude(prompt: prompt, maxTokens: maxTokens)
        } catch {
            print("[ChessCoach] Claude failed: \(error.localizedDescription)")
            throw lastError ?? error
        }
    }

    private func loadOnDeviceModel() async {
        if onDeviceLLM == nil {
            onDeviceLLM = OnDeviceLLMService()
        }
        do {
            try await onDeviceLLM?.loadModel()
        } catch {
            print("[ChessCoach] Failed to load on-device model: \(error.localizedDescription)")
            provider = .ollama
            print("[ChessCoach] Falling back to Ollama")
        }
    }

    private func callOnDevice(prompt: String, maxTokens: Int, useThinking: Bool) async throws -> String {
        // Lazy-load the model on first use
        if onDeviceLLM == nil {
            onDeviceLLM = OnDeviceLLMService()
        }
        guard let onDeviceLLM else {
            throw OnDeviceLLMError.modelNotLoaded
        }
        try await onDeviceLLM.loadModel()
        return try await onDeviceLLM.generate(prompt: prompt, maxTokens: maxTokens, useThinking: useThinking)
    }

    /// Current provider for display in settings
    var currentProvider: LLMProvider { provider }

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
        guard let text = resp.content.first?.text, !text.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return text
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
