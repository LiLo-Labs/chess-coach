import Foundation
import SwiftUI
import ChessKit

/// Trainer-mode specific logic: bot moves, eval, opening detection, game end.
extension GamePlayViewModel {

    /// Handle player move in trainer mode.
    func trainerUserMoved(from: String, to: String) {
        SoundService.shared.play(.move)
        SoundService.shared.hapticPiecePlaced()

        let moveUCI = "\(from)\(to)"
        let preMoveDet = currentOpening
        let preMoveFen: String = {
            let preMoveHistory = Array(gameState.moveHistory.dropLast())
            let temp = GameState()
            for m in preMoveHistory {
                temp.makeMove(from: m.from, to: m.to, promotion: m.promotion)
            }
            return temp.fen
        }()

        updateOpeningDetection()
        evaluatePlayerMove(moveUCI: moveUCI, preMoveFen: preMoveFen, preMoveDetection: preMoveDet)
        checkGameEnd()
        if !isTrainerGameOver() {
            makeBotMove()
        }
    }

    func makeBotMove() {
        withAnimation(.easeInOut(duration: 0.2)) { isThinking = true }

        Task { @MainActor in
            let fen = gameState.fen
            let legalMoves = gameState.legalMoves.map { $0.description }

            guard !legalMoves.isEmpty else {
                withAnimation(.easeOut(duration: 0.2)) { isThinking = false }
                checkGameEnd()
                return
            }

            let delay = Double.random(in: botPersonality.thinkingDelayRange)
            try? await Task.sleep(for: .seconds(delay))

            var selectedMove: String?

            switch trainerEngineMode {
            case .humanLike:
                if let maia = maiaService {
                    let history = gameState.moveHistory.map {
                        "\($0.from)\($0.to)\($0.promotion?.rawValue ?? "")"
                    }
                    selectedMove = try? await maia.sampleMove(
                        fen: fen,
                        legalMoves: legalMoves,
                        eloSelf: selectedBotELO,
                        eloOppo: userELO,
                        temperature: 1.0,
                        recentMoves: history
                    )
                }
                if selectedMove == nil {
                    let depth = AppConfig.engine.depthForELO(selectedBotELO)
                    selectedMove = await stockfish.bestMove(fen: fen, depth: depth)
                }
            case .engine:
                let depth = AppConfig.engine.depthForELO(selectedBotELO)
                selectedMove = await stockfish.bestMove(fen: fen, depth: depth)
            case .custom:
                let depth = botPersonality.customDepth ?? 12
                selectedMove = await stockfish.bestMove(fen: fen, depth: depth)
            }

            if selectedMove == nil {
                selectedMove = legalMoves.randomElement()
            }

            let botMoveSAN = selectedMove.flatMap { gameState.sanForUCI($0) } ?? selectedMove ?? "?"

            if let move = selectedMove {
                let isCapture = gameState.isCapture(move)
                let _ = gameState.makeMoveUCI(move)
                let isCheck = gameState.isCheck

                if gameState.isMate || isCheck {
                    SoundService.shared.play(.check)
                } else if isCapture {
                    SoundService.shared.play(.capture)
                    SoundService.shared.hapticPiecePlaced()
                } else {
                    SoundService.shared.play(.move)
                    SoundService.shared.hapticPiecePlaced()
                }

                if gameState.plyCount > 4 && Bool.random() && Bool.random() {
                    if isCapture {
                        showBotReaction(botPersonality.randomReaction(from: botPersonality.onCapture))
                    } else if isCheck {
                        showBotReaction(botPersonality.randomReaction(from: botPersonality.onCheck))
                    }
                }
            }

            withAnimation(.easeOut(duration: 0.2)) { isThinking = false }

            if let move = selectedMove {
                let sanLabel = OpeningMove.friendlyName(from: botMoveSAN)
                AccessibilityNotification.Announcement("\(botPersonality.name) played \(sanLabel). Your turn.").post()

                addBotMoveEntry(moveUCI: move, moveSAN: botMoveSAN)
                if let eval = await stockfish.evaluate(fen: gameState.fen, depth: 8) {
                    lastEvalScore = eval.score
                }
            }
            updateOpeningDetection()
            checkGameEnd()
        }
    }

    func updateOpeningDetection() {
        let uciMoves = gameState.moveHistory.map { "\($0.from)\($0.to)\($0.promotion?.rawValue ?? "")" }
        currentOpening = openingDetector.detect(moves: uciMoves)
        holisticDetection = holisticDetector.detect(moves: uciMoves)
    }

