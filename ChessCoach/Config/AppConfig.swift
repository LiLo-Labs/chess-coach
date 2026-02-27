import Foundation

/// Single source of truth for all tuning parameters, thresholds, and magic numbers.
/// Organised as nested structs under an uninhabited enum so nothing is accidentally instantiated.
enum AppConfig {

    // MARK: - LLM

    struct LLM: Sendable {
        let claudeModel: String
        let claudeBaseURL: URL
        let defaultOllamaHost: String
        let defaultOllamaModel: String
        let onDeviceModelFilename: String
        let contextSize: UInt32

        // Thinking mode (enable_thinking=True) per Qwen3 docs
        let thinkingTemperature: Float
        let thinkingTopP: Float
        let thinkingTopK: Int32
        let thinkingMinP: Float

        // Non-thinking mode (enable_thinking=False) per Qwen3 docs
        let temperature: Float
        let topP: Float
        let topK: Int32
        let minP: Float

        /// Presence penalty (0.0–2.0) — helps prevent repetition
        let presencePenalty: Float

        let claudeTimeout: TimeInterval
        let ollamaTimeout: TimeInterval

        let onDeviceSystemMessage: String
    }

    static let llm = LLM(
        claudeModel: "claude-sonnet-4-20250514",
        claudeBaseURL: URL(string: "https://api.anthropic.com")!,
        defaultOllamaHost: "192.168.4.62:11434",
        defaultOllamaModel: "qwen2.5:7b",
        onDeviceModelFilename: "Qwen3-4B-Q4_K_M",
        contextSize: 4096,
        thinkingTemperature: 0.6,
        thinkingTopP: 0.95,
        thinkingTopK: 20,
        thinkingMinP: 0.0,
        temperature: 0.7,
        topP: 0.8,
        topK: 20,
        minP: 0.0,
        presencePenalty: 0.0,
        claudeTimeout: 30,
        ollamaTimeout: 10,
        onDeviceSystemMessage: "You are a chess coach."
    )

    // MARK: - Engine (Stockfish)

    struct Engine: Sendable {
        let searchTimeout: TimeInterval
        let readyTimeout: TimeInterval
        let defaultDepth: Int

        /// Fixed depths for specific engine tasks
        let opponentMoveDepth: Int
        let evalDepth: Int
        let hintDepth: Int
        let pesTopMovesDepth: Int

        /// Scales Stockfish search depth by student ELO — beginners get a more
        /// forgiving evaluation while stronger players are held to a higher standard.
        func depthForELO(_ elo: Int) -> Int {
            switch elo {
            case ..<600:  return 8
            case ..<800:  return 10
            case ..<1000: return 12
            case ..<1200: return 14
            default:      return 16
            }
        }
    }

    static let engine = Engine(
        searchTimeout: 5,
        readyTimeout: 10,
        defaultDepth: 15,
        opponentMoveDepth: 10,
        evalDepth: 12,
        hintDepth: 12,
        pesTopMovesDepth: 12
    )

    // MARK: - Maia

    struct Maia: Sendable {
        let modelResourceName: String
        let movesResourceName: String
        let expectedMoveCount: Int

        /// Map ELO to Maia 2 bucket index (0-10).
        /// <1100: 0, 1100-1199: 1, ..., >=2000: 10
        func eloToBucket(_ elo: Int) -> Int32 {
            if elo < 1100 { return 0 }
            if elo >= 2000 { return 10 }
            return Int32((elo - 1100) / 100 + 1)
        }
    }

    static let maia = Maia(
        modelResourceName: "Maia2Blitz",
        movesResourceName: "maia2_moves",
        expectedMoveCount: 1880
    )

    // MARK: - Scoring (Soundness + Popularity)

    struct Scoring: Sendable {
        /// Soundness tolerance curve parameters.
        /// Linear interpolation: minELO → maxTolerance, maxELO → minTolerance.
        let toleranceMinELO: Int
        let toleranceMaxELO: Int
        let toleranceAtMinELO: Double
        let toleranceAtMaxELO: Double

