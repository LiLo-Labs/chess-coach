import Foundation
import ChessKit

/// ViewModel for Stage 4: Practice Opening mode.
/// Uses VariedOpponentService for diverse opponent responses across all learned lines.
@Observable
@MainActor
final class PracticeSessionViewModel {
    let opening: Opening
    let gameState: GameState
    private let stockfish: StockfishService
    private let variedOpponent: VariedOpponentService
    private var maiaService: MaiaService?
    private(set) var isPro: Bool

    // Line detection
    private(set) var currentLineName: String?
    private(set) var lineTransitionMessage: String?

    // Stats
    private(set) var stats = SessionStats()
    private(set) var sessionComplete = false
    private(set) var isThinking = false
    private(set) var evalScore: Int = 0

    // Per-line accuracy tracking
    private(set) var lineAccuracies: [String: (correct: Int, total: Int)] = [:]
    private(set) var linesEncountered: [String] = []

    private(set) var userELO: Int = UserDefaults.standard.object(forKey: AppSettings.Key.userELO) as? Int ?? 600
    private(set) var opponentELO: Int = UserDefaults.standard.object(forKey: AppSettings.Key.opponentELO) as? Int ?? 1200
    private var sessionGeneration = 0
    private var moveSequence: [String] = []

    var isUserTurn: Bool {
        (opening.color == .white && gameState.isWhiteTurn) ||
        (opening.color == .black && !gameState.isWhiteTurn)
    }

    var moveCount: Int { gameState.plyCount }

    var evalFraction: Double {
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

    init(opening: Opening, isPro: Bool = true, stockfish: StockfishService? = nil) {
        self.opening = opening
        self.isPro = isPro
        self.gameState = GameState()
        self.stockfish = stockfish ?? StockfishService()
        self.variedOpponent = VariedOpponentService(opening: opening)
    }

    func startSession() async {
        do {
            maiaService = try MaiaService()
        } catch {
            #if DEBUG
            print("[ChessCoach] Maia init failed for practice: \(error)")
            #endif
        }

        await stockfish.start()

        if opening.color == .black {
            await makeOpponentMove()
        }

        updateLineDetection()
    }

    func userMoved(from: String, to: String) async {
        let uciMove = from + to
        moveSequence.append(uciMove)
        stats.totalUserMoves += 1

        SoundService.shared.play(.move)
        SoundService.shared.hapticPiecePlaced()

        // Check if move matches any known continuation
        let continuations = opening.continuations(afterMoves: Array(moveSequence.dropLast()))
        let isBookMove = continuations.contains { $0.uci == uciMove }
        if isBookMove {
            stats.movesOnBook += 1
        }

        // Track per-line accuracy
        updateLineAccuracy(isCorrect: isBookMove)
        updateLineDetection()

        await updateEval()

        // Check for end of known lines (play up to ~30 moves total = 60 plies)
        if gameState.plyCount >= 60 || gameState.legalMoves.isEmpty {
            endSession()
            return
        }

        if !sessionComplete {
            await makeOpponentMove()
        }
    }

    func endSession() {
        sessionComplete = true
        variedOpponent.recordPath(moveSequence)
        saveProgress()
        Task { await stockfish.stop() }
    }

    // MARK: - Private

    private func makeOpponentMove() async {
        isThinking = true
        defer { isThinking = false }

        let gen = sessionGeneration
        let progress = PersistenceService.shared.loadProgress(forOpening: opening.id)

        // Try varied opponent service first (book moves)
        if let bookMove = variedOpponent.pickOpponentMove(
            atPly: gameState.plyCount,
            afterMoves: moveSequence,
            lineProgress: progress.lineProgress
        ) {
            guard gen == sessionGeneration else { return }
            let success = gameState.makeMoveUCI(bookMove)
            if success {
                moveSequence.append(bookMove)
                updateLineDetection()
                return
            }
        }

        // Fall back to Maia for off-book play
        var computedMove: String?
        if let maia = maiaService {
            do {
                let legalUCI = gameState.legalMoves.map(\.description)
                computedMove = try await maia.sampleMove(
                    fen: gameState.fen,
                    legalMoves: legalUCI,
                    eloSelf: opponentELO,
                    eloOppo: userELO
                )
            } catch {
                #if DEBUG
                print("[ChessCoach] Maia failed in practice: \(error)")
                #endif
            }
        }

        if computedMove == nil {
            if let result = await stockfish.evaluate(fen: gameState.fen, depth: AppConfig.engine.opponentMoveDepth) {
                computedMove = result.bestMove
            }
        }

        guard gen == sessionGeneration, let move = computedMove else { return }

        // Minimum thinking delay
        try? await Task.sleep(for: .seconds(Double.random(in: 0.5...1.5)))
        guard gen == sessionGeneration else { return }

        let success = gameState.makeMoveUCI(move)
        if success {
            moveSequence.append(move)
            updateLineDetection()
        }
    }

    private func updateLineDetection() {
        let matchingLines = opening.matchingLines(forMoveSequence: moveSequence)
        let previousName = currentLineName

        if let bestMatch = matchingLines.first {
            currentLineName = bestMatch.name
            // Track encountered lines
            if !linesEncountered.contains(bestMatch.id) {
                linesEncountered.append(bestMatch.id)
            }
            // Line transition message
            if previousName != nil && previousName != bestMatch.name {
                lineTransitionMessage = "Entering \(bestMatch.name) territory"
                // Clear after a few seconds
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    await MainActor.run { lineTransitionMessage = nil }
                }
            }
        } else if !moveSequence.isEmpty {
            currentLineName = nil
            if previousName != nil {
                lineTransitionMessage = "Off-book — play freely"
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    await MainActor.run { lineTransitionMessage = nil }
                }
            }
        }
    }

    private func updateLineAccuracy(isCorrect: Bool) {
        let matchingLines = opening.matchingLines(forMoveSequence: moveSequence)
        for line in matchingLines {
            var entry = lineAccuracies[line.id] ?? (correct: 0, total: 0)
            entry.total += 1
            if isCorrect { entry.correct += 1 }
            lineAccuracies[line.id] = entry
        }
    }

    private func updateEval() async {
        let fen = gameState.fen
        if let result = await stockfish.evaluate(fen: fen, depth: AppConfig.engine.evalDepth) {
            evalScore = result.score
        }
    }

    private func saveProgress() {
        guard stats.totalUserMoves > 0 else { return }
        var progress = PersistenceService.shared.loadProgress(forOpening: opening.id)
        progress.practiceSessionCount += 1
        progress.practiceAccuracy = stats.accuracy
        PersistenceService.shared.saveProgress(progress)
    }
}
