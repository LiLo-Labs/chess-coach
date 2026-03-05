import Foundation
import SwiftUI
import ChessKit

/// Unified ViewModel for all gameplay screens: trainer, guided, unguided, and practice modes.
@Observable
@MainActor
final class GamePlayViewModel {
    let mode: GamePlayMode
    let gameState: GameState
    let stockfish: StockfishService
    let llmService: LLMService
    private(set) var maiaService: MaiaService?
    private(set) var coachingService: CoachingService?
    private(set) var curriculumService: CurriculumService?
    private(set) var planScoringService: PlanScoringService?
    private(set) var spacedRepScheduler: SpacedRepScheduler?
    private(set) var featureAccess: (any FeatureAccessProviding)?

    // Game flow
    var isThinking = false
    var isGameOver = false
    var sessionComplete = false
    var gameResult: TrainerGameResult?
    var sessionResult: SessionResult?
    var sessionGeneration = 0
    var isCoachingLoading = false
    var isModelLoading = true

    // Board display
    var arrowFrom: String?
    var arrowTo: String?
    var hintSquare: String?
    var displayGameState: GameState { replayGameState ?? gameState }

    // Coaching feed
    var feedEntries: [CoachingEntry] = []

    // Coaching text (session modes — per side)
    var userCoachingText: String?
    var opponentCoachingText: String?
    var lastCoachingWasUser = false

    // Explain feature — per side (session)
    var userExplanation: String?
    var opponentExplanation: String?
    var isExplainingUser = false
    var isExplainingOpponent = false
    var userExplainContext: ExplainContext?
    var opponentExplainContext: ExplainContext?
    var offBookExplanation: String?
    var isExplainingOffBook = false

    // Eval
    var evalScore: Int = 0

    // Book tracking (session modes)
    var bookStatus: BookStatus = .onBook
    var discoveryMode = false
    var branchPointOptions: [OpeningMove]?
    var suggestedVariation: OpeningLine?
    var bestResponseHint: String?

    // Stats (session modes)
    var stats = SessionStats()

    // Undo/redo + replay
    var undoStack: [GamePlaySnapshot] = []
    var redoStack: [GamePlaySnapshot] = []
    var replayPly: Int?
    var replayGameState: GameState?
    var isReplaying: Bool { replayPly != nil }
    var canUndo: Bool { undoStack.count >= 2 }
    var canRedo: Bool { !redoStack.isEmpty }

    // Trainer-specific
    var currentOpening: OpeningDetection = .none
    var holisticDetection: HolisticDetection = .none
    var botMessage: String?
    var showBotMessage = false
    var isEvaluating = false
    var lastEvalScore: Int = 0
    let openingDetector = OpeningDetector()
    let holisticDetector = HolisticDetector()

    // Puzzle mode
    var puzzles: [Puzzle] = []
    var currentPuzzleIndex = 0
    var puzzleAttemptsRemaining = 3
    var puzzleSessionResult = PuzzleSessionResult()
    var isPuzzleComplete = false
    var puzzleSolutionArrowFrom: String?
    var puzzleSolutionArrowTo: String?
    var isPuzzleShowingSolution = false

    // Practice-specific
    var variedOpponent: VariedOpponentService?
    var lineAccuracies: [String: (correct: Int, total: Int)] = [:]
    var linesEncountered: [String] = []
    var currentLineName: String?
    var lineTransitionMessage: String?

    // Session-specific
    var coachPersonality: CoachPersonality? = .defaultPersonality
    var personalityQuip: String?
    var showPersonalityQuip = false
    var quipDismissTask: Task<Void, Never>?
    var lastMovePES: PlanExecutionScore?
    var openingFamiliarity: OpeningFamiliarity = .empty(openingID: "")
    var lastSessionMistakePlies: Set<Int> = []
    var sessionStartDate = Date()
    var consecutiveCorrectPlays: [String: Int] = [:]
    var coachingHistory: [(ply: Int, text: String)] = []
    var mistakeTracker = PersistenceService.shared.loadMistakeTracker()
    var hintTimer: Task<Void, Never>?
    var activeLine: OpeningLine?
    var activeLineID: String?
    let offBookCoachingService = OffBookCoachingService()
    var offBookGuidanceLastPly: Int = -10

    // ELO
    var userELO: Int = UserDefaults.standard.object(forKey: AppSettings.Key.userELO) as? Int ?? 600
    var opponentELO: Int = UserDefaults.standard.object(forKey: AppSettings.Key.opponentELO) as? Int ?? 1200

    // Pro status
    var isPro: Bool = true
    var showProUpgrade = false
    var hasShownUpgradeCTA = false

    // Haptic trigger
    var correctMoveTrigger: Int = 0

    // Trainer stats
    var humanStats: TrainerStats
    var engineStats: TrainerStats
    var recentGames: [TrainerGameResult]

