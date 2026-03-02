import Foundation
import SwiftUI
import ChessKit

func debugLog(_ message: String) {
    #if DEBUG
    let dateStr = ISO8601DateFormatter().string(from: Date())
    let line = "[\(dateStr)] \(message)\n"
    let tmp = FileManager.default.temporaryDirectory
    let logFile = tmp.appendingPathComponent("chesscoach_debug.log")
    if let handle = try? FileHandle(forWritingTo: logFile) {
        handle.seekToEndOfFile()
        if let data = line.data(using: .utf8) { handle.write(data) }
        handle.synchronizeFile()
        handle.closeFile()
    } else {
        try? line.data(using: .utf8)?.write(to: logFile)
    }
    #endif
}

enum BookStatus: Equatable {
    case onBook
    case userDeviated(expected: OpeningMove, atPly: Int)
    case opponentDeviated(expected: OpeningMove, playedSAN: String, atPly: Int)
    case offBook(since: Int)
}

enum SessionMode: String, Codable, Sendable {
    case guided
    case unguided
    case practice
}

struct SessionStats {
    var movesOnBook: Int = 0
    var totalUserMoves: Int = 0
    var deviationPly: Int?
    var deviatedBy: DeviatedBy?
    var restarts: Int = 0
    var moveScores: [PlanExecutionScore] = []

    enum DeviatedBy { case user, opponent }

    var accuracy: Double {
        guard totalUserMoves > 0 else { return 0 }
        return Double(movesOnBook) / Double(totalUserMoves)
    }

    var averagePES: Double {
        guard !moveScores.isEmpty else { return 0 }
        return Double(moveScores.map(\.total).reduce(0, +)) / Double(moveScores.count)
    }

    var pesCategory: ScoreCategory {
        ScoreCategory.from(score: Int(averagePES))
    }
}

@Observable
final class CoachingFeedEntry: Identifiable {
    nonisolated(unsafe) private static var counter = 0
    let id: Int
    let moveNumber: Int
    var whiteSAN: String?
    var blackSAN: String?
    var coaching: String?
    var whitePly: Int
    var blackPly: Int?
    var isDeviation: Bool
    var fen: String?
    var playedUCI: String?
    var expectedSAN: String?
    var expectedUCI: String?
    var explanation: String?
    var isExplaining: Bool = false

    init(moveNumber: Int, whitePly: Int) {
        CoachingFeedEntry.counter += 1
        self.id = CoachingFeedEntry.counter
        self.moveNumber = moveNumber
        self.whitePly = whitePly
        self.isDeviation = false
    }
}

struct PlySnapshot {
    let ply: Int
    let fen: String
    let moveHistory: [(from: String, to: String, promotion: PieceKind?)]
    let userCoachingText: String?
    let opponentCoachingText: String?
    let arrowFrom: String?
    let arrowTo: String?
    let hintSquare: String?
    let bookStatus: BookStatus
    let evalScore: Int
    let lastMovePES: PlanExecutionScore?
    let stats: SessionStats
    let feedEntries: [CoachingFeedEntry]
}

@Observable
@MainActor
final class SessionViewModel {
    let opening: Opening
    let gameState: GameState
    let sessionMode: SessionMode
    let stockfish: StockfishService
    let llmService: LLMService  // concrete for buildPrompt/boardStateSummary; conforms to TextGenerating
    private let curriculumService: CurriculumService
    private let coachingService: CoachingService
    private var maiaService: MaiaService?
    private let spacedRepScheduler: SpacedRepScheduler
    private var planScoringService: PlanScoringService?
    private let featureAccess: any FeatureAccessProviding
    private(set) var isPro: Bool = true  // kept for UI-only gating (paywall, badges)
    private(set) var showProUpgrade: Bool = false

    // Coach personality (resolved from opening tags)
    private(set) var coachPersonality: CoachPersonality = .defaultPersonality
    private(set) var personalityQuip: String?
    private(set) var showPersonalityQuip: Bool = false
    private var quipDismissTask: Task<Void, Never>?

    // Plan Execution Score state
    private(set) var lastMovePES: PlanExecutionScore?
    private(set) var currentLayer: LearningLayer = .understandPlan

    private var lastSessionMistakePlies: Set<Int> = []

    private var sessionStartDate: Date = Date()

    private(set) var arrowFrom: String?
    private(set) var arrowTo: String?

    private var consecutiveCorrectPlays: [String: Int] = [:]

    private(set) var coachingHistory: [(ply: Int, text: String)] = []

    private(set) var feedEntries: [CoachingFeedEntry] = []

    private var mistakeTracker = PersistenceService.shared.loadMistakeTracker()

    private var hintTimer: Task<Void, Never>?
    private(set) var hintSquare: String?

    // Active line being practiced (nil = legacy flat main line)
    private(set) var activeLine: OpeningLine?
    private var activeLineID: String?

    // Latest coaching per side
    private(set) var userCoachingText: String?
    private(set) var opponentCoachingText: String?

    // Track which coaching was updated most recently (true = user was last)
    private(set) var lastCoachingWasUser: Bool = false

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

    // Discovery mode (Phase 6)
    private(set) var branchPointOptions: [OpeningMove]?
    private(set) var discoveryMode = false
    private(set) var suggestedVariation: OpeningLine?

    private(set) var isThinking = false
    private(set) var isCoachingLoading = false
    private(set) var isModelLoading = true
    private(set) var sessionComplete = false
    private(set) var sessionResult: SessionResult?
    private var sessionGeneration = 0
    // ELO values are read once at init time from UserDefaults. This is intentional:
    // the session view is modal and there is no path for the user to reach Settings
    // while a session is in progress, so these values cannot become stale mid-session.
    private(set) var userELO: Int = UserDefaults.standard.object(forKey: AppSettings.Key.userELO) as? Int ?? 600
    private(set) var opponentELO: Int = UserDefaults.standard.object(forKey: AppSettings.Key.opponentELO) as? Int ?? 1200

    // Evaluation
    private(set) var evalScore: Int = 0  // centipawns, positive = white advantage

    // Opening guide
    private(set) var bookStatus: BookStatus = .onBook
    private(set) var bestResponseHint: String?
    private(set) var stats = SessionStats()

    // Haptic trigger: increments on each correct user move
    private(set) var correctMoveTrigger: Int = 0

    // Undo/Redo stacks
    private var undoStack: [PlySnapshot] = []
    private var redoStack: [PlySnapshot] = []

    // In-session replay
    private(set) var replayPly: Int? = nil
    private var replayGameState: GameState? = nil
    var isReplaying: Bool { replayPly != nil }
    var canUndo: Bool { undoStack.count >= 2 }
    var canRedo: Bool { !redoStack.isEmpty }

    var displayGameState: GameState { replayGameState ?? gameState }

    var moveHistorySAN: [String] {
        gameState.moveHistory.map { $0.from + $0.to }
    }

