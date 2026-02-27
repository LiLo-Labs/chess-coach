import Foundation
import ChessKit

actor LLMService: TextGenerating {
    private let config = LLMConfig()
    private var provider: LLMProvider = .claude
    private var onDeviceLLM: OnDeviceLLMService?
    private var fallbackAllowed: Bool = true
    /// Whether the on-device model has finished loading and is ready for inference.
    private(set) var isModelReady: Bool = false

    func detectProvider() async {
        let pref = UserDefaults.standard.string(forKey: AppSettings.Key.llmProvider) ?? "onDevice"
        switch pref {
        case "onDevice":
            provider = .onDevice
            fallbackAllowed = false
        case "ollama":
            provider = .ollama
            fallbackAllowed = false
            isModelReady = true  // No model to load
        case "claude":
            provider = .claude
            fallbackAllowed = false
            isModelReady = true  // No model to load
        default:
            provider = .onDevice
            fallbackAllowed = false
        }

        #if DEBUG
        print("[ChessCoach] LLM provider: \(provider)")
        #endif
    }

    /// Start loading the on-device model in the background.
    /// Call this early so the model is warm by the time the user needs coaching.
    func warmUp() async {
        guard provider == .onDevice else {
            isModelReady = true
            return
        }
        if onDeviceLLM == nil {
            onDeviceLLM = OnDeviceLLMService()
        }
        do {
            try await onDeviceLLM?.loadModel()
            isModelReady = true
            #if DEBUG
            print("[ChessCoach] On-device model warm-up complete")
            #endif
        } catch {
            #if DEBUG
            print("[ChessCoach] On-device model warm-up failed: \(error.localizedDescription)")
            #endif
        }
    }

    static func buildPrompt(for context: CoachingContext) -> String {
        let boardSummary = boardStateSummary(fen: context.fen)
        if context.isUserMove {
            return PromptCatalog.userMovePrompt(for: context, boardSummary: boardSummary)
        } else {
            return PromptCatalog.opponentMovePrompt(for: context, boardSummary: boardSummary)
        }
    }

    private static func pieceKindName(_ kind: PieceKind) -> String {
        switch kind {
        case .king: return "king"
        case .queen: return "queen"
        case .rook: return "rook"
        case .bishop: return "bishop"
        case .knight: return "knight"
        case .pawn: return "pawn"
        }
    }

    static func boardStateSummary(fen: String) -> String {
        let position = FenSerialization.default.deserialize(fen: fen)
        let pieces = position.board.enumeratedPieces()
        let white = pieces.filter { $0.1.color == .white }
            .map { "\(pieceKindName($0.1.kind)) on \($0.0.coordinate)" }
            .joined(separator: ", ")
        let black = pieces.filter { $0.1.color == .black }
            .map { "\(pieceKindName($0.1.kind)) on \($0.0.coordinate)" }
            .joined(separator: ", ")

        var lines = ["White: \(white)", "Black: \(black)"]

        // Add castling rights — helps model understand king safety
        let castlings = position.state.castlings
        var whiteCastle: [String] = []
        var blackCastle: [String] = []
        for c in castlings {
            if c.color == .white && c.kind == .king { whiteCastle.append("O-O") }
            if c.color == .white && c.kind == .queen { whiteCastle.append("O-O-O") }
            if c.color == .black && c.kind == .king { blackCastle.append("O-O") }
            if c.color == .black && c.kind == .queen { blackCastle.append("O-O-O") }
        }

        if let whiteKing = pieces.first(where: { $0.1.color == .white && $0.1.kind == .king }) {
            let castleStr = whiteCastle.isEmpty ? "" : ", can castle \(whiteCastle.joined(separator: " "))"
            lines.append("White king on \(whiteKing.0.coordinate)\(castleStr)")
        }
        if let blackKing = pieces.first(where: { $0.1.color == .black && $0.1.kind == .king }) {
            let castleStr = blackCastle.isEmpty ? "" : ", can castle \(blackCastle.joined(separator: " "))"
            lines.append("Black king on \(blackKing.0.coordinate)\(castleStr)")
        }

        return lines.joined(separator: "\n")
    }

    /// Returns a comma-separated list of squares that have pieces on them.
    /// Used in prompts to constrain REFS to valid squares only.
    static func occupiedSquares(fen: String) -> String {
        let position = FenSerialization.default.deserialize(fen: fen)
        return position.board.enumeratedPieces()
            .map { $0.0.coordinate }
            .sorted()
            .joined(separator: ", ")
    }

    func getCoaching(for context: CoachingContext) async throws -> String {
        let prompt = Self.buildPrompt(for: context)
        return try await callProvider(prompt: prompt, maxTokens: AppConfig.tokens.coaching, useThinking: false)
    }

    func getBatchedCoaching(for batched: BatchedCoachingContext) async throws -> BatchedCoachingResult {
        let prompt = Self.buildBatchedPrompt(for: batched)
        let raw = try await callProvider(prompt: prompt, maxTokens: AppConfig.tokens.batchedCoaching, useThinking: false)
        return Self.parseBatchedResponse(raw)
    }

    func getExplanation(prompt: String) async throws -> String {
        return try await callProvider(prompt: prompt, maxTokens: AppConfig.tokens.explanation, useThinking: false)
    }

    // MARK: - TextGenerating conformance

    func generate(prompt: String, maxTokens: Int) async throws -> String {
        try await callProvider(prompt: prompt, maxTokens: maxTokens, useThinking: false)
    }

    func generateWithThinking(prompt: String, maxTokens: Int) async throws -> String {
        try await callProvider(prompt: prompt, maxTokens: maxTokens, useThinking: true)
    }

    static func buildBatchedPrompt(for batched: BatchedCoachingContext) -> String {
        let userPrompt = buildPrompt(for: batched.userContext)
        let opponentPrompt = buildPrompt(for: batched.opponentContext)
        return PromptCatalog.batchedPrompt(userPrompt: userPrompt, opponentPrompt: opponentPrompt)
    }

    static func parseBatchedResponse(_ response: String) -> BatchedCoachingResult {
        // Split on STUDENT: and OPPONENT: markers
        var studentSection = ""
        var opponentSection = ""

        if let studentRange = response.range(of: "STUDENT:", options: .caseInsensitive),
           let opponentRange = response.range(of: "OPPONENT:", options: .caseInsensitive) {
            if studentRange.lowerBound < opponentRange.lowerBound {
                studentSection = String(response[studentRange.upperBound..<opponentRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                opponentSection = String(response[opponentRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                opponentSection = String(response[opponentRange.upperBound..<studentRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                studentSection = String(response[studentRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            // Couldn't parse sections — return whole response for both
            studentSection = response
            opponentSection = response
        }

        return BatchedCoachingResult(
            userCoaching: studentSection,
            opponentCoaching: opponentSection
        )
    }

    // MARK: - Private

    /// Try the current provider. If `fallbackAllowed` is true (user chose "onDevice" or default),
    /// fall back through the chain: onDevice → ollama → claude. If the user explicitly chose a
    /// provider ("ollama" or "claude"), errors are thrown immediately without fallback.
    private func callProvider(prompt: String, maxTokens: Int, useThinking: Bool) async throws -> String {
        // Try on-device first if selected
        if provider == .onDevice {
            do {
                return try await callOnDevice(prompt: prompt, maxTokens: maxTokens, useThinking: useThinking)
            } catch {
                guard fallbackAllowed else {
                    #if DEBUG
                    print("[ChessCoach] On-device LLM failed (no fallback): \(error.localizedDescription)")
                    #endif
                    throw error
                }
                #if DEBUG
                print("[ChessCoach] On-device LLM failed, trying Ollama: \(error.localizedDescription)")
                #endif
            }
        }

        // Try Ollama
        if provider == .onDevice || provider == .ollama {
            do {
                return try await callOllama(prompt: prompt, maxTokens: maxTokens)
            } catch {
                guard fallbackAllowed else {
                    #if DEBUG
                    print("[ChessCoach] Ollama failed (no fallback): \(error.localizedDescription)")
                    #endif
                    throw error
                }
                #if DEBUG
                print("[ChessCoach] Ollama failed, trying Claude: \(error.localizedDescription)")
                #endif
            }
        }

        // Try Claude
        do {
            return try await callClaude(prompt: prompt, maxTokens: maxTokens)
        } catch {
            #if DEBUG
            print("[ChessCoach] Claude failed: \(error.localizedDescription)")
            #endif
            throw error
        }
    }

    private func loadOnDeviceModel() async {
        if onDeviceLLM == nil {
            onDeviceLLM = OnDeviceLLMService()
        }
        do {
            try await onDeviceLLM?.loadModel()
        } catch {
            #if DEBUG
            print("[ChessCoach] Failed to load on-device model: \(error.localizedDescription)")
            #endif
            provider = .ollama
            #if DEBUG
            print("[ChessCoach] Falling back to Ollama")
            #endif
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
        guard let baseURL = config.ollamaBaseURL else {
            throw NSError(domain: "LLMService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Ollama URL"])
        }
        let url = baseURL.appendingPathComponent("api/chat")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = AppConfig.llm.ollamaTimeout

        let body: [String: Any] = [
            "model": config.ollamaModel,
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
        request.timeoutInterval = AppConfig.llm.claudeTimeout

        let body: [String: Any] = [
            "model": AppConfig.llm.claudeModel,
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
