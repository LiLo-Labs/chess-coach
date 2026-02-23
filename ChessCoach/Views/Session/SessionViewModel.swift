import Foundation
import ChessKit

enum BookStatus: Equatable {
    case onBook
    case userDeviated(expected: OpeningMove, atPly: Int)
    case opponentDeviated(expected: OpeningMove, played: String, atPly: Int)
}

struct SessionStats {
    var movesOnBook: Int = 0
    var totalUserMoves: Int = 0
    var deviationPly: Int?
    var deviatedBy: DeviatedBy?
    var restarts: Int = 0

    enum DeviatedBy { case user, opponent }

    var accuracy: Double {
        guard totalUserMoves > 0 else { return 0 }
        return Double(movesOnBook) / Double(totalUserMoves)
    }
}

@Observable
@MainActor
final class SessionViewModel {
    let opening: Opening
    let gameState: GameState
    private let stockfish: StockfishService
    private let llmService: LLMService
    private let curriculumService: CurriculumService
    private let coachingService: CoachingService
    private var maiaService: MaiaService?

    // Latest coaching per side
    private(set) var userCoachingText: String?
    private(set) var opponentCoachingText: String?

    // Explain feature — per side
    private(set) var userExplanation: String?
    private(set) var opponentExplanation: String?
    private(set) var isExplainingUser = false
    private(set) var isExplainingOpponent = false
    private(set) var userExplainContext: ExplainContext?
    private(set) var opponentExplainContext: ExplainContext?

    // Off-book explanation
    private(set) var offBookExplanation: String?
    private(set) var isExplainingOffBook = false

    private(set) var isThinking = false
    private(set) var isCoachingLoading = false
    private(set) var sessionComplete = false
    private var sessionGeneration = 0
    private(set) var userELO: Int = UserDefaults.standard.object(forKey: "user_elo") as? Int ?? 600
    private(set) var opponentELO: Int = UserDefaults.standard.object(forKey: "opponent_elo") as? Int ?? 1200

    // Evaluation
    private(set) var evalScore: Int = 0  // centipawns, positive = white advantage

    // Opening guide
    private(set) var bookStatus: BookStatus = .onBook
    private(set) var bestResponseHint: String?
    private(set) var stats = SessionStats()

    var isOnBook: Bool { bookStatus == .onBook }

    var isUserTurn: Bool {
        (opening.color == .white && gameState.isWhiteTurn) ||
        (opening.color == .black && !gameState.isWhiteTurn)
    }

    var moveCount: Int { gameState.plyCount }

    var expectedNextMove: OpeningMove? {
        guard isOnBook else { return nil }
        return opening.expectedMove(atPly: gameState.plyCount)
    }

    /// Eval as a fraction from -1.0 (black winning) to 1.0 (white winning)
    var evalFraction: Double {
        // Convert centipawns to a -1...1 range using a sigmoid-like curve
        let cp = Double(evalScore)
        return cp / (abs(cp) + 400.0)
    }

    var evalText: String {
        if abs(evalScore) >= 10000 {
            return evalScore > 0 ? "M" : "-M"
        }
        let pawns = Double(evalScore) / 100.0
        if abs(pawns) < 0.3 { return "Equal" }
        let sign = pawns > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", pawns))"
    }

    init(opening: Opening) {
        self.opening = opening
        self.gameState = GameState()
        self.stockfish = StockfishService()
        self.llmService = LLMService()
        self.curriculumService = CurriculumService(opening: opening, phase: .learningMainLine)
        self.coachingService = CoachingService(llmService: llmService, curriculumService: curriculumService)
    }

    func startSession() async {
        do {
            maiaService = try MaiaService()
        } catch {
            maiaService = nil
            print("[ChessCoach] Maia init failed, falling back to Stockfish: \(error)")
        }
        await stockfish.start()
        await llmService.detectProvider()

        if opening.color == .black {
            await makeOpponentMove()
        }
    }

    func userMoved(from: String, to: String) async {
        let ply = gameState.plyCount - 1
        let uciMove = from + to

        // Clear explanations on new move
        userExplanation = nil
        opponentExplanation = nil
        offBookExplanation = nil

        // Track stats
        stats.totalUserMoves += 1

        if isOnBook {
            if opening.isDeviation(atPly: ply, move: uciMove) {
                if let expected = opening.expectedMove(atPly: ply) {
                    bookStatus = .userDeviated(expected: expected, atPly: ply)
                    stats.deviationPly = ply
                    stats.deviatedBy = .user
                }
            } else {
                stats.movesOnBook += 1
            }
        }

        // Get coaching for the user's move (eval runs inside generateCoaching)
        await generateCoaching(forPly: ply, move: uciMove, isUserMove: true)

        // Store context for explain
        userExplainContext = ExplainContext(
            fen: gameState.fen,
            move: uciMove,
            ply: ply,
            moveHistory: gameState.moveHistory.map { $0.from + $0.to },
            coachingText: userCoachingText ?? ""
        )

        if gameState.plyCount >= opening.mainLine.count {
            sessionComplete = true
            return
        }

        if !sessionComplete {
            await makeOpponentMove()
        }
    }