    func evaluatePlayerMove(moveUCI: String, preMoveFen: String?, preMoveDetection: OpeningDetection?) {
        let ply = gameState.plyCount
        let fen = gameState.fen
        let moveSAN: String
        if let pmFen = preMoveFen {
            moveSAN = GameState.sanForUCI(moveUCI, inFEN: pmFen)
        } else {
            moveSAN = moveUCI
        }
        let moveNumber = (ply + 1) / 2

        let preDetection = preMoveDetection ?? currentOpening
        let postDetection = currentOpening
        let allPreBookMoves: [OpeningMove]
        var seen = Set<String>()
        allPreBookMoves = (holisticDetection.allNextBookMoves + preDetection.matches.flatMap(\.nextBookMoves))
            .filter { seen.insert($0.uci).inserted }

        let isBookMove = allPreBookMoves.contains(where: { $0.uci == moveUCI })
        let isInBook = isBookMove || (postDetection.best?.nextBookMoves.isEmpty == false)
        let openingName = (postDetection.best ?? preDetection.best)?.opening.name
        let scoreBefore = lastEvalScore
        let playerIsWhite = mode.playerColor == .white

        Task { @MainActor in
            isEvaluating = true

            let eval = await stockfish.evaluate(fen: fen, depth: AppConfig.engine.evalDepth)
            let scoreAfter = eval?.score ?? 0

            let cpLoss = SoundnessCalculator.centipawnLoss(
                scoreBefore: scoreBefore,
                scoreAfter: scoreAfter,
                playerIsWhite: playerIsWhite
            )
            let soundness = SoundnessCalculator.ceiling(centipawnLoss: cpLoss, userELO: userELO)

            let category: MoveCategory
            if isBookMove || isInBook {
                category = soundness >= 80 ? .goodMove : .okayMove
            } else if cpLoss < 30 {
                category = .goodMove
            } else if cpLoss < 100 {
                category = .okayMove
            } else {
                category = .mistake
            }

            let sc = ScoreCategory.from(score: soundness)

            let personality: CoachPersonality
            if let matchedOpening = (postDetection.best ?? preDetection.best)?.opening {
                personality = CoachPersonality.forOpening(matchedOpening)
            } else {
                personality = .defaultPersonality
            }

            let coaching: String
            switch category {
            case .goodMove:
                coaching = personality.witticism(for: .goodMove)
            case .okayMove:
                if !isBookMove, let bm = allPreBookMoves.first {
                    coaching = "\(personality.witticism(for: .okayMove)) The book move is \(bm.san)."
                } else {
                    coaching = personality.witticism(for: .okayMove)
                }
            case .mistake:
                if !isBookMove, let bm = allPreBookMoves.first {
                    coaching = "\(personality.witticism(for: .mistake)) The recommended move here is \(bm.san)."
                } else if let pmFen = preMoveFen,
                          let bestUCI = await stockfish.bestMove(fen: pmFen, depth: AppConfig.engine.evalDepth) {
                    // Evaluate from pre-move position to find the PLAYER's best alternative
                    let san = GameState.sanForUCI(bestUCI, inFEN: pmFen)
                    coaching = "\(personality.witticism(for: .mistake)) Better was \(san)."
                } else {
                    coaching = personality.witticism(for: .mistake)
                }
            default:
                coaching = personality.witticism(for: .goodMove)
            }

            let entry = CoachingEntry(
                ply: ply,
                moveNumber: moveNumber,
                moveSAN: moveSAN,
                moveUCI: moveUCI,
                isPlayerMove: true,
                coaching: coaching,
                category: category,
                soundness: soundness,
                scoreCategory: sc,
                openingName: openingName,
                isInBook: isInBook,
                fen: fen,
                fenBeforeMove: preMoveFen
            )

            withAnimation(.easeInOut(duration: 0.2)) {
                feedEntries.insert(entry, at: 0)
                isEvaluating = false
            }

            let qualityLabel = entry.scoreCategory?.displayName ?? category.feedLabel
            AccessibilityNotification.Announcement("\(qualityLabel) move. \(coaching)").post()

            lastEvalScore = scoreAfter
        }
    }

