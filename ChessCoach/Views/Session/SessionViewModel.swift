import Foundation
import ChessKit

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

    private(set) var coachingText: String?
    private(set) var isThinking = false
    private(set) var isCoachingLoading = false
    private(set) var sessionComplete = false
    private(set) var userELO: Int = UserDefaults.standard.object(forKey: "user_elo") as? Int ?? 600
    private(set) var opponentELO: Int = UserDefaults.standard.object(forKey: "opponent_elo") as? Int ?? 1200

    var isUserTurn: Bool {
        (opening.color == .white && gameState.isWhiteTurn) ||
        (opening.color == .black && !gameState.isWhiteTurn)
    }

    var moveCount: Int { gameState.plyCount }

    init(opening: Opening) {
        self.opening = opening
        self.gameState = GameState()
        self.stockfish = StockfishService()
        self.llmService = LLMService()
        self.curriculumService = CurriculumService(opening: opening, phase: .learningMainLine)
        self.coachingService = CoachingService(llmService: llmService, curriculumService: curriculumService)
    }

    func startSession() async {
        // Try loading Maia 2 for human-like opponent
        do {
            maiaService = try MaiaService()
        } catch {
            // Fall back to Stockfish if Maia model not available
            maiaService = nil
        }
        await stockfish.start()
        await llmService.detectProvider()

        // If user plays black, make the first opponent move
        if opening.color == .black {
            await makeOpponentMove()
        } else {
            // Show initial coaching for white's first move
            showMainLineHint()
        }
    }

    func userMoved(from: String, to: String) async {
        let ply = gameState.plyCount - 1
        let uciMove = from + to

        // Get coaching for the user's move
        await generateCoaching(forPly: ply, move: uciMove)

        // Check if opening phase is over
        if gameState.plyCount >= opening.mainLine.count {
            sessionComplete = true
            return
        }

        // Make opponent's response
        if !sessionComplete {
            try? await Task.sleep(for: .milliseconds(500))
            await makeOpponentMove()
        }
    }

    func endSession() {
        sessionComplete = true
        Task {
            await stockfish.stop()
        }
    }

    // MARK: - Private

    private func makeOpponentMove() async {
        isThinking = true
        defer { isThinking = false }

        let ply = gameState.plyCount

        // Check if curriculum forces a specific move
        if let forcedMove = curriculumService.getMaiaOverride(atPly: ply) {
            gameState.makeMoveUCI(forcedMove)
            await generateCoaching(forPly: ply, move: forcedMove)
            return
        }

        // Use Maia 2 for human-like opponent, fall back to Stockfish
        if let maia = maiaService {
            do {
                let move = try await maia.sampleMove(
                    fen: gameState.fen,
                    legalMoves: gameState.legalMoves.map(\.description),
                    eloSelf: opponentELO,
                    eloOppo: userELO
                )
                gameState.makeMoveUCI(move)
                await generateCoaching(forPly: ply, move: move)
                return
            } catch {
                // Fall through to Stockfish
            }
        }

        if let result = await stockfish.evaluate(fen: gameState.fen, depth: 10) {
            gameState.makeMoveUCI(result.bestMove)
            await generateCoaching(forPly: ply, move: result.bestMove)
        }
    }

    private func generateCoaching(forPly ply: Int, move: String) async {
        isCoachingLoading = true
        defer { isCoachingLoading = false }

        let scoreBefore = 0 // Simplified for now
        let scoreAfter = 0

        coachingText = await coachingService.getCoaching(
            fen: gameState.fen,
            lastMove: move,
            scoreBefore: scoreBefore,
            scoreAfter: scoreAfter,
            ply: ply,
            userELO: userELO
        )
    }

    private func showMainLineHint() {
        if let expected = opening.expectedMove(atPly: 0) {
            coachingText = expected.explanation
        }
    }
}
