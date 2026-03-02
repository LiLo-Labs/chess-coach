import Foundation
import SwiftUI
import ChessKit

/// Session-mode specific logic: book tracking, deviation, opponent moves, PES, discovery, progress saving.
extension GamePlayViewModel {

    /// Handle player move in session mode.
    func sessionUserMoved(from: String, to: String) async {
        let ply = gameState.plyCount - 1
        let uciMove = from + to
        let fenAfterMove = gameState.fen

        let fenBeforeMove: String = {
            let tempState = GameState()
            for historyMove in gameState.moveHistory.dropLast() {
                _ = tempState.makeMoveUCI(historyMove.from + historyMove.to)
            }
            return tempState.fen
        }()

        clearArrowAndHint()
        bestResponseHint = nil
        userCoachingText = nil
        userExplanation = nil
        opponentExplanation = nil
        offBookExplanation = nil
        suggestedVariation = nil

        SoundService.shared.play(.move)
        SoundService.shared.hapticPiecePlaced()

        stats.totalUserMoves += 1

        let moves = activeMoves

        if isOnBook {
            handleOnBookMove(ply: ply, uciMove: uciMove, moves: moves, fenBeforeMove: fenBeforeMove)
        } else if case let .opponentDeviated(_, _, deviationPly) = bookStatus {
            if ply < moves.count && moves[ply].uci == uciMove {
                stats.movesOnBook += 1; correctMoveTrigger += 1
            }
            bookStatus = .offBook(since: deviationPly)
        } else if case .offBook = bookStatus {
            if ply < moves.count && moves[ply].uci == uciMove {
                stats.movesOnBook += 1; correctMoveTrigger += 1
            }
        }

        // Build coaching and feed entry
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

        let category: MoveCategory = isDeviation ? .mistake : .goodMove
        maybeShowQuip(for: category)

        // PES
        if let sessionMode = mode.sessionMode, sessionMode != .guided,
           currentLayer.rawValue >= LearningLayer.executePlan.rawValue {
            if let pes = await computePES(forPly: ply, move: uciMove, fenBefore: fenBeforeMove, fenAfter: fenAfterMove) {
                lastMovePES = pes
                stats.moveScores.append(pes)
            }
        }

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
            SoundService.shared.play(.correct)
            SoundService.shared.hapticLineComplete()
            captureSnapshot()
            saveProgress()
            sessionComplete = true
            return
        }