    // MARK: - Computed

    var isUserTurn: Bool {
        let playerColor = mode.playerColor
        return (playerColor == .white && gameState.isWhiteTurn) ||
               (playerColor == .black && !gameState.isWhiteTurn)
    }

    var moveCount: Int { gameState.plyCount }

    var opening: Opening? { mode.opening }

    var activeMoves: [OpeningMove] {
        activeLine?.moves ?? opening?.mainLine ?? []
    }

    var isOnBook: Bool { bookStatus == .onBook }

    var familiarityProgress: Double { openingFamiliarity.progress }

    var moveHistorySAN: [String] {
        gameState.moveHistory.map { $0.from + $0.to }
    }

    var expectedNextMove: OpeningMove? {
        guard isOnBook, isUserTurn else { return nil }
        if discoveryMode { return nil }
        let ply = gameState.plyCount
        guard ply < activeMoves.count else { return nil }
        return activeMoves[ply]
    }

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

    var bestResponseDescription: String? {
        guard let hint = bestResponseHint else { return nil }
        let to = String(hint.dropFirst(2).prefix(2))
        let from = String(hint.prefix(2))
        let position = FenSerialization.default.deserialize(fen: gameState.fen)
        let piece = position.board[from]
        let pieceName: String
        if let piece {
            switch piece.kind {
            case .king: pieceName = "king"
            case .queen: pieceName = "queen"
            case .rook: pieceName = "rook"
            case .bishop: pieceName = "bishop"
            case .knight: pieceName = "knight"
            case .pawn: pieceName = "pawn"
            }
        } else {
            pieceName = "piece"
        }
        return "\(pieceName) to \(to)"
    }

    var displayUserCoaching: String? {
        guard let ply = replayPly else { return userCoachingText }
        return undoStack.last(where: { $0.ply == ply })?.userCoachingText
    }

    var displayOpponentCoaching: String? {
        guard let ply = replayPly else { return opponentCoachingText }
        return undoStack.last(where: { $0.ply == ply })?.opponentCoachingText
    }

    // Trainer-specific computed
    var botPersonality: OpponentPersonality {
        if case .trainer(let personality, _, _, _) = mode {
            return personality
        }
        return OpponentPersonality.forELO(opponentELO)
    }

    var selectedBotELO: Int {
        if case .trainer(_, _, _, let elo) = mode {
            return elo
        }
        return 1200
    }

    var trainerEngineMode: TrainerEngineMode {
        if case .trainer(_, let em, _, _) = mode { return em }
        return .humanLike
    }

    // MARK: - Init

    init(mode: GamePlayMode, isPro: Bool = true, featureAccess: (any FeatureAccessProviding)? = nil, stockfish: StockfishService? = nil, llmService: LLMService? = nil) {
        self.mode = mode
        self.isPro = isPro
        self.featureAccess = featureAccess
        self.gameState = GameState()
        self.stockfish = stockfish ?? StockfishService()
        self.llmService = llmService ?? LLMService()
        self.humanStats = TrainerModeView.loadStats(mode: .humanLike)
        self.engineStats = TrainerModeView.loadStats(mode: .engine)
        self.recentGames = TrainerModeView.loadRecentGames()

        // Session-specific init
        if let opening = mode.opening {
            self.coachPersonality = CoachPersonality.forOpening(opening)
            self.consecutiveCorrectPlays = UserDefaults.standard.dictionary(forKey: AppSettings.Key.consecutiveCorrect) as? [String: Int] ?? [:]

            let lineID = mode.lineID
            self.activeLineID = lineID
            let resolvedLine: OpeningLine?
            let resolvedCurriculum: CurriculumService

            if let lineID {
                let line = opening.lines?.first { $0.id == lineID }
                resolvedLine = line
            } else {
                resolvedLine = nil
            }

            // Compute familiarity from position mastery
            let positions = PersistenceService.shared.loadAllPositionMastery().filter { $0.openingID == opening.id }
            let fam = OpeningFamiliarity(openingID: opening.id, positions: positions)
            self.openingFamiliarity = fam

            self.activeLine = resolvedLine
            resolvedCurriculum = CurriculumService(opening: opening, activeLine: resolvedLine, familiarity: fam.progress)
            self.curriculumService = resolvedCurriculum
            let access = featureAccess ?? UnlockedAccess()
            self.coachingService = CoachingService(llmService: self.llmService, curriculumService: resolvedCurriculum, featureAccess: access)
            self.spacedRepScheduler = SpacedRepScheduler()

            if mode.sessionMode == .practice {
                self.variedOpponent = VariedOpponentService(opening: opening)
            }
        }

        // Puzzle-specific init
        if case .puzzle = mode {
            self.spacedRepScheduler = SpacedRepScheduler()
        }

        // Trainer-specific init — capture ELO at button-press time
        if case .trainer(_, _, _, let botELO) = mode {
            opponentELO = botELO
        }
    }

