import Foundation

/// Generates puzzles from opening data and user mistake history.
/// Does not require LLM — uses Stockfish for evaluation and opening trees for positions.
@MainActor
final class PuzzleService {
    private let database = OpeningDatabase.shared
    private let stockfish: StockfishService

    init(stockfish: StockfishService) {
        self.stockfish = stockfish
    }

    // MARK: - Puzzle Generation

    /// Generate a batch of puzzles from various sources.
    func generatePuzzles(count: Int = 10, userELO: Int = 600) async -> [Puzzle] {
        var puzzles: [Puzzle] = []

        // Mix sources: opening knowledge + mistakes + engine puzzles
        let openingPuzzles = generateOpeningPuzzles(count: max(count / 2, 3), userELO: userELO)
        puzzles.append(contentsOf: openingPuzzles)

        let mistakePuzzles = generateMistakePuzzles(count: max(count / 3, 2))
        puzzles.append(contentsOf: mistakePuzzles)

        // Fill remaining with best-move puzzles from opening positions
        let remaining = count - puzzles.count
        if remaining > 0 {
            let bestMovePuzzles = await generateBestMovePuzzles(count: remaining, userELO: userELO)
            puzzles.append(contentsOf: bestMovePuzzles)
        }

        return puzzles.shuffled()
    }

    /// Generate a daily puzzle — one puzzle based on user's weakest area.
    func dailyPuzzle() async -> Puzzle? {
        let tracker = PersistenceService.shared.loadMistakeTracker()
        let topMistakes = tracker.topMistakes(count: 1)

        if let mistake = topMistakes.first {
            return mistakeToPuzzle(mistake)
        }

        // Fallback: random opening puzzle
        let puzzles = generateOpeningPuzzles(count: 1, userELO: 600)
        return puzzles.first
    }

    // MARK: - Opening Knowledge Puzzles

    /// Creates puzzles from opening book moves — "What's the best move here?"
    /// Requires positions at least 4 plies deep to avoid trivial early-move puzzles.
    private func generateOpeningPuzzles(count: Int, userELO: Int) -> [Puzzle] {
        let allOpenings = database.openings
        var puzzles: [Puzzle] = []

        for _ in 0..<(count * 5) {
            guard puzzles.count < count else { break }
            guard let opening = allOpenings.randomElement() else { continue }

            // Use lines if available, otherwise wrap mainLine as a single line
            let moves: [OpeningMove]
            if let lines = opening.lines, let line = lines.randomElement() {
                moves = line.moves
            } else {
                moves = opening.mainLine
            }
            // Require at least 6 half-moves (3 full moves) so we get meaningful positions
            guard moves.count >= 6 else { continue }

            // Pick a position at least 4 plies deep (after 2 full moves by each side)
            let minPly = 4
            let maxPly = moves.count - 1
            guard minPly < maxPly else { continue }
            let plyIndex = Int.random(in: minPly...maxPly)

            // Build FEN by replaying moves up to this point
            let gameState = GameState()
            var valid = true
            for i in 0..<plyIndex {
                if !gameState.makeMoveUCI(moves[i].uci) {
                    valid = false
                    break
                }
            }
            guard valid else { continue }

            let solutionMove = moves[plyIndex]
            let fen = gameState.fen

            // Verify the solution move is legal in this position
            guard gameState.makeMoveUCI(solutionMove.uci) else { continue }
            // Compute SAN from actual board position (not from opening data which may differ)
            let san = GameState.sanForUCI(solutionMove.uci, inFEN: fen)

            let difficulty = min(5, max(1, opening.difficulty + (plyIndex > 8 ? 1 : 0)))

            let puzzle = Puzzle(
                id: "opening_\(opening.id)_\(plyIndex)_\(UUID().uuidString.prefix(4))",
                fen: fen,
                solutionUCI: solutionMove.uci,
                solutionSAN: san,
                theme: .openingKnowledge,
                difficulty: difficulty,
                openingID: opening.id,
                explanation: solutionMove.explanation
            )
            puzzles.append(puzzle)
        }

        return puzzles
    }