    /// Undo the user's last move so they can try again from the same position.
    func retryLastMove() {
        sessionGeneration += 1
        // Undo the user's move (and any coaching state for it)
        gameState.undoLastMove()
        userCoachingText = nil
        userExplanation = nil
        offBookExplanation = nil
        userExplainContext = nil

        // If user deviated, reset to on-book since we're back before the deviation
        if case .userDeviated = bookStatus {
            bookStatus = .onBook
        }

        // Adjust stats
        if stats.totalUserMoves > 0 {
            stats.totalUserMoves -= 1
        }
    }

    func restartSession() async {
        sessionGeneration += 1
        gameState.reset()
        bookStatus = .onBook
        bestResponseHint = nil
        userCoachingText = "Restarting — let's try the \(opening.name) again!"
        opponentCoachingText = nil
        userExplanation = nil
        opponentExplanation = nil
        offBookExplanation = nil
        userExplainContext = nil
        opponentExplainContext = nil
        sessionComplete = false
        evalScore = 0
        let restartCount = stats.restarts + 1
        stats = SessionStats()
        stats.restarts = restartCount

        if opening.color == .black {
            await makeOpponentMove()
        }
    }

    func requestExplanation(forUserMove: Bool) async {
        let ctx = forUserMove ? userExplainContext : opponentExplainContext
        guard let ctx else {
            print("[ChessCoach] No explain context for \(forUserMove ? "user" : "opponent")")
            return
        }

        print("[ChessCoach] Starting explanation for \(forUserMove ? "user" : "opponent")")

        if forUserMove { isExplainingUser = true } else { isExplainingOpponent = true }
        defer { if forUserMove { isExplainingUser = false } else { isExplainingOpponent = false } }

        let moveHistoryStr = buildMoveHistoryString()
        let who = forUserMove ? "the player's own move" : "the opponent's move"

        let prompt = """
        You are a friendly, encouraging chess coach teaching a beginner (ELO ~\(userELO)).
        Opening: \(opening.name)

        Moves so far: \(moveHistoryStr)
        Current position (FEN): \(ctx.fen)
        The move being asked about: \(ctx.move) — this was \(who)
        Quick summary already shown: "\(ctx.coachingText)"

        Give a deeper explanation (3-5 sentences) of WHY this move matters:
        - What squares or pieces does it affect?
        - What plan or idea does it support?
        - What could go wrong if a different move was played?
        - How does it fit into the \(opening.name) opening strategy?

        Use simple language a beginner can understand. Reference specific squares and pieces.
        Do not use algebraic notation symbols — spell out piece names.
        """

        do {
            print("[ChessCoach] Calling LLM for explanation...")
            let response = try await llmService.getExplanation(prompt: prompt)
            print("[ChessCoach] Got explanation: \(response.prefix(50))...")
            if forUserMove { userExplanation = response } else { opponentExplanation = response }
        } catch {
            print("[ChessCoach] Explanation error: \(error)")
            let fallback = "Couldn't get explanation right now. Try again."
            if forUserMove { userExplanation = fallback } else { opponentExplanation = fallback }
        }
    }

    func requestOffBookExplanation() async {
        guard !isExplainingOffBook else { return }
        isExplainingOffBook = true
        defer { isExplainingOffBook = false }

        let playedMove: String
        let expectedSan: String
        let expectedUci: String
        let who: String

        switch bookStatus {
        case let .userDeviated(expected, _):
            playedMove = gameState.moveHistory.last.map { $0.from + $0.to } ?? "?"
            expectedSan = expected.san
            expectedUci = expected.uci
            who = "You"
        case let .opponentDeviated(expected, played, _):
            playedMove = played
            expectedSan = expected.san
            expectedUci = expected.uci
            who = "Your opponent"
        default:
            return
        }

        // Use Stockfish to evaluate current position
        var evalNote = ""
        if let result = await stockfish.evaluate(fen: gameState.fen, depth: 12) {
            let pawns = Double(result.score) / 100.0
            if abs(pawns) < 0.3 {
                evalNote = "The position is roughly equal — the deviation may be fine."
            } else if pawns > 0.3 {
                evalNote = "White has a slight advantage (+\(String(format: "%.1f", pawns)) pawns)."
            } else {
                evalNote = "Black has a slight advantage (\(String(format: "%.1f", pawns)) pawns)."
            }
        }

        let moveHistoryStr = buildMoveHistoryString()

        let prompt = """
        You are a friendly chess coach teaching a beginner (ELO ~\(userELO)).
        Opening: \(opening.name)

        Moves so far: \(moveHistoryStr)
        Current position (FEN): \(gameState.fen)

        \(who) played \(playedMove) instead of the book move \(expectedSan) (\(expectedUci)).
        \(evalNote)

        Explain in 2-3 sentences:
        1. Why the book move (\(expectedSan)) is the standard choice in the \(opening.name)
        2. Whether the played move (\(playedMove)) is actually bad, or if it's a reasonable alternative
        3. What the key difference is between the two moves

        Be honest — if the played move is fine or even good, say so.
        Use simple language. Reference specific squares and pieces.
        Do not use algebraic notation symbols — spell out piece names.
        """

        do {
            let response = try await llmService.getExplanation(prompt: prompt)
            offBookExplanation = response
        } catch {
            offBookExplanation = "Couldn't get explanation right now. Try again."
        }
    }