    // MARK: - Core Methods

    func startGame() async {
        sessionStartDate = Date()
        sessionGeneration += 1

        // Init engines
        do {
            maiaService = try MaiaService()
        } catch {
            maiaService = nil
            #if DEBUG
            print("[ChessCoach] Maia init failed: \(error)")
            #endif
        }

        await stockfish.start()

        if mode.isPuzzle {
            isModelLoading = false
            await loadPuzzles()
        } else if mode.sessionMode == .practice, let opening = mode.opening {
            isModelLoading = false
            if opening.color == .black {
                await makeOpponentMove()
            }
            updateLineDetection()
        } else if mode.isSession, let opening = mode.opening {
            planScoringService = PlanScoringService(llmService: llmService, stockfish: stockfish, featureAccess: featureAccess ?? UnlockedAccess())

            if isPro {
                await llmService.detectProvider()
                let modelReady = await llmService.isModelReady
                isModelLoading = !modelReady
                if !modelReady {
                    Task {
                        await llmService.warmUp()
                        isModelLoading = false
                    }
                }
            } else {
                isModelLoading = false
            }

            if opening.color == .black {
                await makeOpponentMove()
            }

            showProactiveCoaching()
            captureSnapshot()
            showCoachQuip(coachPersonality?.onGreeting.randomElement() ?? "Let's begin!")
        } else if mode.isTrainer {
            isModelLoading = false
            if mode.playerColor == .black && gameState.isWhiteTurn {
                makeBotMove()
            }
        }
    }

    func clearArrowAndHint() {
        arrowFrom = nil
        arrowTo = nil
        hintSquare = nil
        hintTimer?.cancel()
        hintTimer = nil
    }

    // MARK: - Undo/Redo

    func undoMove() {
        guard undoStack.count >= 2 else { return }
        let current = undoStack.removeLast()
        redoStack.append(current)
        guard let previous = undoStack.last else { return }
        restoreFromSnapshot(previous)
    }