        /// Compute the ELO-scaled tolerance for centipawn loss.
        func toleranceForELO(_ elo: Int) -> Double {
            let clamped = Double(max(toleranceMinELO, min(toleranceMaxELO, elo)))
            let slope = (toleranceAtMinELO - toleranceAtMaxELO) / Double(toleranceMaxELO - toleranceMinELO)
            return toleranceAtMinELO - (clamped - Double(toleranceMinELO)) * slope
        }

        // Popularity adjustment bounds
        let popularityNotInBook: Int
        let popularityTopMove: Int
        let popularityTop3Move: Int
        let popularityRareMove: Int
    }

    static let scoring = Scoring(
        toleranceMinELO: 400,
        toleranceMaxELO: 1400,
        toleranceAtMinELO: 130.0,
        toleranceAtMaxELO: 50.0,
        popularityNotInBook: -5,
        popularityTopMove: 10,
        popularityTop3Move: 5,
        popularityRareMove: 2
    )

    // MARK: - Learning Phase Thresholds

    struct Learning: Sendable {
        struct PhaseThreshold: Sendable {
            let promotionThreshold: Double?
            let minimumGames: Int?
        }

        let learningMainLine: PhaseThreshold
        let naturalDeviations: PhaseThreshold
        let widerVariations: PhaseThreshold
        let freePlay: PhaseThreshold

        func threshold(for phase: LearningPhase) -> PhaseThreshold {
            switch phase {
            case .learningMainLine: return learningMainLine
            case .naturalDeviations: return naturalDeviations
            case .widerVariations: return widerVariations
            case .freePlay: return freePlay
            }
        }
    }

    static let learning = Learning(
        learningMainLine: .init(promotionThreshold: 60, minimumGames: 3),
        naturalDeviations: .init(promotionThreshold: 70, minimumGames: 5),
        widerVariations: .init(promotionThreshold: 75, minimumGames: 8),
        freePlay: .init(promotionThreshold: nil, minimumGames: nil)
    )

    // MARK: - Pro / Subscription

    struct Pro: Sendable {
        let productID: String
        let freeOpeningIDs: Set<String>
    }

    static let pro = Pro(
        productID: "com.chesscoach.pro.lifetime",
        freeOpeningIDs: ["italian", "london", "sicilian"]
    )

    // MARK: - Coaching

    struct Coaching: Sendable {
        /// Map student ELO to a human-readable level label used in prompts.
        func levelString(elo: Int) -> String {
            switch elo {
            case ..<600:  return "complete beginner"
            case ..<800:  return "beginner"
            case ..<1000: return "improving beginner"
            default:      return "intermediate"
            }
        }

        // Fallback coaching templates (free tier)
        let goodMoveTemplate: String
        let okayMoveTemplate: String
        let mistakeMoveTemplate: String
        let deviationTemplate: String
        let standardOpponentTemplate: String
    }

    static let coaching = Coaching(
        goodMoveTemplate: "Good move! That follows the %@ game plan.",
        okayMoveTemplate: "Playable, but %@ is the recommended move here.",
        mistakeMoveTemplate: "The recommended move here is %@.",
        deviationTemplate: "Your opponent went off the plan. Stay calm and use your %@ ideas.",
        standardOpponentTemplate: "Your opponent continues with a standard response."
    )

    // MARK: - Token Limits

    struct Tokens: Sendable {
        let coaching: Int
        let batchedCoaching: Int
        let explanation: Int
    }

    static let tokens = Tokens(
        coaching: 80,
        batchedCoaching: 200,
        explanation: 200
    )

    // MARK: - Feedback

    struct Feedback: Sendable {
        let workerURL: String
    }

    static let feedback = Feedback(
        workerURL: "https://chess-coach-feedback.malathon.workers.dev/feedback"
    )
}