    func endSession() {
        saveProgress()
        sessionComplete = true
        Task {
            await stockfish.stop()
        }
    }

    private func saveProgress() {
        guard stats.totalUserMoves > 0 else { return }
        var progress = PersistenceService.shared.loadProgress(forOpening: opening.id)
        let completed = gameState.plyCount >= opening.mainLine.count
        progress.recordGame(accuracy: stats.accuracy, won: completed)
        PersistenceService.shared.saveProgress(progress)
    }

    // MARK: - Private

    private func makeOpponentMove() async {
        isThinking = true
        defer { isThinking = false }

        let gen = sessionGeneration
        let ply = gameState.plyCount
        let clock = ContinuousClock()
        let minimumDelay = Duration.seconds(Double.random(in: 1.0...10.0))
        let start = clock.now

        var computedMove: String?

        if let forcedMove = curriculumService.getMaiaOverride(atPly: ply) {
            computedMove = forcedMove
        } else if let maia = maiaService {
            do {
                computedMove = try await maia.sampleMove(
                    fen: gameState.fen,
                    legalMoves: gameState.legalMoves.map(\.description),
                    eloSelf: opponentELO,
                    eloOppo: userELO
                )
            } catch {
                // Fall through to Stockfish
            }
        }

        // Check if session was restarted while we were awaiting
        guard gen == sessionGeneration else { return }

        if computedMove == nil {
            if let result = await stockfish.evaluate(fen: gameState.fen, depth: 10) {
                computedMove = result.bestMove
            }
        }

        // Check again after Stockfish await
        guard gen == sessionGeneration else { return }

        guard let move = computedMove else {
            opponentCoachingText = "Opponent couldn't find a move. Try restarting."
            return
        }

        let elapsed = clock.now - start
        if elapsed < minimumDelay {
            do {
                try await Task.sleep(for: minimumDelay - elapsed)
            } catch {
                return // Task cancelled (user left session)
            }
        }

        guard gen == sessionGeneration else { return }

        if isOnBook && opening.isDeviation(atPly: ply, move: move) {
            if let expected = opening.expectedMove(atPly: ply) {
                bookStatus = .opponentDeviated(expected: expected, played: move, atPly: ply)
                stats.deviationPly = ply
                stats.deviatedBy = .opponent
            }
        }

        let moveSucceeded = gameState.makeMoveUCI(move)
        guard moveSucceeded else {
            print("[ChessCoach] makeMoveUCI failed for \(move) — position may have changed")
            return
        }

        if case .opponentDeviated = bookStatus {
            await fetchBestResponseHint()
        }

        guard gen == sessionGeneration else { return }

        await generateCoaching(forPly: ply, move: move, isUserMove: false)

        // Store context for explain
        opponentExplainContext = ExplainContext(
            fen: gameState.fen,
            move: move,
            ply: ply,
            moveHistory: gameState.moveHistory.map { $0.from + $0.to },
            coachingText: opponentCoachingText ?? ""
        )
    }

    private func fetchBestResponseHint() async {
        if let result = await stockfish.evaluate(fen: gameState.fen, depth: 12) {
            bestResponseHint = result.bestMove
        }
    }

    private func updateEval() async {
        if let result = await stockfish.evaluate(fen: gameState.fen, depth: 12) {
            evalScore = result.score
        }
    }

    private func generateCoaching(forPly ply: Int, move: String, isUserMove: Bool) async {
        isCoachingLoading = true
        defer { isCoachingLoading = false }

        // Update eval in parallel with coaching
        async let evalTask: () = updateEval()

        let moveHistoryStr = buildMoveHistoryString()

        let text = await coachingService.getCoaching(
            fen: gameState.fen,
            lastMove: move,
            scoreBefore: 0,
            scoreAfter: 0,
            ply: ply,
            userELO: userELO,
            moveHistory: moveHistoryStr,
            isUserMove: isUserMove
        )

        // Wait for eval to complete
        await evalTask

        if let text {
            if isUserMove {
                userCoachingText = text
            } else {
                opponentCoachingText = text
            }
        }
    }

    private func buildMoveHistoryString() -> String {
        var result = ""
        for (i, move) in gameState.moveHistory.enumerated() {
            if i % 2 == 0 {
                result += "\(i / 2 + 1). "
            }
            if i < opening.mainLine.count && opening.mainLine[i].uci == move.from + move.to {
                result += opening.mainLine[i].san
            } else {
                result += move.from + move.to
            }
            result += " "
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Supporting Types

struct ExplainContext {
    let fen: String
    let move: String
    let ply: Int
    let moveHistory: [String]
    let coachingText: String
}