    func redoMove() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(next)
        restoreFromSnapshot(next)
    }

    func retryLastMove() {
        sessionGeneration += 1
        gameState.undoLastMove()

        // FIX: Clear undo/redo stacks to prevent state corruption
        undoStack.removeAll()
        redoStack.removeAll()

        userCoachingText = nil
        userExplanation = nil
        offBookExplanation = nil
        userExplainContext = nil
        suggestedVariation = nil
        discoveryMode = false
        branchPointOptions = nil

        // Remove the orphan deviation entry from the feed
        if !feedEntries.isEmpty {
            feedEntries.removeFirst()
        }

        if case .userDeviated = bookStatus {
            bookStatus = .onBook
        }

        if stats.totalUserMoves > 0 {
            stats.totalUserMoves -= 1
        }

        captureSnapshot()
        showProactiveCoaching()
    }

    // MARK: - Replay

    func enterReplay(ply: Int) {
        let maxPly = gameState.plyCount
        let clampedPly = max(0, min(ply, maxPly))
        if clampedPly == maxPly {
            exitReplay()
            return
        }
        replayPly = clampedPly
        let tempState = GameState()
        let history = gameState.moveHistory
        for i in 0..<clampedPly {
            guard i < history.count else { break }
            tempState.makeMove(from: history[i].from, to: history[i].to, promotion: history[i].promotion)
        }
        replayGameState = tempState
    }

    func exitReplay() {
        replayPly = nil
        replayGameState = nil
    }

    // MARK: - Snapshots

    func captureSnapshot() {
        let snapshot = GamePlaySnapshot(
            ply: gameState.plyCount,
            fen: gameState.fen,
            moveHistory: gameState.moveHistory,
            bookStatus: bookStatus,
            evalScore: evalScore,
            lastMovePES: lastMovePES,
            stats: stats,
            feedEntries: feedEntries,
            arrowFrom: arrowFrom,
            arrowTo: arrowTo,
            hintSquare: hintSquare,
            userCoachingText: userCoachingText,
            opponentCoachingText: opponentCoachingText,
            lastEvalScoreBefore: lastEvalScore,
            coachingFeedForTrainer: nil
        )
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    func restoreFromSnapshot(_ snapshot: GamePlaySnapshot) {
        sessionGeneration += 1
        gameState.restoreFromHistory(snapshot.moveHistory)
        userCoachingText = snapshot.userCoachingText
        opponentCoachingText = snapshot.opponentCoachingText
        arrowFrom = snapshot.arrowFrom
        arrowTo = snapshot.arrowTo
        hintSquare = snapshot.hintSquare
        bookStatus = snapshot.bookStatus
        evalScore = snapshot.evalScore
        lastMovePES = snapshot.lastMovePES
        stats = snapshot.stats
        feedEntries = snapshot.feedEntries
        userExplanation = nil
        opponentExplanation = nil
        offBookExplanation = nil
        userExplainContext = nil
        opponentExplainContext = nil
        suggestedVariation = nil
        discoveryMode = false
        branchPointOptions = nil
        replayPly = nil
        replayGameState = nil
    }

    // MARK: - Quips

    func showCoachQuip(_ message: String) {
        quipDismissTask?.cancel()
        personalityQuip = message
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showPersonalityQuip = true
        }
        quipDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self?.showPersonalityQuip = false
            }
        }
    }

    func maybeShowQuip(for category: MoveCategory) {
        guard Double.random(in: 0...1) < 0.28 else { return }
        guard let personality = coachPersonality else { return }
        let quip = personality.witticism(for: category)
        guard !quip.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            showCoachQuip(quip)
        }
    }

    func showBotReaction(_ message: String) {
        botMessage = message
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showBotMessage = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation(.easeOut(duration: 0.3)) {
                showBotMessage = false
            }
        }
    }

    // MARK: - Pro

    func dismissProUpgrade() {
        showProUpgrade = false
    }

    func updateProStatus(_ isPro: Bool) {
        self.isPro = isPro
    }

    // MARK: - Hint Timer

    func startHintTimer(square: String?) {
        hintTimer?.cancel()
        guard let square else { return }
        hintTimer = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            hintSquare = square
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            hintSquare = nil
        }
    }

    // MARK: - Move History String

    func buildMoveHistoryString() -> String {
        let bookMoves = activeMoves
        let replay = GameState()
        var result = ""
        for (i, move) in gameState.moveHistory.enumerated() {
            if i % 2 == 0 {
                result += "\(i / 2 + 1). "
            }
            let uci = move.from + move.to + (move.promotion.map { $0.rawValue } ?? "")
            if i < bookMoves.count && bookMoves[i].uci == move.from + move.to {
                result += bookMoves[i].san
            } else {
                result += replay.sanForUCI(uci) ?? uci
            }
            replay.makeMoveUCI(uci)
            result += " "
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Eval

    func updateEval() async {
        guard !isOnBook else { return }
        let currentFen = gameState.fen
        if let result = await stockfish.evaluate(fen: currentFen, depth: AppConfig.engine.evalDepth) {
            evalScore = result.score
        }
    }

    func fetchBestResponseHint() async {
        let currentFen = gameState.fen
        if let result = await stockfish.evaluate(fen: currentFen, depth: AppConfig.engine.hintDepth) {
            bestResponseHint = result.bestMove
        }
    }

    func fetchBestResponseHintAndEval() async {
        let currentFen = gameState.fen
        let depth = max(AppConfig.engine.hintDepth, AppConfig.engine.evalDepth)
        if let result = await stockfish.evaluate(fen: currentFen, depth: depth) {
            bestResponseHint = result.bestMove
            evalScore = result.score
        }
    }

    // MARK: - Puzzle Stubs

    func loadPuzzles() async {}

    func puzzleUserMoved(from: String, to: String) {}

    // MARK: - Saved Session

    static func hasSavedSession() -> Bool {
        PersistenceService.shared.loadSessionState() != nil
    }

    static func savedSessionInfo() -> (openingID: String, lineID: String?)? {
        guard let state = PersistenceService.shared.loadSessionState(),
              let openingID = state["openingID"] as? String else { return nil }
        let lineID = state["lineID"] as? String
        return (openingID, lineID?.isEmpty == true ? nil : lineID)
    }

    // MARK: - Line Switching

    func switchToLine(_ line: OpeningLine) {
        activeLine = line
        activeLineID = line.id
        suggestedVariation = nil
    }

    // MARK: - Session End

    func endSession() {
        if mode.isSession {
            if mode.sessionMode == .practice {
                let moveHistory = gameState.moveHistory.map { $0.from + $0.to }
                variedOpponent?.recordPath(moveHistory)
            }
            saveProgress()
            sessionComplete = true
            PersistenceService.shared.clearSessionState()
            Task { await stockfish.stop() }
        }
    }

    func saveSessionToDisk() {
        guard mode.isSession, !sessionComplete, stats.totalUserMoves > 0 else { return }
        guard let opening = mode.opening else { return }
        let moveHistory = gameState.moveHistory.map { $0.from + $0.to }
        let state: [String: Any] = [
            "openingID": opening.id,
            "lineID": activeLineID ?? "",
            "fen": gameState.fen,
            "moveHistory": moveHistory,
            "movesOnBook": stats.movesOnBook,
            "totalUserMoves": stats.totalUserMoves,
            "isPro": isPro
        ]
        PersistenceService.shared.saveSessionState(state)
    }
}