    func addBotMoveEntry(moveUCI: String, moveSAN: String?) {
        let ply = gameState.plyCount
        let moveNumber = (ply + 1) / 2
        let detection = currentOpening
        let isInBook = detection.best?.nextBookMoves.isEmpty == false
        let openingName = detection.best?.opening.name
        let isDeviation = detection.best != nil && !isInBook

        let opponentColorName = mode.playerColor == .white ? "Black" : "White"
        let coaching: String
        if isDeviation, let bestOpening = detection.best?.opening,
           let catalogue = bestOpening.opponentResponses {
            let movesSoFar = gameState.moveHistory.dropLast().map { "\($0.from)\($0.to)" }
            if let response = catalogue.matchResponse(moveUCI: moveUCI, afterMoves: Array(movesSoFar)) {
                coaching = "\(opponentColorName) played the \(response.name). \(response.planAdjustment)"
            } else if let name = openingName {
                coaching = "\(opponentColorName) went off the \(name) plan."
            } else {
                coaching = "\(opponentColorName)'s move."
            }
        } else if isDeviation, let name = openingName {
            coaching = "\(opponentColorName) went off the \(name) plan."
        } else if isInBook, let name = openingName {
            coaching = "Standard \(name) response by \(opponentColorName)."
        } else {
            coaching = "\(opponentColorName)'s move."
        }

        let entry = CoachingEntry(
            ply: ply,
            moveNumber: moveNumber,
            moveSAN: moveSAN ?? moveUCI,
            moveUCI: moveUCI,
            isPlayerMove: false,
            coaching: coaching,
            category: isDeviation ? .deviation : .opponentMove,
            openingName: openingName,
            isInBook: isInBook,
            fen: gameState.fen
        )

        withAnimation(.easeInOut(duration: 0.2)) {
            feedEntries.insert(entry, at: 0)
        }
    }

    func isTrainerGameOver() -> Bool {
        gameState.isMate || gameState.legalMoves.isEmpty
    }

    func checkGameEnd() {
        guard isTrainerGameOver() else { return }

        let outcome: TrainerGameResult.Outcome
        if gameState.isMate {
            let lastMoverIsWhite = !gameState.isWhiteTurn
            let playerIsWhite = mode.playerColor == .white
            outcome = lastMoverIsWhite == playerIsWhite ? .win : .loss
        } else {
            outcome = .draw
        }

        endTrainerGame(outcome: outcome)
    }

    func resignTrainer() {
        endTrainerGame(outcome: .resigned)
    }

    func endTrainerGame(outcome: TrainerGameResult.Outcome) {
        let result = TrainerGameResult(
            playerColor: mode.playerColor == .white ? "white" : "black",
            botELO: selectedBotELO,
            botName: botPersonality.name,
            engineMode: trainerEngineMode,
            outcome: outcome,
            moveCount: gameState.plyCount
        )
        gameResult = result
        isGameOver = true

        switch outcome {
        case .win:
            SoundService.shared.play(.phaseUp)
            SoundService.shared.hapticLineComplete()
        case .loss, .resigned:
            SoundService.shared.hapticDeviation()
        case .draw:
            SoundService.shared.hapticPiecePlaced()
        }

        switch outcome {
        case .win:
            if trainerEngineMode == .humanLike { humanStats.wins += 1 } else { engineStats.wins += 1 }
        case .loss, .resigned:
            if trainerEngineMode == .humanLike { humanStats.losses += 1 } else { engineStats.losses += 1 }
        case .draw:
            if trainerEngineMode == .humanLike { humanStats.draws += 1 } else { engineStats.draws += 1 }
        }

        // Custom mode shares the engine stats bucket

        TrainerModeView.saveStats(humanStats, mode: .humanLike)
        TrainerModeView.saveStats(engineStats, mode: .engine)
        var games = recentGames
        games.insert(result, at: 0)
        if games.count > 50 { games = Array(games.prefix(50)) }
        recentGames = games
        TrainerModeView.saveRecentGames(games)

        let uciMoves = gameState.moveHistory.map { "\($0.from)\($0.to)\($0.promotion?.rawValue ?? "")" }
        let detector = OpeningDetector()
        let detection = detector.detect(moves: uciMoves)
        let openingID = detection.best?.opening.id

        PlayerProgressService.shared.recordGame(
            opponentELO: selectedBotELO,
            outcome: outcome,
            engineMode: trainerEngineMode,
            openingID: openingID,
            moveCount: gameState.plyCount
        )
    }
}
