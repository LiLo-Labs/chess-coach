import Foundation
import SwiftUI
import ChessKit

/// Coaching & explanation logic: feed entry explain, off-book explain, coaching text generation.
extension GamePlayViewModel {

    // MARK: - Explain for Feed Entries (Trainer + Session)

    /// Request an LLM-generated explanation for any coaching feed entry.
    func requestExplanation(for entry: CoachingEntry) {
        guard isPro else {
            showProUpgrade = true
            return
        }
        guard !entry.isExplaining, entry.explanation == nil else { return }
        guard let fen = entry.fen ?? entry.fenBeforeMove else { return }

        entry.isExplaining = true

        let playerColor = mode.playerColor
        let studentColor = playerColor == .white ? "White" : "Black"
        let opponentColor = playerColor == .white ? "Black" : "White"
        let moveHistoryStr = buildMoveHistoryString()
        let boardState = LLMService.boardStateSummary(fen: fen, studentColor: studentColor)
        let occupied = LLMService.occupiedSquares(fen: fen)
        let moveDisplay = entry.moveSAN

        let prompt: String

        if entry.isDeviation, let expectedSAN = entry.expectedSAN, let expectedUCI = entry.expectedUCI {
            // Deviation entry: explain why played move is suboptimal and why book move is better
            let evalNote = evalScore != 0
                ? "Current engine evaluation: \(evalScore > 0 ? "+" : "")\(evalScore) centipawns."
                : ""
            prompt = PromptCatalog.offBookExplanationPrompt(params: .init(
                openingName: entry.openingName ?? mode.opening?.name ?? "this opening",
                studentColor: studentColor,
                opponentColor: opponentColor,
                userELO: userELO,
                moveHistoryStr: moveHistoryStr,
                boardState: boardState,
                occupiedSquares: occupied,
                who: "The student",
                playedMove: moveDisplay,
                expectedSan: expectedSAN,
                expectedUci: expectedUCI,
                evalNote: evalNote
            ))
        } else if mode.isTrainer {
            // Trainer mode: per-move explanation
            let openingName = currentOpening.best?.opening.name ?? entry.openingName ?? "this opening"
            let perspective = entry.isPlayerMove
                ? "The student (\(studentColor)) played \(moveDisplay). Explain why this move matters."
                : "The opponent (\(opponentColor)) played \(moveDisplay). Explain what it means for the student."

            prompt = PromptCatalog.explanationPrompt(params: .init(
                openingName: openingName,
                studentColor: studentColor,
                opponentColor: opponentColor,
                userELO: userELO,
                perspective: perspective,
                moveHistoryStr: moveHistoryStr,
                boardState: boardState,
                occupiedSquares: occupied,
                moveDisplay: moveDisplay,
                moveUCI: entry.moveUCI,
                moveFraming: "\(entry.moveNumber). \(moveDisplay)",
                coachingText: entry.coaching,
                forUserMove: entry.isPlayerMove
            ))
        } else {
            // Session mode: move pair or single move explanation
            let openingName = mode.opening?.name ?? entry.openingName ?? "this opening"
            let perspective = """
            The student plays \(studentColor). Explain the move \(entry.moveLabel).
            When referring to \(studentColor) pieces, say "your knight" or "\(studentColor)'s knight".
            When referring to \(opponentColor) pieces, say "the opponent's bishop" or "\(opponentColor)'s bishop".
            Explain the strategic ideas behind this move in the context of the \(openingName).
            """

            prompt = PromptCatalog.explanationPrompt(params: .init(
                openingName: openingName,
                studentColor: studentColor,
                opponentColor: opponentColor,
                userELO: userELO,
                perspective: perspective,
                moveHistoryStr: moveHistoryStr,
                boardState: boardState,
                occupiedSquares: occupied,
                moveDisplay: moveDisplay,
                moveUCI: entry.moveUCI,
                moveFraming: entry.moveLabel,
                coachingText: entry.coaching,
                forUserMove: entry.isPlayerMove
            ))
        }

        Task {
            do {
                let response = try await llmService.generate(prompt: prompt, maxTokens: AppConfig.tokens.explanation)
                let parsed = CoachingValidator.parse(response: response)
                let validated = CoachingValidator.validate(parsed: parsed, fen: fen) ?? parsed.text
                entry.explanation = validated
                entry.isExplaining = false
            } catch {
                entry.explanation = "Couldn't generate explanation right now."
                entry.isExplaining = false
            }
        }
    }

    // MARK: - Context-Based Explain (Session — per side)

    /// Request explanation for the current user or opponent move context.
    func requestExplanation(forUserMove: Bool) async {
        guard isPro else {
            showProUpgrade = true
            return
        }
        let ctx = forUserMove ? userExplainContext : opponentExplainContext
        guard let ctx else { return }

        if forUserMove { isExplainingUser = true } else { isExplainingOpponent = true }
        defer { if forUserMove { isExplainingUser = false } else { isExplainingOpponent = false } }

        let moveHistoryStr = buildMoveHistoryString()
        let playerColor = mode.playerColor
        let studentColor = playerColor == .white ? "White" : "Black"
        let opponentColor = playerColor == .white ? "Black" : "White"
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
            openingName: mode.opening?.name ?? "this opening",
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
            let response = try await llmService.generate(prompt: prompt, maxTokens: AppConfig.tokens.explanation)
            let parsed = CoachingValidator.parse(response: response)
            let validated = CoachingValidator.validate(parsed: parsed, fen: ctx.fen) ?? parsed.text
            if forUserMove { userExplanation = validated } else { opponentExplanation = validated }
        } catch {
            let fallback = "Couldn't get explanation right now. Try again."
            if forUserMove { userExplanation = fallback } else { opponentExplanation = fallback }
        }
    }

    // MARK: - Off-Book Explanation (Session)

    /// Explain why a deviation occurred and what the book move would have been.
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
        let playerColor = mode.playerColor
        let studentColor = playerColor == .white ? "White" : "Black"
        let opponentColor = playerColor == .white ? "Black" : "White"

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
            openingName: mode.opening?.name ?? "this opening",
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
}
