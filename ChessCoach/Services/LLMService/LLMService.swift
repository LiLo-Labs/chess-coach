import Foundation
import ChessKit

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
        if context.isUserMove {
            return buildUserMovePrompt(for: context)
        } else {
            return buildOpponentMovePrompt(for: context)
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
        return "White pieces: \(white)\nBlack pieces: \(black)"
    }

    private static func levelString(elo: Int) -> String {
        switch elo {
        case ..<600: return "complete beginner"
        case ..<800: return "beginner"
        case ..<1000: return "improving beginner"
        default: return "intermediate"
        }
    }

    /// Prompt for when the STUDENT just made a move
    private static func buildUserMovePrompt(for context: CoachingContext) -> String {
        let level = levelString(elo: context.userELO)
        let studentColor = context.studentColor ?? "White"

        let feedback: String
        switch context.moveCategory {
        case .goodMove:
            feedback = "The student played the correct \(context.openingName) move (\(context.lastMove)). Tell them why this move is good in the \(context.openingName) — what plan or idea does it serve?"
        case .okayMove:
            let expected = context.expectedMoveSAN ?? "the book move"
            feedback = "The student played \(context.lastMove), which is playable but not the \(context.openingName) main line. The book move was \(expected). Briefly explain why \(expected) is preferred in this system."
        case .mistake:
            let expected = context.expectedMoveSAN ?? "the book move"
            let explanation = context.expectedMoveExplanation ?? ""
            feedback = "The student played \(context.lastMove), deviating from the \(context.openingName). The book move was \(expected). \(explanation) Gently explain what they should have played and why."
        default:
            feedback = ""
        }

        return """
        You are a chess coach. Your student (ELO ~\(context.userELO), \(level)) is learning the \(context.openingName) as \(studentColor).
        System: \(context.openingName) — \(context.openingDescription)
        Main line so far: \(context.mainLineSoFar)

        The student just played: \(context.lastMove) (move \(context.plyNumber / 2 + 1))

        Current board position:
        \(boardStateSummary(fen: context.fen))

        \(feedback)

        Response format (REQUIRED):
        REFS: <list each piece and square you mention, e.g. "bishop e5, knight c3". Write "none" if you don't reference specific pieces>
        COACHING: <your coaching text>

        Rules:
        - ONLY reference pieces that exist on the squares listed above.
        - REFS must exactly match pieces you mention in COACHING.
        - Address the student as "you". You are talking TO the student about THEIR move.
        - ONE or TWO short sentences (max 25 words total).
        - Relate advice to the \(context.openingName) system.
        - Use simple language. Spell out piece names, no algebraic notation.
        """
    }

    /// Prompt for when the OPPONENT just made a move
    private static func buildOpponentMovePrompt(for context: CoachingContext) -> String {
        let level = levelString(elo: context.userELO)
        let studentColor = context.studentColor ?? "White"

        let guidance: String
        if context.moveCategory == .deviation {
            guidance = "The opponent deviated from the expected \(context.openingName) line by playing \(context.lastMove). Explain that the student is now out of book and suggest how to adapt while keeping the \(context.openingName) ideas."
        } else {
            let explanation = context.expectedMoveExplanation ?? ""
            guidance = "The opponent played \(context.lastMove). Explain WHY the opponent wants to make this move — what is the opponent trying to achieve? \(explanation) Help the student understand the opponent's reasoning so they can anticipate it in future games."
        }

        return """
        You are a chess coach. Your student (ELO ~\(context.userELO), \(level)) is learning the \(context.openingName) as \(studentColor).
        System: \(context.openingName) — \(context.openingDescription)
        Main line so far: \(context.mainLineSoFar)

        The OPPONENT just played: \(context.lastMove) (move \(context.plyNumber / 2 + 1))

        Current board position:
        \(boardStateSummary(fen: context.fen))

        \(guidance)

        Response format (REQUIRED):
        REFS: <list each piece and square you mention, e.g. "bishop e5, knight c3". Write "none" if you don't reference specific pieces>
        COACHING: <your coaching text>

        Rules:
        - ONLY reference pieces that exist on the squares listed above.
        - REFS must exactly match pieces you mention in COACHING.
        - Address the student as "you". Say "your opponent" or "they" for the other side.
        - When naming pieces, always specify the color: "\(studentColor == "White" ? "Black" : "White")'s knight" not just "the knight".
        - Frame it like: "Your opponent plays ... because they want to ..." or "They're aiming to ..."
        - ONE or TWO short sentences (max 25 words total).
        - Relate to the \(context.openingName) system.
        - Use simple language. Spell out piece names, no algebraic notation.
        """
    }

    func getCoaching(for context: CoachingContext) async throws -> String {
        let prompt = Self.buildPrompt(for: context)
        return try await callProvider(prompt: prompt, maxTokens: 200, useThinking: false)
    }

    func getBatchedCoaching(for batched: BatchedCoachingContext) async throws -> BatchedCoachingResult {
        let prompt = Self.buildBatchedPrompt(for: batched)
        let raw = try await callProvider(prompt: prompt, maxTokens: 400, useThinking: false)
        return Self.parseBatchedResponse(raw)
    }

    func getExplanation(prompt: String) async throws -> String {
        return try await callProvider(prompt: prompt, maxTokens: 500, useThinking: true)
    }

    static func buildBatchedPrompt(for batched: BatchedCoachingContext) -> String {
        let userPrompt = buildPrompt(for: batched.userContext)
        let opponentPrompt = buildPrompt(for: batched.opponentContext)

        return """
        You will provide coaching for TWO consecutive moves. Respond with BOTH sections.

        === MOVE 1 (Student's move) ===
        \(userPrompt)

        === MOVE 2 (Opponent's response) ===
        \(opponentPrompt)

        IMPORTANT: Format your response EXACTLY as:
        STUDENT:
        REFS: <piece references or "none">
        COACHING: <coaching text>
        OPPONENT:
        REFS: <piece references or "none">
        COACHING: <coaching text>
        """
    }

    static func parseBatchedResponse(_ response: String) -> BatchedCoachingResult {
        let upper = response.uppercased()

        // Split on STUDENT: and OPPONENT: markers
        var studentSection = ""
        var opponentSection = ""

        if let studentRange = upper.range(of: "STUDENT:"),
           let opponentRange = upper.range(of: "OPPONENT:") {
            let studentStart = response.index(studentRange.upperBound, offsetBy: 0)
            let opponentStart = response.index(opponentRange.upperBound, offsetBy: 0)

            if studentRange.lowerBound < opponentRange.lowerBound {
                studentSection = String(response[studentStart..<opponentRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                opponentSection = String(response[opponentStart...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                opponentSection = String(response[opponentStart..<studentRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                studentSection = String(response[studentStart...])
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
        request.timeoutInterval = 10

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