    // MARK: - Mistake Review Puzzles

    private func generateMistakePuzzles(count: Int) -> [Puzzle] {
        let tracker = PersistenceService.shared.loadMistakeTracker()
        let topMistakes = tracker.topMistakes(count: count)
        return topMistakes.compactMap { mistakeToPuzzle($0) }
    }

    private func mistakeToPuzzle(_ record: MistakeRecord) -> Puzzle? {
        guard let opening = database.opening(byID: record.openingID) else { return nil }

        // Find the moves to replay from lines or mainLine
        let moves: [OpeningMove]
        if let lines = opening.lines, let lineID = record.lineID,
           let line = lines.first(where: { $0.id == lineID }) {
            moves = line.moves
        } else if let lines = opening.lines, let line = lines.first {
            moves = line.moves
        } else {
            moves = opening.mainLine
        }

        let gameState = GameState()
        let movesToPlay = min(record.ply, moves.count)
        for i in 0..<movesToPlay {
            if !gameState.makeMoveUCI(moves[i].uci) {
                return nil
            }
        }

        let san = GameState.sanForUCI(record.expectedMove, inFEN: gameState.fen)

        return Puzzle(
            id: "mistake_\(record.id)",
            fen: gameState.fen,
            solutionUCI: record.expectedMove,
            solutionSAN: san,
            theme: .mistakeReview,
            difficulty: 2,
            openingID: record.openingID,
            explanation: "You've played this position \(record.totalCount) time(s) and got it wrong. The correct move follows the opening plan."
        )
    }

    // MARK: - Best Move Puzzles (Engine-Assisted)

    private func generateBestMovePuzzles(count: Int, userELO: Int) async -> [Puzzle] {
        let allOpenings = database.openings
        var puzzles: [Puzzle] = []

        for _ in 0..<(count * 3) {
            guard puzzles.count < count else { break }
            guard let opening = allOpenings.randomElement() else { continue }

            let moves: [OpeningMove]
            if let lines = opening.lines, let line = lines.randomElement() {
                moves = line.moves
            } else {
                moves = opening.mainLine
            }
            guard moves.count >= 4 else { continue }

            let depth = min(Int.random(in: 3..<moves.count), moves.count - 1)
            let gameState = GameState()
            var valid = true
            for i in 0..<depth {
                if !gameState.makeMoveUCI(moves[i].uci) {
                    valid = false
                    break
                }
            }
            guard valid else { continue }

            let fen = gameState.fen

            guard let topMoves = await nonEmpty(stockfish.topMoves(fen: fen, count: 3, depth: AppConfig.engine.evalDepth)) else {
                continue
            }

            guard topMoves.count >= 2 else { continue }
            let scoreDiff = abs(topMoves[0].score - topMoves[1].score)
            guard scoreDiff >= 30 else { continue }

            let bestMove = topMoves[0].move
            let san = GameState.sanForUCI(bestMove, inFEN: fen)

            let difficulty: Int
            switch scoreDiff {
            case 200...: difficulty = 1
            case 100..<200: difficulty = 2
            case 60..<100: difficulty = 3
            case 30..<60: difficulty = 4
            default: difficulty = 5
            }

            let puzzle = Puzzle(
                id: "bestmove_\(opening.id)_\(depth)_\(UUID().uuidString.prefix(4))",
                fen: fen,
                solutionUCI: bestMove,
                solutionSAN: san,
                theme: .findTheBestMove,
                difficulty: difficulty,
                openingID: opening.id,
                explanation: nil
            )
            puzzles.append(puzzle)
        }

        return puzzles
    }

    private func nonEmpty(_ moves: [(move: String, score: Int)]) -> [(move: String, score: Int)]? {
        moves.isEmpty ? nil : moves
    }
}