        if case let .userDeviated(expected, _) = bookStatus {
            SoundService.shared.play(.wrong)
            SoundService.shared.hapticDeviation()
            if mode.sessionMode == .unguided {
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

    private func handleOnBookMove(ply: Int, uciMove: String, moves: [OpeningMove], fenBeforeMove: String) {
        guard let opening = mode.opening else { return }

        if discoveryMode {
            discoveryMode = false
            branchPointOptions = nil

            let moveHistory = gameState.moveHistory.map { $0.from + $0.to }

            if opening.isKnownContinuation(atPly: ply, move: uciMove, afterMoves: Array(moveHistory.prefix(ply))) {
                stats.movesOnBook += 1; correctMoveTrigger += 1
                let allMoves = moveHistory + [uciMove]
                let matchingLines = opening.matchingLines(forMoveSequence: allMoves)
                if let newLine = matchingLines.first(where: { $0.id != activeLine?.id }) {
                    suggestedVariation = newLine
                }
            } else if ply < moves.count && moves[ply].uci != uciMove {
                recordDeviation(ply: ply, uciMove: uciMove, moves: moves, fenBeforeMove: fenBeforeMove, opening: opening)
            } else {
                stats.movesOnBook += 1; correctMoveTrigger += 1
            }
        } else if ply < moves.count && moves[ply].uci != uciMove {
            let moveHistory = gameState.moveHistory.map { $0.from + $0.to }
            if opening.isKnownContinuation(atPly: ply, move: uciMove, afterMoves: Array(moveHistory.prefix(ply))) {
                stats.movesOnBook += 1; correctMoveTrigger += 1
                let allMoves = moveHistory + [uciMove]
                let matchingLines = opening.matchingLines(forMoveSequence: allMoves)
                if let newLine = matchingLines.first(where: { $0.id != activeLine?.id }) {
                    suggestedVariation = newLine
                }
            } else {
                recordDeviation(ply: ply, uciMove: uciMove, moves: moves, fenBeforeMove: fenBeforeMove, opening: opening)
            }
        } else {
            stats.movesOnBook += 1; correctMoveTrigger += 1
            if let scheduler = spacedRepScheduler,
               let item = scheduler.findItem(openingID: opening.id, ply: ply) {
                scheduler.review(itemID: item.id, quality: 4)
            }
            let correctKey = "\(opening.id)/\(activeLineID ?? "main")/\(ply)"
            consecutiveCorrectPlays[correctKey, default: 0] += 1
            UserDefaults.standard.set(consecutiveCorrectPlays, forKey: AppSettings.Key.consecutiveCorrect)
            SoundService.shared.hapticCorrectMove()
        }
    }

    private func recordDeviation(ply: Int, uciMove: String, moves: [OpeningMove], fenBeforeMove: String, opening: Opening) {
        if let expected = ply < moves.count ? moves[ply] : nil {
            bookStatus = .userDeviated(expected: expected, atPly: ply)
            stats.deviationPly = ply
            stats.deviatedBy = .user
            lastSessionMistakePlies.insert(ply)
            mistakeTracker.recordMistake(openingID: opening.id, lineID: activeLineID, ply: ply, expectedMove: expected.uci, playedMove: uciMove)
            PersistenceService.shared.saveMistakeTracker(mistakeTracker)
            spacedRepScheduler?.addItem(openingID: opening.id, lineID: activeLineID, fen: fenBeforeMove, ply: ply, correctMove: expected.uci, playerColor: opening.color.rawValue)
        }
    }

    // MARK: - Opponent Move

    func makeOpponentMove() async {
        isThinking = true
        defer { isThinking = false }

        let gen = sessionGeneration
        let ply = gameState.plyCount
        let clock = ContinuousClock()
        let start = clock.now

        var computedMove: String?
        var isForced = false

        if let forcedMove = curriculumService?.getMaiaOverride(atPly: ply) {
            computedMove = forcedMove
            isForced = true
        } else if let maia = maiaService {
            do {
                let legalUCI = gameState.legalMoves.map(\.description)
                let history = gameState.moveHistory.map {
                    "\($0.from)\($0.to)\($0.promotion?.rawValue ?? "")"
                }
                computedMove = try await maia.sampleMove(
                    fen: gameState.fen,
                    legalMoves: legalUCI,
                    eloSelf: opponentELO,
                    eloOppo: userELO,
                    recentMoves: history
                )
            } catch {}
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

        if !isForced {
            let minimumDelay = Duration.seconds(Double.random(in: 1.0...3.0))
            let elapsed = clock.now - start
            if elapsed < minimumDelay {
                try? await Task.sleep(for: minimumDelay - elapsed)
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

        guard gameState.makeMoveUCI(move) else { return }

        let isOffBookHere: Bool = {
            switch bookStatus {
            case .opponentDeviated, .offBook: return true
            default: return false
            }
        }()
        if isOffBookHere {
            await fetchBestResponseHint()
        }

        guard gen == sessionGeneration else { return }

        checkDiscoveryMode()

        let moves2 = activeMoves
        if isOnBook && ply < moves2.count && moves2[ply].uci == move {
            let studentColor = mode.opening?.color == .white ? "White" : "Black"
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

        appendToFeed(ply: ply, san: opponentSan, coaching: opponentCoachingText, isDeviation: !isOnBook, fen: gameState.fen)

        if isOffBookHere {
            showOffBookGuidance()
        } else {
            showProactiveCoaching()
        }
    }

    func makeOpponentMoveWithBatchedCoaching(userPly: Int, userMove: String) async {
        isThinking = true
        defer { isThinking = false }

        let gen = sessionGeneration
        let clock = ContinuousClock()
        let start = clock.now

        guard let opponentResult = await computeOpponentMove() else {
            opponentCoachingText = "Opponent couldn't find a move. Try restarting."
            return
        }
        let opponentMove = opponentResult.move
        let opponentIsForced = opponentResult.isForced
        guard gen == sessionGeneration else { return }

        let opponentPly = gameState.plyCount
        let userFen = gameState.fen

        let opponentBookExplanation: String? = {
            let moves = activeMoves
            if isOnBook && opponentPly < moves.count && moves[opponentPly].uci == opponentMove {
                let studentColor = mode.opening?.color == .white ? "White" : "Black"
                let opponentColor = studentColor == "White" ? "Black" : "White"
                return "\(opponentColor) plays \(moves[opponentPly].san) — \(moves[opponentPly].explanation.prefix(1).lowercased())\(moves[opponentPly].explanation.dropFirst())"
            }
            return nil
        }()

        var coachingTask: Task<String?, Never>?
        if opponentBookExplanation == nil, let coachingService = coachingService {
            isCoachingLoading = true
            let moveHistoryStr = buildMoveHistoryString()
            let studentColor = mode.opening?.color == .white ? "White" : "Black"
            let postMoveFen: String = {
                let tempState = GameState(fen: userFen)
                _ = tempState.makeMoveUCI(opponentMove)
                return tempState.fen
            }()
            let movesSoFar = gameState.moveHistory.dropLast().map { "\($0.from)\($0.to)" }
            var responseName: String?
            var responseAdjustment: String?
            if let catalogue = mode.opening?.opponentResponses,
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

        if !opponentIsForced {
            let minimumDelay = Duration.seconds(Double.random(in: 1.0...3.0))
            let elapsed = clock.now - start
            if elapsed < minimumDelay {
                try? await Task.sleep(for: minimumDelay - elapsed)
            }
        }
        guard gen == sessionGeneration else { return }

        let moves = activeMoves
        if isOnBook && opponentPly < moves.count && moves[opponentPly].uci != opponentMove {
            if let expected = opponentPly < moves.count ? moves[opponentPly] : nil {
                let san = gameState.sanForUCI(opponentMove) ?? opponentMove
                bookStatus = .opponentDeviated(expected: expected, playedSAN: san, atPly: opponentPly)
                stats.deviationPly = opponentPly
                stats.deviatedBy = .opponent
            }
        }

        guard gameState.makeMoveUCI(opponentMove) else { return }

        let isOffBook: Bool = {
            switch bookStatus {
            case .opponentDeviated, .offBook: return true
            default: return false
            }
        }()

        if let opponentBookExplanation {
            opponentCoachingText = opponentBookExplanation
            lastCoachingWasUser = false
        } else if let coachingTask {
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

        appendToFeed(ply: opponentPly, san: batchedOpponentSan, coaching: opponentCoachingText, isDeviation: !isOnBook, fen: gameState.fen)

        if gameState.plyCount >= moves.count {
            captureSnapshot()
            saveProgress()
            sessionComplete = true
            return
        }

        checkDiscoveryMode()

        if isOffBook {
            await fetchBestResponseHintAndEval()
        } else {
            await updateEval()
        }

        guard gen == sessionGeneration else { return }

        if isOffBook {
            showOffBookGuidance()
        } else {
            showProactiveCoaching()
        }
        captureSnapshot()
    }

    private func computeOpponentMove() async -> (move: String, isForced: Bool)? {
        let ply = gameState.plyCount
        if let forcedMove = curriculumService?.getMaiaOverride(atPly: ply) {
            return (forcedMove, true)
        }
        if let maia = maiaService {
            do {
                let legalUCI = gameState.legalMoves.map(\.description)
                let history = gameState.moveHistory.map {
                    "\($0.from)\($0.to)\($0.promotion?.rawValue ?? "")"
                }
                let move = try await maia.sampleMove(
                    fen: gameState.fen,
                    legalMoves: legalUCI,
                    eloSelf: opponentELO,
                    eloOppo: userELO,
                    recentMoves: history
                )
                return (move, false)
            } catch {}
        }
        if let result = await stockfish.evaluate(fen: gameState.fen, depth: AppConfig.engine.opponentMoveDepth) {
            return (result.bestMove, false)
        }
        return nil
    }

    // MARK: - Proactive Coaching

    func showProactiveCoaching() {
        guard mode.isSession else { return }
        guard isOnBook, isUserTurn, !sessionComplete else {
            if !isUserTurn { userCoachingText = nil }
            return
        }
        if discoveryMode { return }

        guard mode.showsProactiveCoaching else {
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

        guard let opening = mode.opening else { return }
        let correctKey = "\(opening.id)/\(activeLineID ?? "main")/\(ply)"
        let correctCount = consecutiveCorrectPlays[correctKey] ?? 0

        if lastSessionMistakePlies.contains(ply) {
            userCoachingText = "You missed this last time — play \(nextMove.san) — \(lowerExplanation)"
        } else if correctCount >= 5 {
            userCoachingText = nextMove.san
        } else {
            userCoachingText = "Play \(nextMove.san) — \(lowerExplanation)"
        }

        if mode.showsArrows {
            let uci = nextMove.uci
            if uci.count >= 4 {
                arrowFrom = String(uci.prefix(2))
                arrowTo = String(uci.dropFirst(2).prefix(2))
            }
        }

        startHintTimer(square: arrowTo)
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

    func showOffBookGuidance() {
        guard isUserTurn, !sessionComplete else { return }

        if mode.showsArrows, let hint = bestResponseHint, hint.count >= 4 {
            arrowFrom = String(hint.prefix(2))
            arrowTo = String(hint.dropFirst(2).prefix(2))
        }

        if let bestMove = bestResponseDescription {
            userCoachingText = "You're on your own. Suggested: \(bestMove) — focus on development and king safety."
        } else {
            userCoachingText = "You're on your own. Focus on developing pieces and keeping your king safe."
        }
    }

    func checkDiscoveryMode() {
        guard isOnBook else { return }
        guard let curriculum = curriculumService, curriculum.shouldDiscover(atPly: gameState.plyCount) else { return }

        let options = curriculum.allBookMoves(atPly: gameState.plyCount)
        if options.count > 1 {
            discoveryMode = true
            branchPointOptions = options
        }
    }

    func continueAfterDeviation() async {
        let ply = gameState.plyCount - 1
        let uciMove = gameState.moveHistory.last.map { $0.from + $0.to } ?? ""
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
        userCoachingText = "Restarting — let's try the \(mode.opening?.name ?? "opening") again!"
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

        if mode.opening?.color == .black {
            await makeOpponentMove()
        }

        showProactiveCoaching()
        captureSnapshot()
    }

    // MARK: - Feed Management

    func appendToFeed(
        ply: Int,
        san: String?,
        coaching: String?,
        isDeviation: Bool,
        fen: String? = nil,
        playedUCI: String? = nil,
        expectedSAN: String? = nil,
        expectedUCI: String? = nil
    ) {
        let moveNumber = ply / 2 + 1
        let entry = CoachingEntry(
            ply: ply,
            moveNumber: moveNumber,
            moveSAN: san ?? "?",
            moveUCI: playedUCI ?? "",
            isPlayerMove: isUserTurn,
            coaching: coaching ?? "",
            isDeviation: isDeviation,
            expectedSAN: expectedSAN,
            expectedUCI: expectedUCI,
            playedUCI: playedUCI
        )
        entry.fen = fen
        feedEntries.insert(entry, at: 0)
    }

    // MARK: - PES

    func computePES(forPly ply: Int, move: String, fenBefore: String, fenAfter: String) async -> PlanExecutionScore? {
        guard let planScoringService, let opening = mode.opening else { return nil }

        let playerIsWhite = opening.color == .white

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
            } catch {}
        }

        let sfTopMoves: [(move: String, score: Int)]
        if isOnBook {
            sfTopMoves = await stockfish.topMoves(fen: fenBefore, count: 3, depth: AppConfig.engine.pesTopMovesDepth)
        } else {
            sfTopMoves = []
        }

        let moveHistory = gameState.moveHistory.dropLast().map { $0.from + $0.to }
        let siblings = opening.childNodes(afterMoves: Array(moveHistory))
        let (moveWeight, allWeights) = PopularityService.lookupWeights(move: move, siblings: siblings)

        let moveSAN: String
        if ply < activeMoves.count && activeMoves[ply].uci == move {
            moveSAN = activeMoves[ply].san
        } else {
            moveSAN = move
        }

        let moveHistoryStr = buildMoveHistoryString()
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

    // MARK: - Coaching Generation

    func generateCoaching(forPly ply: Int, move: String, isUserMove: Bool) async {
        guard let coachingService else { return }
        isCoachingLoading = true
        defer { isCoachingLoading = false }

        let moveHistoryStr = buildMoveHistoryString()
        var responseName: String?
        var responseAdjustment: String?
        if !isUserMove, let catalogue = mode.opening?.opponentResponses {
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
            studentColor: mode.opening?.color == .white ? "White" : "Black",
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

    // MARK: - Progress

    func saveProgress() {
        guard mode.isSession, let opening = mode.opening else { return }
        guard stats.totalUserMoves > 0 else { return }
        var progress = PersistenceService.shared.loadProgress(forOpening: opening.id)
        let completed = gameState.plyCount >= activeMoves.count
        let accuracy = stats.accuracy

        let previousBest: Double
        if let lineID = activeLineID {
            previousBest = progress.progress(forLine: lineID).bestAccuracy
        } else {
            previousBest = progress.bestAccuracy
        }
        let isPersonalBest = accuracy > previousBest && progress.gamesPlayed > 0

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
            if completed {
                switch mode.sessionMode {
                case .guided:
                    progress.lineProgress[lineID]?.guidedCompletions += 1
                case .unguided:
                    progress.lineProgress[lineID]?.unguidedCompletions += 1
                    let currentBest = progress.lineProgress[lineID]?.unguidedBestAccuracy ?? 0
                    progress.lineProgress[lineID]?.unguidedBestAccuracy = max(currentBest, accuracy)
                case .practice, .none:
                    break
                }
            }
        } else {
            let old = progress.recordGame(accuracy: accuracy, won: completed)
            if let old {
                phasePromotion = SessionResult.PhasePromotion(from: old, to: progress.currentPhase)
            }
        }

        PersistenceService.shared.saveProgress(progress)

        var mastery = PersistenceService.shared.loadMastery(forOpening: opening.id)
        let masteryBefore = mastery
        let sessionPES = stats.averagePES
        switch mastery.currentLayer {
        case .understandPlan: break
        case .executePlan:
            let modeStr = mode.sessionMode == .guided ? "guided" : "unguided"
            mastery.recordExecutionSession(pes: sessionPES, mode: modeStr)
        case .discoverTheory: break
        case .handleVariety:
            if let responses = opening.opponentResponses?.responses {
                let moveHistory = gameState.moveHistory.map { $0.from + $0.to }
                let modeStr = mode.sessionMode == .guided ? "guided" : "unguided"
                for response in responses {
                    if moveHistory.contains(response.move.uci) {
                        mastery.recordResponseHandled(responseID: response.id, pes: sessionPES, mode: modeStr)
                    }
                }
            }
        case .realConditions: mastery.recordRealConditionsSession(pes: sessionPES)
        }
        PersistenceService.shared.saveMastery(mastery)
        currentLayer = mastery.currentLayer

        var newlyUnlockedLines: [String] = []
        if let lines = opening.lines {
            for line in lines {
                if let parentID = line.parentLineID,
                   progress.isLineUnlocked(line.id, parentLineID: parentID) {
                    let lp = progress.progress(forLine: line.id)
                    if lp.gamesPlayed == 0 {
                        newlyUnlockedLines.append(line.name)
                    }
                }
            }
        }

        let dueReviewCount = spacedRepScheduler?.dueItems().count ?? 0

        let currentComposite: Double
        let currentPhaseVal: LearningPhase
        if let lineID = activeLineID {
            let lp = progress.progress(forLine: lineID)
            currentComposite = lp.compositeScore
            currentPhaseVal = lp.currentPhase
        } else {
            currentComposite = progress.compositeScore
            currentPhaseVal = progress.currentPhase
        }

        let nextThreshold = currentPhaseVal.promotionThreshold
        let minGames = currentPhaseVal.minimumGames
        let gamesPlayed = activeLineID.map { progress.progress(forLine: $0).gamesPlayed } ?? progress.gamesPlayed
        let gamesUntilMinimum: Int? = minGames.map { max(0, $0 - gamesPlayed) }

        var streak = PersistenceService.shared.loadStreak()
        streak.recordPractice()
        PersistenceService.shared.saveStreak(streak)

        let timeSpent = Date().timeIntervalSince(sessionStartDate)
        let movesPerMinute: Double? = timeSpent > 0
            ? Double(stats.totalUserMoves) / (timeSpent / 60.0)
            : nil

        let layerAfter = mastery.currentLayer
        let layerPromotion: SessionResult.LayerPromotion?
        if layerAfter != currentLayer {
            layerPromotion = SessionResult.LayerPromotion(from: currentLayer, to: layerAfter)
        } else {
            layerPromotion = nil
        }

        // Milestone tracking
        let completedMilestones = OpeningMastery.newlyCompletedMilestones(before: masteryBefore, after: mastery)
        let nextMilestone = mastery.currentLayer.nextMilestone(from: mastery)
        let coach = CoachPersonality.forOpening(opening)
        let guidance = CoachGuidance(personality: coach, mastery: mastery, openingName: opening.name)
        let coachMessage = guidance.sessionCompleteMessage(pes: sessionPES, completedMilestones: completedMilestones)

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
            movesPerMinute: movesPerMinute,
            averagePES: stats.moveScores.isEmpty ? nil : stats.averagePES,
            pesCategory: stats.moveScores.isEmpty ? nil : stats.pesCategory,
            moveScores: stats.moveScores.isEmpty ? nil : stats.moveScores,
            layerPromotion: layerPromotion,
            completedMilestones: completedMilestones,
            nextMilestone: nextMilestone,
            coachSessionMessage: coachMessage
        )
    }
}
