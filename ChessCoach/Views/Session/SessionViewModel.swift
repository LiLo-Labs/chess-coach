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

    private(set) var coachingText: String?
    private(set) var isThinking = false
    private(set) var isCoachingLoading = false
    private(set) var sessionComplete = false
    private(set) var userELO: Int = 600

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

        // Otherwise use Stockfish as opponent (placeholder for Maia)
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