    var displayUserCoaching: String? {
        guard let ply = replayPly else { return userCoachingText }
        return undoStack.last(where: { $0.ply == ply })?.userCoachingText
    }

    var displayOpponentCoaching: String? {
        guard let ply = replayPly else { return opponentCoachingText }
        return undoStack.last(where: { $0.ply == ply })?.opponentCoachingText
    }

    var isOnBook: Bool { bookStatus == .onBook }

    var currentPhase: LearningPhase { curriculumService.phase }

    var isUserTurn: Bool {
        (opening.color == .white && gameState.isWhiteTurn) ||
        (opening.color == .black && !gameState.isWhiteTurn)
    }

    var moveCount: Int { gameState.plyCount }

    var bestResponseDescription: String? {
        guard let hint = bestResponseHint else { return nil }
        let to = String(hint.dropFirst(2).prefix(2))
        // Look up what piece is on the 'from' square
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

    private var activeMoves: [OpeningMove] {
        activeLine?.moves ?? opening.mainLine
    }

    var expectedNextMove: OpeningMove? {
        guard isOnBook, isUserTurn else { return nil }
        // In discovery mode, don't reveal the expected move
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

    init(opening: Opening, lineID: String? = nil, isPro: Bool = true, sessionMode: SessionMode = .guided, featureAccess: any FeatureAccessProviding = UnlockedAccess(), stockfish: StockfishService? = nil, llmService: LLMService? = nil) {
        self.isPro = isPro
        self.featureAccess = featureAccess
        self.sessionMode = sessionMode
        self.consecutiveCorrectPlays = UserDefaults.standard.dictionary(forKey: AppSettings.Key.consecutiveCorrect) as? [String: Int] ?? [:]
        self.opening = opening
        self.gameState = GameState()
        self.stockfish = stockfish ?? StockfishService()
        self.llmService = llmService ?? LLMService()
        self.spacedRepScheduler = SpacedRepScheduler()

        // Load per-line progress to determine phase
        self.activeLineID = lineID
        let resolvedLine: OpeningLine?
        let resolvedCurriculum: CurriculumService

        if let lineID {
            let line = opening.lines?.first { $0.id == lineID }
            resolvedLine = line
            let progress = PersistenceService.shared.loadProgress(forOpening: opening.id)
            let linePhase = progress.progress(forLine: lineID).currentPhase
            resolvedCurriculum = CurriculumService(opening: opening, activeLine: line, phase: linePhase)
        } else {
            resolvedLine = nil
            let progress = PersistenceService.shared.loadProgress(forOpening: opening.id)
            resolvedCurriculum = CurriculumService(opening: opening, activeLine: nil, phase: progress.currentPhase)
        }

        self.activeLine = resolvedLine
        self.curriculumService = resolvedCurriculum
        self.coachingService = CoachingService(llmService: self.llmService, curriculumService: resolvedCurriculum, featureAccess: featureAccess)
        self.coachPersonality = CoachPersonality.forOpening(opening)

        // Load current learning layer from mastery
        let mastery = PersistenceService.shared.loadMastery(forOpening: opening.id)
        self.currentLayer = mastery.currentLayer
    }

    // Engine status for debug display
    private(set) var maiaStatus: String = "…"
    private(set) var llmStatus: String = "…"
    private(set) var stockfishStatus: String = "…"

    func startSession() async {
        sessionStartDate = Date()
        debugLog("startSession() called")
        do {
            maiaService = try MaiaService()
            maiaStatus = "Maia 2"
            debugLog("Maia loaded successfully")
        } catch {
            maiaService = nil
            maiaStatus = "Stockfish (Maia failed)"
            debugLog("Maia init failed: \(error.localizedDescription)")
            #if DEBUG
            print("[ChessCoach] Maia init failed, falling back to Stockfish: \(error)")
            #endif
        }

        debugLog("Starting Stockfish...")
        await stockfish.start() // no-op if already started
        stockfishStatus = "Ready"
        debugLog("Stockfish ready")

        // Initialize PES scoring service
        planScoringService = PlanScoringService(llmService: llmService, stockfish: stockfish, featureAccess: featureAccess)

        if isPro {
            await llmService.detectProvider()
            let provider = await llmService.currentProvider
            let modelReady = await llmService.isModelReady

            if modelReady {
                // Already warmed up at app launch
                switch provider {
                case .onDevice: llmStatus = "On-Device (Qwen3-4B)"
                case .ollama: llmStatus = "Ollama"
                case .claude: llmStatus = "Claude API"
                }
                isModelLoading = false
            } else {
                switch provider {
                case .onDevice: llmStatus = "Loading coach..."
                case .ollama: llmStatus = "Ollama"
                case .claude: llmStatus = "Claude API"
                }

                if provider == .onDevice {
                    Task {
                        await llmService.warmUp()
                        llmStatus = "On-Device (Qwen3-4B)"
                        isModelLoading = false
                    }
                } else {
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

        // Show coach greeting
        showCoachQuip(coachPersonality.onGreeting.randomElement() ?? "Let's begin!")
    }

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
        let quip = coachPersonality.witticism(for: category)
        guard !quip.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            showCoachQuip(quip)
        }
    }

    private func showProactiveCoaching() {
        guard isOnBook, isUserTurn, !sessionComplete else {
            // Clear proactive coaching if it's not user's turn
            if !isUserTurn { userCoachingText = nil }
            return
        }
        if discoveryMode { return }

        // Unguided / practice (real conditions) mode: no arrows, no proactive coaching, no hints
        if sessionMode == .unguided || sessionMode == .practice {
            userCoachingText = nil
            arrowFrom = nil
            arrowTo = nil
            return
        }

        let ply = gameState.plyCount
        let moves = activeMoves
        guard ply < moves.count else { return }
        let nextMove = moves[ply]
        let lowerExplanation = nextMove.explanation.prefix(1).lowercased() + nextMove.explanation.dropFirst()
        let correctKey = "\(opening.id)/\(activeLineID ?? "main")/\(ply)"
        let correctCount = consecutiveCorrectPlays[correctKey] ?? 0

        if lastSessionMistakePlies.contains(ply) {
            userCoachingText = "You missed this last time — play \(nextMove.san) — \(lowerExplanation)"
        } else if correctCount >= 5 {
            userCoachingText = nextMove.san
        } else {
            userCoachingText = "Play \(nextMove.san) — \(lowerExplanation)"
        }

        let uci = nextMove.uci
        if uci.count >= 4 {
            arrowFrom = String(uci.prefix(2))
            arrowTo = String(uci.dropFirst(2).prefix(2))
        }

        startHintTimer(square: arrowTo)
        // Set up explain context so "Explain why" works before they move
        userExplainContext = ExplainContext(
            fen: gameState.fen,
            move: nextMove.uci,
            san: nextMove.san,
            ply: ply,
            moveHistory: gameState.moveHistory.map { $0.from + $0.to },
            coachingText: nextMove.explanation,
            hasPlayed: false
        )
    }

    private func showOffBookGuidance() {
        guard isUserTurn, !sessionComplete else { return }

        // In guided mode, show the Stockfish arrow
        if sessionMode == .guided, let hint = bestResponseHint, hint.count >= 4 {
            arrowFrom = String(hint.prefix(2))
            arrowTo = String(hint.dropFirst(2).prefix(2))
        }

        // Build guidance text
        if let bestMove = bestResponseDescription {
            userCoachingText = "You're on your own. Suggested: \(bestMove) — focus on development and king safety."
        } else {
            userCoachingText = "You're on your own. Focus on developing pieces and keeping your king safe."
        }
    }

    func userMoved(from: String, to: String) async {
        debugLog("userMoved: \(from)\(to)")
        let ply = gameState.plyCount - 1
        let uciMove = from + to
        let fenAfterMove = gameState.fen

        // Capture FEN before this move (reconstruct from history minus last move)
        let fenBeforeMove: String = {
            let tempState = GameState()
            for historyMove in gameState.moveHistory.dropLast() {
                _ = tempState.makeMoveUCI(historyMove.from + historyMove.to)
            }
            return tempState.fen
        }()

        // Clear proactive coaching (user consumed the guidance by playing)
        clearArrowAndHint()
        bestResponseHint = nil  // Clear stale hint — it was for the deviation position, not the current one
        userCoachingText = nil
        userExplanation = nil
        opponentExplanation = nil
        offBookExplanation = nil
        suggestedVariation = nil

        SoundService.shared.play(.move)
        SoundService.shared.hapticPiecePlaced()

        // Track stats
        stats.totalUserMoves += 1

        let moves = activeMoves

        if isOnBook {
            // Discovery mode: check if move matches ANY book continuation
            if discoveryMode {
                discoveryMode = false
                branchPointOptions = nil

                let moveHistory = gameState.moveHistory.map { $0.from + $0.to }
                let allMoves = moveHistory + [uciMove]

                if opening.isKnownContinuation(atPly: ply, move: uciMove, afterMoves: Array(moveHistory.prefix(ply))) {
                    stats.movesOnBook += 1; correctMoveTrigger += 1
                    // Check if this move leads to a different line
                    let matchingLines = opening.matchingLines(forMoveSequence: allMoves)
                    if let newLine = matchingLines.first(where: { $0.id != activeLine?.id }) {
                        suggestedVariation = newLine
                    }
                } else if ply < moves.count && moves[ply].uci != uciMove {
                    if let expected = ply < moves.count ? moves[ply] : nil {
                        bookStatus = .userDeviated(expected: expected, atPly: ply)
                        stats.deviationPly = ply
                        stats.deviatedBy = .user
                        lastSessionMistakePlies.insert(ply)
                        mistakeTracker.recordMistake(openingID: opening.id, lineID: activeLineID, ply: ply, expectedMove: expected.uci, playedMove: uciMove)
                        PersistenceService.shared.saveMistakeTracker(mistakeTracker)
                        // Schedule for spaced rep — use fenBeforeMove so review shows the position where the correct move should be played
                        spacedRepScheduler.addItem(openingID: opening.id, lineID: activeLineID, fen: fenBeforeMove, ply: ply, correctMove: expected.uci, playerColor: opening.color.rawValue)
                    }
                } else {
                    stats.movesOnBook += 1; correctMoveTrigger += 1
                }
            } else if ply < moves.count && moves[ply].uci != uciMove {
                // Standard deviation check
                if let expected = ply < moves.count ? moves[ply] : nil {
                    // Check if the move matches a known variation (branch detection)
                    let moveHistory = gameState.moveHistory.map { $0.from + $0.to }
                    if opening.isKnownContinuation(atPly: ply, move: uciMove, afterMoves: Array(moveHistory.prefix(ply))) {
                        stats.movesOnBook += 1; correctMoveTrigger += 1
                        let allMoves = moveHistory + [uciMove]
                        let matchingLines = opening.matchingLines(forMoveSequence: allMoves)
                        if let newLine = matchingLines.first(where: { $0.id != activeLine?.id }) {
                            suggestedVariation = newLine
                        }
                    } else {
                        bookStatus = .userDeviated(expected: expected, atPly: ply)
                        stats.deviationPly = ply
                        stats.deviatedBy = .user
                        lastSessionMistakePlies.insert(ply)
                        mistakeTracker.recordMistake(openingID: opening.id, lineID: activeLineID, ply: ply, expectedMove: expected.uci, playedMove: uciMove)
                        PersistenceService.shared.saveMistakeTracker(mistakeTracker)
                        // Schedule for spaced rep — use fenBeforeMove so review shows the position where the correct move should be played
                        spacedRepScheduler.addItem(openingID: opening.id, lineID: activeLineID, fen: fenBeforeMove, ply: ply, correctMove: expected.uci, playerColor: opening.color.rawValue)
                    }
                }
            } else {
                stats.movesOnBook += 1; correctMoveTrigger += 1
                // Correct play at a previously-failed position? Update spaced rep
                if let item = spacedRepScheduler.findItem(openingID: opening.id, ply: ply) {
                    spacedRepScheduler.review(itemID: item.id, quality: 4)
                }
                let correctKey = "\(opening.id)/\(activeLineID ?? "main")/\(ply)"
                consecutiveCorrectPlays[correctKey, default: 0] += 1
                UserDefaults.standard.set(consecutiveCorrectPlays, forKey: AppSettings.Key.consecutiveCorrect)

                SoundService.shared.hapticCorrectMove()
            }
        } else if case let .opponentDeviated(_, _, deviationPly) = bookStatus {
            // Off-book due to OPPONENT deviation — still credit the user for correct moves.
            if ply < moves.count && moves[ply].uci == uciMove {
                stats.movesOnBook += 1; correctMoveTrigger += 1
            }
            // Transition to offBook — user has responded to the deviation
            bookStatus = .offBook(since: deviationPly)
        } else if case .offBook = bookStatus {
            // Continuing off-book — just track stats
            if ply < moves.count && moves[ply].uci == uciMove {
                stats.movesOnBook += 1; correctMoveTrigger += 1
            }
        }

        // Skip updateEval here — makeOpponentMoveWithBatchedCoaching will eval
        // after the opponent moves. This saves a redundant Stockfish call.

        // Show the book explanation for the move they just played (same text as proactive coaching)
        let userSan: String?
        let isDeviation: Bool
        var expectedSAN: String?
        var expectedUCI: String?
        if ply < moves.count && moves[ply].uci == uciMove {
            let moveData = moves[ply]
            userSan = moveData.san
            let lower = moveData.explanation.prefix(1).lowercased() + moveData.explanation.dropFirst()
            userCoachingText = "\(moveData.san) — \(lower)"
            isDeviation = false
        } else {
            // User deviated — get SAN of the played move and explain what was expected
            let tempState = GameState(fen: fenBeforeMove)
            userSan = tempState.sanForUCI(uciMove)
            isDeviation = true
            if let expected = ply < moves.count ? moves[ply] : nil {
                let lower = expected.explanation.prefix(1).lowercased() + expected.explanation.dropFirst()
                userCoachingText = "Recommended move is \(expected.san) — \(lower)"
                expectedSAN = expected.san
                expectedUCI = expected.uci
            }
        }

        // Add to feed (move pairs)
        appendToFeed(
            ply: ply,
            san: userSan,
            coaching: userCoachingText,
            isDeviation: isDeviation,
            fen: fenAfterMove,
            playedUCI: uciMove,
            expectedSAN: expectedSAN,
            expectedUCI: expectedUCI
        )

        // Random personality quip (~28% chance)
        let category: MoveCategory = isDeviation ? .mistake : .goodMove
        maybeShowQuip(for: category)

        if sessionMode != .guided, currentLayer.rawValue >= LearningLayer.executePlan.rawValue {
            debugLog("Computing PES")
            if let pes = await computePES(forPly: ply, move: uciMove, fenBefore: fenBeforeMove, fenAfter: fenAfterMove) {
                lastMovePES = pes
                stats.moveScores.append(pes)
                debugLog("PES: \(pes.total) (\(pes.category.displayName)) — \(pes.reasoning.prefix(60))")
            }
            debugLog("PES done")
        }

        // Store context for explain — user already played this move
        userExplainContext = ExplainContext(
            fen: gameState.fen,
            move: uciMove,
            san: userSan,
            ply: ply,
            moveHistory: gameState.moveHistory.map { $0.from + $0.to },
            coachingText: userCoachingText ?? "",
            hasPlayed: true
        )

        if gameState.plyCount >= moves.count {
            // Session ending — last move of the line
            debugLog("Final user move — line complete")
            // Use the book explanation if available, otherwise keep PES reasoning
            if userCoachingText == nil || userCoachingText?.isEmpty == true {
                if ply < moves.count && moves[ply].uci == uciMove {
                    let explanation = moves[ply].explanation
                    let lower = explanation.prefix(1).lowercased() + explanation.dropFirst()
                    userCoachingText = "\(moves[ply].san) — \(lower)"
                }
            }
            SoundService.shared.play(.correct)
            SoundService.shared.hapticLineComplete()
            captureSnapshot()
            saveProgress()
            sessionComplete = true
            return
        }

        // If user deviated, pause here so they can see the deviation and press Undo
        // before the opponent responds. The opponent move happens when they press "Continue".
        if case let .userDeviated(expected, _) = bookStatus {
            SoundService.shared.play(.wrong)
            SoundService.shared.hapticDeviation()
            // In unguided mode, show what the book move was (feedback without pre-guidance)
            if sessionMode == .unguided {
                let lowerExplanation = expected.explanation.prefix(1).lowercased() + expected.explanation.dropFirst()
                userCoachingText = "The recommended move was \(expected.san) — \(lowerExplanation)"
            }
            captureSnapshot()
            return
        }

        captureSnapshot()
        if !sessionComplete {
            await makeOpponentMoveWithBatchedCoaching(userPly: ply, userMove: uciMove)
        }
    }

    func switchToLine(_ line: OpeningLine) {
        activeLine = line
        activeLineID = line.id
        suggestedVariation = nil
    }

    func retryLastMove() {
        sessionGeneration += 1
        gameState.undoLastMove()
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

        showProactiveCoaching()
    }

    // MARK: - Undo/Redo & Replay

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

    private func captureSnapshot() {
        let snapshot = PlySnapshot(
            ply: gameState.plyCount,
            fen: gameState.fen,
            moveHistory: gameState.moveHistory,
            userCoachingText: userCoachingText,
            opponentCoachingText: opponentCoachingText,
            arrowFrom: arrowFrom,
            arrowTo: arrowTo,
            hintSquare: hintSquare,
            bookStatus: bookStatus,
            evalScore: evalScore,
            lastMovePES: lastMovePES,
            stats: stats,
            feedEntries: feedEntries
        )
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    private func restoreFromSnapshot(_ snapshot: PlySnapshot) {
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

    func continueAfterDeviation() async {
        let ply = gameState.plyCount - 1
        let uciMove = gameState.moveHistory.last.map { $0.from + $0.to } ?? ""
        // Transition from userDeviated/opponentDeviated to offBook so the UI
        // stops showing the deviation card and shows off-book guidance instead.
        if case .userDeviated(_, let atPly) = bookStatus {
            bookStatus = .offBook(since: atPly)
        } else if case .opponentDeviated(_, _, let atPly) = bookStatus {
            bookStatus = .offBook(since: atPly)
        }
        await makeOpponentMoveWithBatchedCoaching(userPly: ply, userMove: uciMove)
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
        sessionResult = nil
        evalScore = 0
        discoveryMode = false
        branchPointOptions = nil
        suggestedVariation = nil
        lastMovePES = nil
        undoStack.removeAll()
        redoStack.removeAll()
        feedEntries.removeAll()
        replayPly = nil
        replayGameState = nil
        let restartCount = stats.restarts + 1
        stats = SessionStats()
        stats.restarts = restartCount

        if opening.color == .black {
            await makeOpponentMove()
        }

        showProactiveCoaching()
        captureSnapshot()
    }

    func requestExplanation(forUserMove: Bool) async {
        guard isPro else {
            showProUpgrade = true
            return
        }
        let ctx = forUserMove ? userExplainContext : opponentExplainContext
        guard let ctx else {
            #if DEBUG
            print("[ChessCoach] No explain context for \(forUserMove ? "user" : "opponent")")
            #endif
            return
        }

        #if DEBUG
        print("[ChessCoach] Starting explanation for \(forUserMove ? "user" : "opponent")")
        #endif

        if forUserMove { isExplainingUser = true } else { isExplainingOpponent = true }
        defer { if forUserMove { isExplainingUser = false } else { isExplainingOpponent = false } }

        let moveHistoryStr = buildMoveHistoryString()
        let studentColor = opening.color == .white ? "White" : "Black"
        let opponentColor = studentColor == "White" ? "Black" : "White"
        let boardState = LLMService.boardStateSummary(fen: ctx.fen, studentColor: studentColor)
        let occupied = LLMService.occupiedSquares(fen: ctx.fen)

        let perspective: String
        let moveDisplay = ctx.san ?? ctx.move
        let moveFraming: String

        if forUserMove {
            if ctx.hasPlayed {
                perspective = """
                The student plays \(studentColor). The student just played \(moveDisplay).
                When referring to \(studentColor) pieces, say "\(studentColor)'s knight" or "your knight".
                When referring to \(opponentColor) pieces, say "\(opponentColor)'s bishop" or "the opponent's bishop".
                Explain why this was a good move to play.
                """
                moveFraming = "The student just played: \(moveDisplay) (UCI: \(ctx.move))"
            } else {
                perspective = """
                The student plays \(studentColor). The student has NOT played this move yet — you are explaining WHY they should play it.
                When referring to \(studentColor) pieces, say "\(studentColor)'s knight" or "your knight".
                When referring to \(opponentColor) pieces, say "\(opponentColor)'s bishop" or "the opponent's bishop".
                Explain why this is the right move to play next.
                """
                moveFraming = "The recommended next move for you: \(moveDisplay) (UCI: \(ctx.move))"
            }
        } else {
            perspective = """
            This is the OPPONENT'S move. The opponent plays \(opponentColor).
            When referring to \(opponentColor) pieces (the opponent's), say "\(opponentColor)'s knight" or "the opponent's knight".
            When referring to \(studentColor) pieces (the student's), say "\(studentColor)'s bishop" or "your bishop".
            Explain what the opponent is trying to accomplish and how the student should respond.
            """
            moveFraming = "The opponent just played: \(moveDisplay) (UCI: \(ctx.move))"
        }

        let prompt = PromptCatalog.explanationPrompt(params: .init(
            openingName: opening.name,
            studentColor: studentColor,
            opponentColor: opponentColor,
            userELO: userELO,
            perspective: perspective,
            moveHistoryStr: moveHistoryStr,
            boardState: boardState,
            occupiedSquares: occupied,
            moveDisplay: moveDisplay,
            moveUCI: ctx.move,
            moveFraming: moveFraming,
            coachingText: ctx.coachingText,
            forUserMove: forUserMove
        ))

        do {
            #if DEBUG
            print("[ChessCoach] Calling LLM for explanation...")
            #endif
            let response = try await llmService.generate(prompt: prompt, maxTokens: AppConfig.tokens.explanation)
            #if DEBUG
            print("[ChessCoach] Got explanation: \(response.prefix(50))...")
            #endif
            let parsed = CoachingValidator.parse(response: response)
            let validated = CoachingValidator.validate(parsed: parsed, fen: ctx.fen) ?? parsed.text
            if forUserMove { userExplanation = validated } else { opponentExplanation = validated }
        } catch {
            #if DEBUG
            print("[ChessCoach] Explanation error: \(error)")
            #endif
            let fallback = "Couldn't get explanation right now. Try again."
            if forUserMove { userExplanation = fallback } else { opponentExplanation = fallback }
        }
    }

    func requestOffBookExplanation() async {
        guard isPro else {
            showProUpgrade = true
            return
        }
        guard !isExplainingOffBook else { return }
        isExplainingOffBook = true
        defer { isExplainingOffBook = false }

        let playedMove: String
        let expectedSan: String
        let expectedUci: String
        let who: String

        switch bookStatus {
        case let .userDeviated(expected, _):
            // Convert the played UCI to SAN by replaying to the position before the last move
            let history = gameState.moveHistory
            let uci = history.last.map { $0.from + $0.to } ?? "?"
            let tempState = GameState()
            for entry in history.dropLast() {
                tempState.makeMoveUCI(entry.from + entry.to)
            }
            playedMove = tempState.sanForUCI(uci) ?? uci
            expectedSan = expected.san
            expectedUci = expected.uci
            who = "You (the student)"
        case let .opponentDeviated(expected, playedSAN, _):
            playedMove = playedSAN
            expectedSan = expected.san
            expectedUci = expected.uci
            who = "The opponent"
        default:
            return
        }

        let currentFen = gameState.fen
        let moveHistoryStr = buildMoveHistoryString()
        let studentColor = opening.color == .white ? "White" : "Black"
        let opponentColor = studentColor == "White" ? "Black" : "White"

        var evalNote = ""
        if let result = await stockfish.evaluate(fen: currentFen, depth: AppConfig.engine.evalDepth) {
            let pawns = Double(result.score) / 100.0
            if abs(pawns) < 0.3 {
                evalNote = "The position is roughly equal — the deviation may be fine."
            } else if pawns > 0.3 {
                evalNote = "White has a slight advantage (+\(String(format: "%.1f", pawns)) pawns)."
            } else {
                evalNote = "Black has a slight advantage (\(String(format: "%.1f", pawns)) pawns)."
            }
        }

        let boardState = LLMService.boardStateSummary(fen: currentFen, studentColor: studentColor)
        let occupied = LLMService.occupiedSquares(fen: currentFen)

        let prompt = PromptCatalog.offBookExplanationPrompt(params: .init(
            openingName: opening.name,
            studentColor: studentColor,
            opponentColor: opponentColor,
            userELO: userELO,
            moveHistoryStr: moveHistoryStr,
            boardState: boardState,
            occupiedSquares: occupied,
            who: who,
            playedMove: playedMove,
            expectedSan: expectedSan,
            expectedUci: expectedUci,
            evalNote: evalNote
        ))

        do {
            let response = try await llmService.generate(prompt: prompt, maxTokens: AppConfig.tokens.explanation)
            let parsed = CoachingValidator.parse(response: response)
            offBookExplanation = CoachingValidator.validate(parsed: parsed, fen: currentFen) ?? parsed.text
        } catch {
            offBookExplanation = "Couldn't get explanation right now. Try again."
        }
    }

    func clearArrowAndHint() {
        arrowFrom = nil
        arrowTo = nil
        hintSquare = nil
        hintTimer?.cancel()
        hintTimer = nil
    }

    private func startHintTimer(square: String?) {
        hintTimer?.cancel()
        guard let square else { return }
        hintTimer = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            hintSquare = square
            // Auto-clear hint after 2 seconds
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            hintSquare = nil
        }
    }

    func dismissProUpgrade() {
        showProUpgrade = false
    }

    func updateProStatus(_ isPro: Bool) {
        self.isPro = isPro
    }

    func endSession() {
        saveProgress()
        sessionComplete = true
        PersistenceService.shared.clearSessionState()
        Task {
            await stockfish.stop()
        }
    }

    // MARK: - Session Auto-Save

    func saveSessionToDisk() {
        guard !sessionComplete, stats.totalUserMoves > 0 else { return }
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

    static func hasSavedSession() -> Bool {
        PersistenceService.shared.loadSessionState() != nil
    }

    static func savedSessionInfo() -> (openingID: String, lineID: String?)? {
        guard let state = PersistenceService.shared.loadSessionState(),
              let openingID = state["openingID"] as? String else { return nil }
        let lineID = state["lineID"] as? String
        return (openingID, lineID?.isEmpty == true ? nil : lineID)
    }

    static func clearSavedSession() {
        PersistenceService.shared.clearSessionState()
    }

    private func saveProgress() {
        guard stats.totalUserMoves > 0 else { return }
        let input = SessionProgressInput(
            opening: opening,
            activeLineID: activeLineID,
            activeMoves: activeMoves,
            stats: stats,
            sessionMode: sessionMode,
            sessionStartDate: sessionStartDate,
            gameState: gameState,
            spacedRepScheduler: spacedRepScheduler,
            currentLayer: currentLayer
        )
        let output = SessionProgressTracker.saveProgress(input: input)
        sessionResult = output.sessionResult
        currentLayer = output.updatedLayer
    }

    // MARK: - Private

    private func makeOpponentMove() async {
        isThinking = true
        defer { isThinking = false }

        let gen = sessionGeneration
        let ply = gameState.plyCount
        let clock = ContinuousClock()
        let start = clock.now

        var computedMove: String?
        var isForced = false

        if let forcedMove = curriculumService.getMaiaOverride(atPly: ply) {
            computedMove = forcedMove
            isForced = true
        } else if let maia = maiaService {
            do {
                let legalUCI = gameState.legalMoves.map(\.description)
                let history = gameState.moveHistory.map {
                    "\($0.from)\($0.to)\($0.promotion?.rawValue ?? "")"
                }
                let predictions = try await maia.predictMove(
                    fen: gameState.fen,
                    legalMoves: legalUCI,
                    eloSelf: opponentELO,
                    eloOppo: userELO
                )
                let top3 = predictions.prefix(3).map { "\($0.move) (\(String(format: "%.1f%%", $0.probability * 100)))" }
                #if DEBUG
                print("[ChessCoach] Maia ELO \(opponentELO) top moves: \(top3.joined(separator: ", "))")
                #endif
                computedMove = try await maia.sampleMove(
                    fen: gameState.fen,
                    legalMoves: legalUCI,
                    eloSelf: opponentELO,
                    eloOppo: userELO,
                    recentMoves: history
                )
                #if DEBUG
                print("[ChessCoach] Maia selected: \(computedMove ?? "nil")")
                #endif
            } catch {
                #if DEBUG
                print("[ChessCoach] Maia failed, falling back to Stockfish: \(error)")
                #endif
            }
        }

        guard gen == sessionGeneration else { return }

        if computedMove == nil {
            if let result = await stockfish.evaluate(fen: gameState.fen, depth: AppConfig.engine.opponentMoveDepth) {
                computedMove = result.bestMove
            }
        }

        guard gen == sessionGeneration else { return }

        guard let move = computedMove else {
            opponentCoachingText = "Opponent couldn't find a move. Try restarting."
            return
        }

        // Skip artificial delay for forced book moves (no engine ran)
        if !isForced {
            let minimumDelay = Duration.seconds(Double.random(in: 1.0...3.0))
            let elapsed = clock.now - start
            if elapsed < minimumDelay {
                do {
                    try await Task.sleep(for: minimumDelay - elapsed)
                } catch {
                    return
                }
            }
        }

        guard gen == sessionGeneration else { return }

        let moves = activeMoves
        if isOnBook && ply < moves.count && moves[ply].uci != move {
            if let expected = ply < moves.count ? moves[ply] : nil {
                let san = gameState.sanForUCI(move) ?? move
                bookStatus = .opponentDeviated(expected: expected, playedSAN: san, atPly: ply)
                stats.deviationPly = ply
                stats.deviatedBy = .opponent
            }
        }

        let moveSucceeded = gameState.makeMoveUCI(move)
        guard moveSucceeded else {
            #if DEBUG
            print("[ChessCoach] makeMoveUCI failed for \(move) — position may have changed")
            #endif
            return
        }

        // Fetch fresh hint whenever we're off-book
        let isOffBookHere: Bool = {
            switch bookStatus {
            case .opponentDeviated: return true
            case .offBook: return true
            default: return false
            }
        }()
        if isOffBookHere {
            await fetchBestResponseHint()
        }

        guard gen == sessionGeneration else { return }

        // Check for discovery mode opportunity (Phase 6)
        checkDiscoveryMode()

        // Use book explanation for on-book opponent moves; only call LLM for off-book
        let moves2 = activeMoves
        if isOnBook && ply < moves2.count && moves2[ply].uci == move {
            let studentColor = opening.color == .white ? "White" : "Black"
            let opponentColor = studentColor == "White" ? "Black" : "White"
            opponentCoachingText = "\(opponentColor) plays \(moves2[ply].san) — \(moves2[ply].explanation.prefix(1).lowercased())\(moves2[ply].explanation.dropFirst())"
            lastCoachingWasUser = false
        } else {
            await generateCoaching(forPly: ply, move: move, isUserMove: false)
        }
        await updateEval()

        let opponentSan = (isOnBook && ply < moves2.count && moves2[ply].uci == move) ? moves2[ply].san : nil
        opponentExplainContext = ExplainContext(
            fen: gameState.fen,
            move: move,
            san: opponentSan,
            ply: ply,
            moveHistory: gameState.moveHistory.map { $0.from + $0.to },
            coachingText: opponentCoachingText ?? "",
            hasPlayed: true
        )

        // Add opponent move to feed (completes the move pair)
        appendToFeed(ply: ply, san: opponentSan, coaching: opponentCoachingText, isDeviation: !isOnBook, fen: gameState.fen)

        // Show proactive coaching or off-book guidance
        if isOffBookHere {
            showOffBookGuidance()
        } else {
            showProactiveCoaching()
        }
    }

    private func computeOpponentMove() async -> (move: String, isForced: Bool)? {
        let ply = gameState.plyCount
        var computedMove: String?

        if let forcedMove = curriculumService.getMaiaOverride(atPly: ply) {
            return (forcedMove, true)
        } else if let maia = maiaService {
            do {
                let legalUCI = gameState.legalMoves.map(\.description)
                let history = gameState.moveHistory.map {
                    "\($0.from)\($0.to)\($0.promotion?.rawValue ?? "")"
                }
                let predictions = try await maia.predictMove(
                    fen: gameState.fen,
                    legalMoves: legalUCI,
                    eloSelf: opponentELO,
                    eloOppo: userELO
                )
                let top3 = predictions.prefix(3).map { "\($0.move) (\(String(format: "%.1f%%", $0.probability * 100)))" }
                #if DEBUG
                print("[ChessCoach] Maia ELO \(opponentELO) top moves: \(top3.joined(separator: ", "))")
                #endif
                computedMove = try await maia.sampleMove(
                    fen: gameState.fen,
                    legalMoves: legalUCI,
                    eloSelf: opponentELO,
                    eloOppo: userELO,
                    recentMoves: history
                )
                #if DEBUG
                print("[ChessCoach] Maia selected: \(computedMove ?? "nil")")
                #endif
            } catch {
                #if DEBUG
                print("[ChessCoach] Maia failed, falling back to Stockfish: \(error)")
                #endif
            }
        }

        if computedMove == nil {
            #if DEBUG
            print("[ChessCoach] Maia unavailable, using Stockfish fallback")
            #endif
            if let result = await stockfish.evaluate(fen: gameState.fen, depth: AppConfig.engine.opponentMoveDepth) {
                computedMove = result.bestMove
            }
        }

        guard let move = computedMove else { return nil }
        return (move, false)
    }

    private func makeOpponentMoveWithBatchedCoaching(userPly: Int, userMove: String) async {
        isThinking = true
        defer { isThinking = false }

        let gen = sessionGeneration
        let clock = ContinuousClock()
        let start = clock.now

        // 1. Compute opponent move
        guard let opponentResult = await computeOpponentMove() else {
            opponentCoachingText = "Opponent couldn't find a move. Try restarting."
            // Still generate user coaching via single call
            await generateCoaching(forPly: userPly, move: userMove, isUserMove: true)
            return
        }
        let opponentMove = opponentResult.move
        let opponentIsForced = opponentResult.isForced
        guard gen == sessionGeneration else { return }

        let opponentPly = gameState.plyCount
        let userFen = gameState.fen

        // 2. For opponent's book moves, use the hardcoded explanation directly.
        //    Only call the LLM for deviations or off-book opponent moves.
        let opponentBookExplanation: String? = {
            let moves = activeMoves
            if isOnBook && opponentPly < moves.count && moves[opponentPly].uci == opponentMove {
                let studentColor = opening.color == .white ? "White" : "Black"
                let opponentColor = studentColor == "White" ? "Black" : "White"
                return "\(opponentColor) plays \(moves[opponentPly].san) — \(moves[opponentPly].explanation.prefix(1).lowercased())\(moves[opponentPly].explanation.dropFirst())"
            }
            return nil
        }()

        // 3. Fire LLM coaching concurrently — don't block opponent move on it.
        //    Use post-move FEN so the LLM sees the board after the opponent played.
        var coachingTask: Task<String?, Never>?
        if opponentBookExplanation == nil {
            isCoachingLoading = true
            let moveHistoryStr = buildMoveHistoryString()
            let studentColor = opening.color == .white ? "White" : "Black"
            let postMoveFen: String = {
                let tempState = GameState(fen: userFen)
                _ = tempState.makeMoveUCI(opponentMove)
                return tempState.fen
            }()
            // Look up named opponent response for variation coaching
            let movesSoFar = gameState.moveHistory.dropLast().map { "\($0.from)\($0.to)" }
            var responseName: String?
            var responseAdjustment: String?
            if let catalogue = opening.opponentResponses,
               let response = catalogue.matchResponse(moveUCI: opponentMove, afterMoves: Array(movesSoFar)) {
                responseName = response.name
                responseAdjustment = response.planAdjustment
            }

            let capturedGen = gen
            let coaching = coachingService
            coachingTask = Task {
                guard capturedGen == self.sessionGeneration else { return nil }
                return await coaching.getCoaching(
                    fen: postMoveFen,
                    lastMove: opponentMove,
                    scoreBefore: 0,
                    scoreAfter: 0,
                    ply: opponentPly,
                    userELO: self.userELO,
                    moveHistory: moveHistoryStr,
                    isUserMove: false,
                    studentColor: studentColor,
                    matchedResponseName: responseName,
                    matchedResponseAdjustment: responseAdjustment
                )
            }
        }

        guard gen == sessionGeneration else { return }

        // 4. Apply thinking delay (skip for forced book moves)
        if !opponentIsForced {
            let minimumDelay = Duration.seconds(Double.random(in: 1.0...3.0))
            let elapsed = clock.now - start
            if elapsed < minimumDelay {
                do {
                    try await Task.sleep(for: minimumDelay - elapsed)
                } catch {
                    return
                }
            }
        }
        guard gen == sessionGeneration else { return }

        // 6. Check for deviation and apply opponent move
        let moves = activeMoves
        if isOnBook && opponentPly < moves.count && moves[opponentPly].uci != opponentMove {
            if let expected = opponentPly < moves.count ? moves[opponentPly] : nil {
                let san = gameState.sanForUCI(opponentMove) ?? opponentMove
                bookStatus = .opponentDeviated(expected: expected, playedSAN: san, atPly: opponentPly)
                stats.deviationPly = opponentPly
                stats.deviatedBy = .opponent
            }
        }

        let moveSucceeded = gameState.makeMoveUCI(opponentMove)
        guard moveSucceeded else {
            #if DEBUG
            print("[ChessCoach] makeMoveUCI failed for \(opponentMove)")
            #endif
            return
        }

        // Fetch fresh hint whenever we're off-book (initial deviation or continuing)
        let isOffBook: Bool = {
            switch bookStatus {
            case .opponentDeviated: return true
            case .offBook: return true
            default: return false
            }
        }()

        // Show opponent coaching — book explanation is instant, LLM arrives async
        if let opponentBookExplanation {
            opponentCoachingText = opponentBookExplanation
            lastCoachingWasUser = false
        } else if let coachingTask {
            // Don't block — coaching text appears when LLM finishes.
            // Guard with both session generation and ply count so a stale
            // result doesn't overwrite coaching from a later move.
            let plyAtRequest = gameState.plyCount
            Task { [gen] in
                let llmCoaching = await coachingTask.value
                guard gen == self.sessionGeneration,
                      self.gameState.plyCount == plyAtRequest else {
                    self.isCoachingLoading = false
                    return
                }
                self.isCoachingLoading = false
                if let llmCoaching {
                    self.opponentCoachingText = llmCoaching
                    self.lastCoachingWasUser = false
                }
            }
        }

        let batchedOpponentSan: String? = {
            let moves = activeMoves
            if opponentPly < moves.count && moves[opponentPly].uci == opponentMove {
                return moves[opponentPly].san
            }
            return nil
        }()
        opponentExplainContext = ExplainContext(
            fen: gameState.fen,
            move: opponentMove,
            san: batchedOpponentSan,
            ply: opponentPly,
            moveHistory: gameState.moveHistory.map { $0.from + $0.to },
            coachingText: opponentCoachingText ?? "",
            hasPlayed: true
        )

        // Add opponent move to feed (completes the move pair)
        appendToFeed(ply: opponentPly, san: batchedOpponentSan, coaching: opponentCoachingText, isDeviation: !isOnBook, fen: gameState.fen)

        // Check if the line is complete after opponent's move
        if gameState.plyCount >= moves.count {
            captureSnapshot()
            saveProgress()
            sessionComplete = true
            return
        }

        checkDiscoveryMode()

        // Single Stockfish call for both hint and eval (saves a redundant search)
        if isOffBook {
            await fetchBestResponseHintAndEval()
        } else {
            await updateEval()
        }

        guard gen == sessionGeneration else { return }

        // Show proactive coaching or off-book guidance for the user's next move
        if isOffBook {
            showOffBookGuidance()
        } else {
            showProactiveCoaching()
        }
        captureSnapshot()
    }

    /// Check if we should enter discovery mode at current position.
    private func checkDiscoveryMode() {
        guard isOnBook else { return }
        guard curriculumService.shouldDiscover(atPly: gameState.plyCount) else { return }

        let options = curriculumService.allBookMoves(atPly: gameState.plyCount)
        if options.count > 1 {
            discoveryMode = true
            branchPointOptions = options
        }
    }

    private func fetchBestResponseHint() async {
        let currentFen = gameState.fen
        if let result = await stockfish.evaluate(fen: currentFen, depth: AppConfig.engine.hintDepth) {
            bestResponseHint = result.bestMove
        }
    }

    private func fetchBestResponseHintAndEval() async {
        let currentFen = gameState.fen
        let depth = max(AppConfig.engine.hintDepth, AppConfig.engine.evalDepth)
        if let result = await stockfish.evaluate(fen: currentFen, depth: depth) {
            bestResponseHint = result.bestMove
            evalScore = result.score
        }
    }

    private func updateEval() async {
        // Skip eval when on-book — known opening positions don't need engine analysis
        guard !isOnBook else { return }
        let currentFen = gameState.fen
        if let result = await stockfish.evaluate(fen: currentFen, depth: AppConfig.engine.evalDepth) {
            evalScore = result.score
        }
    }

    private func computePES(forPly ply: Int, move: String, fenBefore: String, fenAfter: String) async -> PlanExecutionScore? {
        guard let planScoringService else { return nil }

        let playerIsWhite = opening.color == .white

        // Gather Maia predictions for this position
        var maiaTopMoves: [(move: String, probability: Double)] = []
        if let maia = maiaService {
            do {
                let tempState = GameState(fen: fenBefore)
                let legalUCI = tempState.legalMoves.map(\.description)
                let predictions = try await maia.predictMove(
                    fen: fenBefore,
                    legalMoves: legalUCI,
                    eloSelf: userELO,
                    eloOppo: opponentELO
                )
                maiaTopMoves = predictions.prefix(5).map { ($0.move, Double($0.probability)) }
            } catch {
                #if DEBUG
                print("[ChessCoach] Maia predictions for PES failed: \(error)")
                #endif
            }
        }

        // Gather Stockfish top moves — skip when off-book to reduce Stockfish calls
        let sfTopMoves: [(move: String, score: Int)]
        if isOnBook {
            sfTopMoves = await stockfish.topMoves(fen: fenBefore, count: 3, depth: AppConfig.engine.pesTopMovesDepth)
        } else {
            sfTopMoves = [] // off-book: topMoves not needed, soundness eval is enough
        }

        // Get Polyglot weights from the opening tree
        let moveHistory = gameState.moveHistory.dropLast().map { $0.from + $0.to }
        let siblings = opening.childNodes(afterMoves: Array(moveHistory))
        let (moveWeight, allWeights) = PopularityService.lookupWeights(move: move, siblings: siblings)

        // Get SAN for the move (look in active moves or fallback)
        let moveSAN: String
        if ply < activeMoves.count && activeMoves[ply].uci == move {
            moveSAN = activeMoves[ply].san
        } else {
            moveSAN = move // fallback to UCI
        }

        let moveHistoryStr = buildMoveHistoryString()

        // Determine if this is the exact book move the app recommended
        let isBookMove = ply < activeMoves.count && activeMoves[ply].uci == move

        return await planScoringService.scoreMoveForPlan(
            fen: fenAfter,
            fenBeforeMove: fenBefore,
            move: move,
            moveSAN: moveSAN,
            opening: opening,
            plan: opening.plan,
            ply: ply,
            playerIsWhite: playerIsWhite,
            userELO: userELO,
            moveHistory: moveHistoryStr,
            polyglotMoveWeight: moveWeight,
            polyglotAllWeights: allWeights,
            maiaTopMoves: maiaTopMoves,
            stockfishTopMoves: sfTopMoves,
            isBookMove: isBookMove
        )
    }

    private func generateCoaching(forPly ply: Int, move: String, isUserMove: Bool) async {
        isCoachingLoading = true
        defer { isCoachingLoading = false }

        let moveHistoryStr = buildMoveHistoryString()

        // Look up named opponent response for variation coaching
        var responseName: String?
        var responseAdjustment: String?
        if !isUserMove, let catalogue = opening.opponentResponses {
            let movesSoFar = gameState.moveHistory.dropLast().map { "\($0.from)\($0.to)" }
            if let response = catalogue.matchResponse(moveUCI: move, afterMoves: Array(movesSoFar)) {
                responseName = response.name
                responseAdjustment = response.planAdjustment
            }
        }

        let text = await coachingService.getCoaching(
            fen: gameState.fen,
            lastMove: move,
            scoreBefore: 0,
            scoreAfter: 0,
            ply: ply,
            userELO: userELO,
            moveHistory: moveHistoryStr,
            isUserMove: isUserMove,
            studentColor: opening.color == .white ? "White" : "Black",
            matchedResponseName: responseName,
            matchedResponseAdjustment: responseAdjustment
        )

        if let text {
            if isUserMove {
                userCoachingText = text
            } else {
                opponentCoachingText = text
            }
            lastCoachingWasUser = isUserMove
            coachingHistory.append((ply: ply, text: text))
        }
    }

    // MARK: - Feed Management

    private func appendToFeed(
        ply: Int,
        san: String?,
        coaching: String?,
        isDeviation: Bool,
        fen: String? = nil,
        playedUCI: String? = nil,
        expectedSAN: String? = nil,
        expectedUCI: String? = nil
    ) {
        SessionFeedManager.appendToFeed(
            entries: &feedEntries,
            ply: ply,
            san: san,
            coaching: coaching,
            isDeviation: isDeviation,
            fen: fen,
            playedUCI: playedUCI,
            expectedSAN: expectedSAN,
            expectedUCI: expectedUCI
        )
    }

    func requestExplanationForEntry(_ entry: CoachingFeedEntry) async {
        guard isPro else {
            showProUpgrade = true
            return
        }
        await SessionFeedManager.requestExplanationForEntry(
            entry,
            opening: opening,
            userELO: userELO,
            evalScore: evalScore,
            moveHistoryStr: buildMoveHistoryString(),
            llmService: llmService,
            userExplainContext: userExplainContext,
            opponentExplainContext: opponentExplainContext
        )
    }

    private func buildMoveHistoryString() -> String {
        let bookMoves = activeMoves
        // Replay from the starting position to convert each UCI move to proper SAN
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
                // Convert UCI to SAN at the correct position (not current position)
                result += replay.sanForUCI(uci) ?? uci
            }
            replay.makeMoveUCI(uci)
            result += " "
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Supporting Types

struct ExplainContext {
    let fen: String
    let move: String        // UCI (e.g. "c7c5")
    let san: String?        // SAN (e.g. "c5") — helps LLM identify the piece
    let ply: Int
    let moveHistory: [String]
    let coachingText: String
    let hasPlayed: Bool     // true if the user already played this move
}
