import Foundation

/// Background Stockfish per-move analysis for imported games.
/// Follows the same actor/service pattern as PuzzleService.
@MainActor @Observable
final class GameAnalysisService {

    var isAnalyzing = false
    var analysisProgress: Double = 0
    var currentGameIndex = 0
    var totalGames = 0

    private let stockfish: StockfishService
    private var analysisTask: Task<Void, Never>?

    init(stockfish: StockfishService) {
        self.stockfish = stockfish
    }

    /// Analyze all unanalyzed games, saving incrementally after each game completes.
    func analyzeGames(_ games: [ImportedGame]) async {
        var mutableGames = games
        let unanalyzed = mutableGames.indices.filter { !mutableGames[$0].analysisComplete }
        guard !unanalyzed.isEmpty else { return }

        isAnalyzing = true
        totalGames = unanalyzed.count
        currentGameIndex = 0
        analysisProgress = 0

        for (progressIdx, gameIdx) in unanalyzed.enumerated() {
            if Task.isCancelled { break }

            currentGameIndex = progressIdx + 1
            let game = mutableGames[gameIdx]

            if let analyzed = await analyzeGame(game) {
                mutableGames[gameIdx] = analyzed
                PersistenceService.shared.saveImportedGames(mutableGames)
            }

            analysisProgress = Double(progressIdx + 1) / Double(unanalyzed.count)
        }

        isAnalyzing = false
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
    }

    // MARK: - Per-Game Analysis

    private func analyzeGame(_ game: ImportedGame) async -> ImportedGame? {
        let sanMoves = game.sanMoves
        guard !sanMoves.isEmpty else { return nil }

        // Replay to collect FENs at each position
        guard let replay = PGNParser.replayMoves(sanMoves) else { return nil }
        let fens = replay.fens
        let uciMoves = replay.uciMoves

        guard fens.count == sanMoves.count, uciMoves.count == sanMoves.count else { return nil }

        var analyzedMoves: [AnalyzedMove] = []
        var totalCPLoss = 0
        var playerMoveCount = 0

        let isPlayerWhite = game.playerColor == "white"

        // Evaluate the starting position first
        var prevEval = 0
        if let startResult = await stockfish.topMoves(fen: fens[0], count: 1, depth: AppConfig.engine.evalDepth).first {
            prevEval = startResult.score
        }

        for ply in 0..<sanMoves.count {
            if Task.isCancelled { return nil }

            let fen = fens[ply]
            let san = sanMoves[ply]
            let uci = uciMoves[ply]

            let isPlayerMove = (ply % 2 == 0) == isPlayerWhite

            // Get best move for this position
            let topMoves = await stockfish.topMoves(fen: fen, count: 1, depth: AppConfig.engine.evalDepth)
            let bestMove = topMoves.first
            let evalBefore = prevEval

            // Get eval after the played move by evaluating next position
            let nextFen: String
            if ply + 1 < fens.count {
                nextFen = fens[ply + 1]
            } else {
                // Last move — evaluate from the resulting position
                let gs = GameState(fen: fen)
                gs.makeSANMove(san)
                nextFen = gs.fen
            }

            let nextEval: Int
            if let result = await stockfish.topMoves(fen: nextFen, count: 1, depth: AppConfig.engine.evalDepth).first {
                // Flip sign since it's now the other side's perspective
                nextEval = -result.score
            } else {
                nextEval = evalBefore
            }

            let evalAfter = nextEval

            // Centipawn loss: only meaningful for player's moves
            // Loss = how much worse the position got compared to best play
            let cpLoss: Int
            if isPlayerMove {
                let bestEval = bestMove?.score ?? evalBefore
                // From player's perspective, loss is best eval minus eval after their move
                if isPlayerWhite {
                    cpLoss = max(0, bestEval - evalAfter)
                } else {
                    cpLoss = max(0, (-bestEval) - (-evalAfter))
                }
                totalCPLoss += cpLoss
                playerMoveCount += 1
            } else {
                cpLoss = 0
            }

            let classification: AnalyzedMove.MoveClass
            if !isPlayerMove {
                classification = .good
            } else if cpLoss >= 300 {
                classification = .blunder
            } else if cpLoss >= 100 {
                classification = .mistake
            } else if cpLoss >= 30 {
                classification = .inaccuracy
            } else {
                classification = .good
            }

            let bestSAN: String?
            if let bestUCI = bestMove?.move {
                bestSAN = GameState.sanForUCI(bestUCI, inFEN: fen)
            } else {
                bestSAN = nil
            }

            analyzedMoves.append(AnalyzedMove(
                id: ply,
                san: san,
                uci: uci,
                fen: fen,
                evalBefore: evalBefore,
                evalAfter: evalAfter,
                bestMoveUCI: bestMove?.move,
                bestMoveSAN: bestSAN,
                centipawnLoss: cpLoss,
                classification: classification
            ))

            prevEval = nextEval
        }

        let avgCPLoss = playerMoveCount > 0 ? Double(totalCPLoss) / Double(playerMoveCount) : 0

        var updated = game
        updated.analysisComplete = true
        updated.mistakes = analyzedMoves.filter { $0.classification != .good }
        updated.averageCentipawnLoss = avgCPLoss

        return updated
    }
}
