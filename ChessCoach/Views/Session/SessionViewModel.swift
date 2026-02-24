import Foundation
import ChessKit

/// Debug log that writes to a file (survives stdout redirect + crash)
func debugLog(_ message: String) {
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
}

enum BookStatus: Equatable {
    case onBook
    case userDeviated(expected: OpeningMove, atPly: Int)
    case opponentDeviated(expected: OpeningMove, played: String, atPly: Int)
}

/// Training pipeline mode for SessionView.
enum SessionMode: String, Codable, Sendable {
    case guided    // Stage 2: arrows ON, proactive coaching ON, hint timer ON
    case unguided  // Stage 3: arrows OFF, coaching OFF, but deviation feedback ON
    case practice  // Stage 4: mixed practice across all lines (handled by PracticeOpeningView)
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
    let sessionMode: SessionMode
    private let stockfish: StockfishService
    private let llmService: LLMService
    private let curriculumService: CurriculumService
    private let coachingService: CoachingService
    private var maiaService: MaiaService?
    private let spacedRepScheduler: SpacedRepScheduler
    private(set) var isPro: Bool = true
    private(set) var showProUpgrade: Bool = false

    // Mistake plies from last session (for smarter restart - improvement 29)
    private var lastSessionMistakePlies: Set<Int> = []

    // Session timing
    private var sessionStartDate: Date = Date()

    // Move arrow overlay (improvement 1)
    private(set) var arrowFrom: String?
    private(set) var arrowTo: String?

    // "I Know This" skip tracking (improvement 23)
    // Track consecutive correct plays per ply per line (persisted in UserDefaults)
    private var consecutiveCorrectPlays: [String: Int] = [:]  // "openingID/lineID/ply" -> count

    // Coaching history for replay (improvement 5)
    private(set) var coachingHistory: [(ply: Int, text: String)] = []

    // Mistake tracker (improvement 2)
    private var mistakeTracker = PersistenceService.shared.loadMistakeTracker()

    // Pulsing hint after delay (improvement 21)
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
    private(set) var sessionComplete = false
    private(set) var sessionResult: SessionResult?
    private var sessionGeneration = 0
    private(set) var userELO: Int = UserDefaults.standard.object(forKey: "user_elo") as? Int ?? 600
    private(set) var opponentELO: Int = UserDefaults.standard.object(forKey: "opponent_elo") as? Int ?? 1200

    // Evaluation
    private(set) var evalScore: Int = 0  // centipawns, positive = white advantage

    // Opening guide
    private(set) var bookStatus: BookStatus = .onBook
    private(set) var bestResponseHint: String?
    private(set) var stats = SessionStats()

    // Haptic trigger: increments on each correct user move
    private(set) var correctMoveTrigger: Int = 0

    var isOnBook: Bool { bookStatus == .onBook }

    var currentPhase: LearningPhase { curriculumService.phase }

    var isUserTurn: Bool {
        (opening.color == .white && gameState.isWhiteTurn) ||
        (opening.color == .black && !gameState.isWhiteTurn)
    }

    var moveCount: Int { gameState.plyCount }

    /// Human-readable best response (e.g. "knight to f3" instead of "g1f3")
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

    /// The moves to check against — active line or main line.
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

    /// Eval as a fraction from -1.0 (black winning) to 1.0 (white winning)
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

    /// Initialize with a specific line (new tree-based flow).
    init(opening: Opening, lineID: String? = nil, isPro: Bool = true, sessionMode: SessionMode = .guided) {
        self.isPro = isPro
        self.sessionMode = sessionMode
        // Load "I Know This" data (improvement 23)
        self.consecutiveCorrectPlays = UserDefaults.standard.dictionary(forKey: "chess_coach_consecutive_correct") as? [String: Int] ?? [:]
        self.opening = opening
        self.gameState = GameState()
        self.stockfish = StockfishService()
        self.llmService = LLMService()
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
        self.coachingService = CoachingService(llmService: llmService, curriculumService: resolvedCurriculum)
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
            print("[ChessCoach] Maia init failed, falling back to Stockfish: \(error)")
        }

        debugLog("Starting Stockfish...")
        await stockfish.start()
        stockfishStatus = "Ready"
        debugLog("Stockfish ready")

        await llmService.detectProvider()
        let provider = await llmService.currentProvider
        switch provider {
        case .onDevice: llmStatus = "On-Device (Qwen3-4B)"
        case .ollama: llmStatus = "Ollama"
        case .claude: llmStatus = "Claude API"
        }

        if opening.color == .black {
            await makeOpponentMove()
        }

        showProactiveCoaching()
    }

    /// Show the next book move and its explanation BEFORE the user plays.
    /// Uses the hardcoded opening explanation — no LLM, no hallucinations.
    /// In `.unguided` mode, skips arrows, coaching text, and hint timer entirely.
    private func showProactiveCoaching() {
        guard isOnBook, isUserTurn, !sessionComplete else {
            // Clear proactive coaching if it's not user's turn
            if !isUserTurn { userCoachingText = nil }
            return
        }
        if discoveryMode { return }

        // Unguided mode: no arrows, no proactive coaching, no hints
        if sessionMode == .unguided {
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
        // Improvement 23: Abbreviated coaching if user knows this ply well
        let correctKey = "\(opening.id)/\(activeLineID ?? "main")/\(ply)"
        let correctCount = consecutiveCorrectPlays[correctKey] ?? 0

        // Improvement 29: prefix with mistake reminder if this ply was missed last session
        if lastSessionMistakePlies.contains(ply) {
            userCoachingText = "You missed this last time — play \(nextMove.san) — \(lowerExplanation)"
        } else if correctCount >= 5 {
            // Improvement 23: Abbreviated — user knows this
            userCoachingText = nextMove.san
        } else {
            userCoachingText = "Play \(nextMove.san) — \(lowerExplanation)"
        }

        // Improvement 1: Set arrow overlay from proactive coaching move data
        let uci = nextMove.uci
        if uci.count >= 4 {
            arrowFrom = String(uci.prefix(2))
            arrowTo = String(uci.dropFirst(2).prefix(2))
        }

        // Improvement 21: Start pulsing hint timer (8 seconds)
        startHintTimer(square: arrowTo)
        // Set up explain context so "Explain why" works before they move
        userExplainContext = ExplainContext(
            fen: gameState.fen,
            move: nextMove.uci,
            ply: ply,
            moveHistory: gameState.moveHistory.map { $0.from + $0.to },
            coachingText: nextMove.explanation
        )
    }

    func userMoved(from: String, to: String) async {
        debugLog("userMoved: \(from)\(to)")
        let ply = gameState.plyCount - 1
        let uciMove = from + to

        // Clear proactive coaching (user consumed the guidance by playing)
        clearArrowAndHint()
        userCoachingText = nil
        userExplanation = nil
        opponentExplanation = nil
        offBookExplanation = nil
        suggestedVariation = nil

        // Sound & haptics (improvements 10, 11)
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
                        // Schedule for spaced rep
                        spacedRepScheduler.addItem(openingID: opening.id, lineID: activeLineID, fen: gameState.fen, ply: ply, correctMove: expected.uci)
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
                        // Schedule for spaced rep
                        spacedRepScheduler.addItem(openingID: opening.id, lineID: activeLineID, fen: gameState.fen, ply: ply, correctMove: expected.uci)
                    }
                }
            } else {
                stats.movesOnBook += 1; correctMoveTrigger += 1
                // Correct play at a previously-failed position? Update spaced rep
                if let item = spacedRepScheduler.findItem(openingID: opening.id, ply: ply) {
                    spacedRepScheduler.review(itemID: item.id, quality: 4)
                }
                // Improvement 23: Track consecutive correct plays
                let correctKey = "\(opening.id)/\(activeLineID ?? "main")/\(ply)"
                consecutiveCorrectPlays[correctKey, default: 0] += 1
                UserDefaults.standard.set(consecutiveCorrectPlays, forKey: "chess_coach_consecutive_correct")

                SoundService.shared.hapticCorrectMove()
            }
        } else if case .opponentDeviated = bookStatus {
            // Off-book due to OPPONENT deviation — still credit the user for correct moves.
            // Check if the user's move matches what the line expects at this ply.
            if ply < moves.count && moves[ply].uci == uciMove {
                stats.movesOnBook += 1; correctMoveTrigger += 1
            }
        }

        debugLog("Updating eval after user move")
        await updateEval()
        debugLog("Eval updated")

        // Store context for explain
        userExplainContext = ExplainContext(
            fen: gameState.fen,
            move: uciMove,
            ply: ply,
            moveHistory: gameState.moveHistory.map { $0.from + $0.to },
            coachingText: userCoachingText ?? ""
        )

        if gameState.plyCount >= moves.count {
            // Session ending — no opponent move, just generate single coaching
            debugLog("Generating coaching for final user move")
            await generateCoaching(forPly: ply, move: uciMove, isUserMove: true)
            SoundService.shared.play(.correct)
            SoundService.shared.hapticLineComplete()
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
                userCoachingText = "The book move was \(expected.san) — \(lowerExplanation)"
            }
            return
        }

        if !sessionComplete {
            await makeOpponentMoveWithBatchedCoaching(userPly: ply, userMove: uciMove)
        }
    }

    /// Switch to practicing a different line mid-session.
    func switchToLine(_ line: OpeningLine) {
        activeLine = line
        activeLineID = line.id
        suggestedVariation = nil
    }

    /// Undo the user's last move so they can try again from the same position.
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

        if case .userDeviated = bookStatus {
            bookStatus = .onBook
        }

        if stats.totalUserMoves > 0 {
            stats.totalUserMoves -= 1
        }

        showProactiveCoaching()
    }

    /// Continue playing after a deviation — make the opponent's response move.
    func continueAfterDeviation() async {
        let ply = gameState.plyCount - 1
        let uciMove = gameState.moveHistory.last.map { $0.from + $0.to } ?? ""
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
        let restartCount = stats.restarts + 1
        stats = SessionStats()
        stats.restarts = restartCount

        if opening.color == .black {
            await makeOpponentMove()
        }

        showProactiveCoaching()
    }

    func requestExplanation(forUserMove: Bool) async {
        guard isPro else {
            showProUpgrade = true
            return
        }
        let ctx = forUserMove ? userExplainContext : opponentExplainContext
        guard let ctx else {
            print("[ChessCoach] No explain context for \(forUserMove ? "user" : "opponent")")
            return
        }

        print("[ChessCoach] Starting explanation for \(forUserMove ? "user" : "opponent")")

        if forUserMove { isExplainingUser = true } else { isExplainingOpponent = true }
        defer { if forUserMove { isExplainingUser = false } else { isExplainingOpponent = false } }

        let moveHistoryStr = buildMoveHistoryString()
        let studentColor = opening.color == .white ? "White" : "Black"
        let opponentColor = studentColor == "White" ? "Black" : "White"
        let boardState = LLMService.boardStateSummary(fen: ctx.fen)

        let perspective: String
        if forUserMove {
            perspective = """
            The student plays \(studentColor). The student has NOT played this move yet — you are explaining WHY they should play it.
            When referring to \(studentColor) pieces, say "\(studentColor)'s knight" or "your knight".
            When referring to \(opponentColor) pieces, say "\(opponentColor)'s bishop" or "the opponent's bishop".
            Explain why this is the right move to play next.
            """
        } else {
            perspective = """
            This is the OPPONENT'S move. The opponent plays \(opponentColor).
            When referring to \(opponentColor) pieces (the opponent's), say "\(opponentColor)'s knight" or "the opponent's knight".
            When referring to \(studentColor) pieces (the student's), say "\(studentColor)'s bishop" or "your bishop".
            Explain what the opponent is trying to accomplish and how the student should respond.
            """
        }

        let moveFraming = forUserMove
            ? "The recommended next move for you: \(ctx.move)"
            : "The opponent just played: \(ctx.move)"

        let prompt = """
        You are a friendly chess coach. Your student (ELO ~\(userELO)) is learning the \(opening.name) as \(studentColor).
        \(perspective)

        CRITICAL: Always use colors (\(studentColor)/\(opponentColor)) or "the opponent" to identify whose piece you mean. NEVER write ambiguous phrases like "your pieces" without specifying the color.

        Moves so far: \(moveHistoryStr)
        Current board position:
        \(boardState)

        \(moveFraming)
        Quick summary already shown: "\(ctx.coachingText)"

        Give a deeper explanation (3-5 sentences) of WHY this move \(forUserMove ? "is the right choice here" : "matters"):
        - What squares or pieces does it affect?
        - What plan or idea does it support?
        - How does it fit into the \(opening.name) strategy?

        Response format (REQUIRED):
        REFS: <list each piece and square you mention, e.g. "bishop e5, knight c3". Write "none" if you don't reference specific pieces>
        COACHING: <your explanation>

        Rules:
        - ONLY reference pieces that exist on the squares listed above.
        - Use simple language a beginner can understand.
        - Do not use algebraic notation symbols — spell out piece names.
        """

        do {
            print("[ChessCoach] Calling LLM for explanation...")
            let response = try await llmService.getExplanation(prompt: prompt)
            print("[ChessCoach] Got explanation: \(response.prefix(50))...")
            let parsed = CoachingValidator.parse(response: response)
            let validated = CoachingValidator.validate(parsed: parsed, fen: ctx.fen) ?? parsed.text
            if forUserMove { userExplanation = validated } else { opponentExplanation = validated }
        } catch {
            print("[ChessCoach] Explanation error: \(error)")
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
            playedMove = gameState.moveHistory.last.map { $0.from + $0.to } ?? "?"
            expectedSan = expected.san
            expectedUci = expected.uci
            who = "You (the student)"
        case let .opponentDeviated(expected, played, _):
            playedMove = played
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
        if let result = await stockfish.evaluate(fen: currentFen, depth: 12) {
            let pawns = Double(result.score) / 100.0
            if abs(pawns) < 0.3 {
                evalNote = "The position is roughly equal — the deviation may be fine."
            } else if pawns > 0.3 {
                evalNote = "White has a slight advantage (+\(String(format: "%.1f", pawns)) pawns)."
            } else {
                evalNote = "Black has a slight advantage (\(String(format: "%.1f", pawns)) pawns)."
            }
        }

        let boardState = LLMService.boardStateSummary(fen: currentFen)

        let prompt = """
        You are a friendly chess coach. Your student (ELO ~\(userELO)) is learning the \(opening.name) as \(studentColor).
        Always use colors (\(studentColor)/\(opponentColor)) to identify whose piece you mean. Never write ambiguous "your" without the color.

        Moves so far: \(moveHistoryStr)
        Current board position:
        \(boardState)

        \(who) played \(playedMove) instead of the book move \(expectedSan) (\(expectedUci)).
        \(evalNote)

        Explain in 2-3 sentences:
        1. Why the book move (\(expectedSan)) is the standard choice in the \(opening.name)
        2. Whether the played move (\(playedMove)) is actually bad, or if it's a reasonable alternative
        3. What the student should focus on from here

        Response format (REQUIRED):
        REFS: <list each piece and square you mention, e.g. "bishop e5, knight c3". Write "none" if you don't reference specific pieces>
        COACHING: <your explanation>

        Rules:
        - ONLY reference pieces that exist on the squares listed above.
        - Be honest — if the played move is fine or even good, say so.
        - Use simple language. Spell out piece names, no algebraic notation.
        """

        do {
            let response = try await llmService.getExplanation(prompt: prompt)
            let parsed = CoachingValidator.parse(response: response)
            offBookExplanation = CoachingValidator.validate(parsed: parsed, fen: currentFen) ?? parsed.text
        } catch {
            offBookExplanation = "Couldn't get explanation right now. Try again."
        }
    }

    /// Clear arrow and hint when user interacts with the board.
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

    // MARK: - Session Auto-Save (improvement 27)

    /// Save current session state for resume on app relaunch.
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

    /// Check if there is a saved session to resume.
    static func hasSavedSession() -> Bool {
        PersistenceService.shared.loadSessionState() != nil
    }

    /// Load saved session metadata (opening ID and line ID) for resume prompt.
    static func savedSessionInfo() -> (openingID: String, lineID: String?)? {
        guard let state = PersistenceService.shared.loadSessionState(),
              let openingID = state["openingID"] as? String else { return nil }
        let lineID = state["lineID"] as? String
        return (openingID, lineID?.isEmpty == true ? nil : lineID)
    }

    /// Discard the saved session.
    static func clearSavedSession() {
        PersistenceService.shared.clearSessionState()
    }

    private func saveProgress() {
        guard stats.totalUserMoves > 0 else { return }
        var progress = PersistenceService.shared.loadProgress(forOpening: opening.id)
        let completed = gameState.plyCount >= activeMoves.count
        let accuracy = stats.accuracy

        // Check personal best before recording (uses line best if per-line, aggregate otherwise)
        let previousBest: Double
        if let lineID = activeLineID {
            previousBest = progress.progress(forLine: lineID).bestAccuracy
        } else {
            previousBest = progress.bestAccuracy
        }
        let isPersonalBest = accuracy > previousBest && progress.gamesPlayed > 0

        // Record game and capture promotions
        var phasePromotion: SessionResult.PhasePromotion?
        var linePhasePromotion: SessionResult.PhasePromotion?

        if let lineID = activeLineID {
            let (aggOld, lineOld) = progress.recordLineGame(lineID: lineID, accuracy: accuracy, won: completed)
            if let old = aggOld {
                phasePromotion = SessionResult.PhasePromotion(from: old, to: progress.currentPhase)
            }
            if let old = lineOld {
                linePhasePromotion = SessionResult.PhasePromotion(from: old, to: progress.progress(forLine: lineID).currentPhase)
            }

            // Track guided/unguided completions for training pipeline
            if completed {
                switch sessionMode {
                case .guided:
                    progress.lineProgress[lineID]?.guidedCompletions += 1
                case .unguided:
                    progress.lineProgress[lineID]?.unguidedCompletions += 1
                    let currentBest = progress.lineProgress[lineID]?.unguidedBestAccuracy ?? 0
                    progress.lineProgress[lineID]?.unguidedBestAccuracy = max(currentBest, accuracy)
                case .practice:
                    break // Practice mode is handled by PracticeOpeningView
                }
            }
        } else {
            let old = progress.recordGame(accuracy: accuracy, won: completed)
            if let old {
                phasePromotion = SessionResult.PhasePromotion(from: old, to: progress.currentPhase)
            }
        }

        PersistenceService.shared.saveProgress(progress)

        // Scan for newly unlocked sibling lines
        var newlyUnlockedLines: [String] = []
        if let lines = opening.lines {
            for line in lines {
                if let parentID = line.parentLineID,
                   progress.isLineUnlocked(line.id, parentLineID: parentID) {
                    // Check if this line had no games before (newly accessible)
                    let lp = progress.progress(forLine: line.id)
                    if lp.gamesPlayed == 0 {
                        newlyUnlockedLines.append(line.name)
                    }
                }
            }
        }

        // Due review count
        let dueReviewCount = spacedRepScheduler.dueItems().count

        // Composite score and thresholds
        let currentComposite: Double
        let currentPhase: LearningPhase
        if let lineID = activeLineID {
            let lp = progress.progress(forLine: lineID)
            currentComposite = lp.compositeScore
            currentPhase = lp.currentPhase
        } else {
            currentComposite = progress.compositeScore
            currentPhase = progress.currentPhase
        }

        let nextThreshold = currentPhase.promotionThreshold
        let minGames = currentPhase.minimumGames
        let gamesPlayed = activeLineID != nil
            ? progress.progress(forLine: activeLineID!).gamesPlayed
            : progress.gamesPlayed
        let gamesUntilMinimum: Int? = minGames.map { max(0, $0 - gamesPlayed) }

        // Record streak
        var streak = PersistenceService.shared.loadStreak()
        streak.recordPractice()
        PersistenceService.shared.saveStreak(streak)

        let timeSpent = Date().timeIntervalSince(sessionStartDate)
        let movesPerMinute: Double? = timeSpent > 0
            ? Double(stats.totalUserMoves) / (timeSpent / 60.0)
            : nil

        sessionResult = SessionResult(
            accuracy: accuracy,
            isPersonalBest: isPersonalBest,
            phasePromotion: phasePromotion,
            linePhasePromotion: linePhasePromotion,
            newlyUnlockedLines: newlyUnlockedLines,
            dueReviewCount: dueReviewCount,
            compositeScore: currentComposite,
            nextPhaseThreshold: nextThreshold,
            gamesUntilMinimum: gamesUntilMinimum,
            timeSpent: timeSpent,
            movesPerMinute: movesPerMinute
        )
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
                let predictions = try await maia.predictMove(
                    fen: gameState.fen,
                    legalMoves: legalUCI,
                    eloSelf: opponentELO,
                    eloOppo: userELO
                )
                let top3 = predictions.prefix(3).map { "\($0.move) (\(String(format: "%.1f%%", $0.probability * 100)))" }
                print("[ChessCoach] Maia ELO \(opponentELO) top moves: \(top3.joined(separator: ", "))")
                computedMove = try await maia.sampleMove(
                    fen: gameState.fen,
                    legalMoves: legalUCI,
                    eloSelf: opponentELO,
                    eloOppo: userELO
                )
                print("[ChessCoach] Maia selected: \(computedMove ?? "nil")")
            } catch {
                print("[ChessCoach] Maia failed, falling back to Stockfish: \(error)")
            }
        }

        guard gen == sessionGeneration else { return }

        if computedMove == nil {
            if let result = await stockfish.evaluate(fen: gameState.fen, depth: 10) {
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

        opponentExplainContext = ExplainContext(
            fen: gameState.fen,
            move: move,
            ply: ply,
            moveHistory: gameState.moveHistory.map { $0.from + $0.to },
            coachingText: opponentCoachingText ?? ""
        )

        // Show proactive coaching for user's next move
        showProactiveCoaching()
    }

    /// Compute opponent move without applying it or waiting.
    /// Returns (move, isForced) — isForced is true when the book move was used directly (no engine needed).
    private func computeOpponentMove() async -> (move: String, isForced: Bool)? {
        let ply = gameState.plyCount
        var computedMove: String?

        if let forcedMove = curriculumService.getMaiaOverride(atPly: ply) {
            return (forcedMove, true)
        } else if let maia = maiaService {
            do {
                let legalUCI = gameState.legalMoves.map(\.description)
                let predictions = try await maia.predictMove(
                    fen: gameState.fen,
                    legalMoves: legalUCI,
                    eloSelf: opponentELO,
                    eloOppo: userELO
                )
                let top3 = predictions.prefix(3).map { "\($0.move) (\(String(format: "%.1f%%", $0.probability * 100)))" }
                print("[ChessCoach] Maia ELO \(opponentELO) top moves: \(top3.joined(separator: ", "))")
                computedMove = try await maia.sampleMove(
                    fen: gameState.fen,
                    legalMoves: legalUCI,
                    eloSelf: opponentELO,
                    eloOppo: userELO
                )
                print("[ChessCoach] Maia selected: \(computedMove ?? "nil")")
            } catch {
                print("[ChessCoach] Maia failed, falling back to Stockfish: \(error)")
            }
        }

        if computedMove == nil {
            print("[ChessCoach] Maia unavailable, using Stockfish fallback")
            if let result = await stockfish.evaluate(fen: gameState.fen, depth: 10) {
                computedMove = result.bestMove
            }
        }

        guard let move = computedMove else { return nil }
        return (move, false)
    }

    /// Batched flow: compute opponent move, get coaching for both moves in one LLM call,
    /// show user coaching immediately, apply thinking delay, animate opponent move, show opponent coaching.
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

        // 3. Only call LLM if we don't have a book explanation for the opponent move
        //    Use post-move FEN so the LLM sees the board after the opponent played,
        //    and the validator checks piece positions correctly.
        var opponentCoachingFromLLM: String?
        if opponentBookExplanation == nil {
            isCoachingLoading = true
            let moveHistoryStr = buildMoveHistoryString()
            let studentColor = opening.color == .white ? "White" : "Black"
            // Compute post-move FEN for accurate board state in the prompt
            let postMoveFen: String = {
                let tempState = GameState(fen: userFen)
                _ = tempState.makeMoveUCI(opponentMove)
                return tempState.fen
            }()
            opponentCoachingFromLLM = await coachingService.getCoaching(
                fen: postMoveFen,
                lastMove: opponentMove,
                scoreBefore: 0,
                scoreAfter: 0,
                ply: opponentPly,
                userELO: userELO,
                moveHistory: moveHistoryStr,
                isUserMove: false,
                studentColor: studentColor,
                isPro: isPro
            )
            isCoachingLoading = false
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
                bookStatus = .opponentDeviated(expected: expected, played: opponentMove, atPly: opponentPly)
                stats.deviationPly = opponentPly
                stats.deviatedBy = .opponent
            }
        }

        let moveSucceeded = gameState.makeMoveUCI(opponentMove)
        guard moveSucceeded else {
            print("[ChessCoach] makeMoveUCI failed for \(opponentMove)")
            return
        }

        if case .opponentDeviated = bookStatus {
            await fetchBestResponseHint()
        }

        guard gen == sessionGeneration else { return }

        // Show opponent coaching (book explanation or LLM result)
        let opponentCoaching = opponentBookExplanation ?? opponentCoachingFromLLM
        if let opponentCoaching {
            opponentCoachingText = opponentCoaching
            lastCoachingWasUser = false
        }

        opponentExplainContext = ExplainContext(
            fen: gameState.fen,
            move: opponentMove,
            ply: opponentPly,
            moveHistory: gameState.moveHistory.map { $0.from + $0.to },
            coachingText: opponentCoachingText ?? ""
        )

        // Check if the line is complete after opponent's move
        if gameState.plyCount >= moves.count {
            saveProgress()
            sessionComplete = true
            return
        }

        checkDiscoveryMode()
        await updateEval()

        // Show proactive coaching for the user's next move
        showProactiveCoaching()
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
        if let result = await stockfish.evaluate(fen: currentFen, depth: 12) {
            bestResponseHint = result.bestMove
        }
    }

    private func updateEval() async {
        // Skip eval when on-book — known opening positions don't need engine analysis
        guard !isOnBook else { return }
        let currentFen = gameState.fen
        if let result = await stockfish.evaluate(fen: currentFen, depth: 12) {
            evalScore = result.score
        }
    }

    private func generateCoaching(forPly ply: Int, move: String, isUserMove: Bool) async {
        isCoachingLoading = true
        defer { isCoachingLoading = false }

        let moveHistoryStr = buildMoveHistoryString()

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
            isPro: isPro
        )

        if let text {
            if isUserMove {
                userCoachingText = text
            } else {
                opponentCoachingText = text
            }
            lastCoachingWasUser = isUserMove
            // Improvement 5: Store coaching for replay
            coachingHistory.append((ply: ply, text: text))
        }
    }

    private func buildMoveHistoryString() -> String {
        let moves = activeMoves
        var result = ""
        for (i, move) in gameState.moveHistory.enumerated() {
            if i % 2 == 0 {
                result += "\(i / 2 + 1). "
            }
            if i < moves.count && moves[i].uci == move.from + move.to {
                result += moves[i].san
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
