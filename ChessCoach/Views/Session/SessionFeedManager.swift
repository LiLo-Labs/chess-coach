import Foundation

struct SessionFeedManager {

    // MARK: - Feed Entry Append

    static func appendToFeed(
        entries: inout [CoachingFeedEntry],
        ply: Int,
        san: String?,
        coaching: String?,
        isDeviation: Bool,
        fen: String? = nil,
        playedUCI: String? = nil,
        expectedSAN: String? = nil,
        expectedUCI: String? = nil
    ) {
        let isWhitePly = ply % 2 == 0
        let moveNumber = ply / 2 + 1

        if isWhitePly {
            let entry = CoachingFeedEntry(moveNumber: moveNumber, whitePly: ply)
            entry.whiteSAN = san
            entry.coaching = coaching
            entry.isDeviation = isDeviation
            entry.fen = fen
            entry.playedUCI = playedUCI
            entry.expectedSAN = expectedSAN
            entry.expectedUCI = expectedUCI
            // Insert in descending ply order (newest first)
            let insertIndex = entries.firstIndex { $0.whitePly < ply } ?? entries.endIndex
            entries.insert(entry, at: insertIndex)
        } else {
            // Find the matching white-ply entry for this move number (not just first)
            if let existing = entries.first(where: { $0.moveNumber == moveNumber }) {
                existing.blackSAN = san
                existing.blackPly = ply
                existing.fen = fen ?? existing.fen
                if let opCoaching = coaching {
                    if existing.isDeviation {
                        existing.coaching = opCoaching
                    } else if let userCoaching = existing.coaching {
                        existing.coaching = "\(userCoaching)\n\(opCoaching)"
                    } else {
                        existing.coaching = opCoaching
                    }
                }
                if isDeviation { existing.isDeviation = true }
            } else {
                let entry = CoachingFeedEntry(moveNumber: moveNumber, whitePly: ply - 1)
                entry.blackSAN = san
                entry.blackPly = ply
                entry.coaching = coaching
                entry.isDeviation = isDeviation
                entry.fen = fen
                entry.playedUCI = playedUCI
                entry.expectedSAN = expectedSAN
                entry.expectedUCI = expectedUCI
                // Insert in descending ply order (newest first)
                let insertIndex = entries.firstIndex { $0.whitePly < (ply - 1) } ?? entries.endIndex
                entries.insert(entry, at: insertIndex)
            }
        }
    }

    // MARK: - Entry Explanation

    @MainActor
    static func requestExplanationForEntry(
        _ entry: CoachingFeedEntry,
        opening: Opening,
        userELO: Int,
        evalScore: Int,
        moveHistoryStr: String,
        llmService: LLMService,
        userExplainContext: ExplainContext?,
        opponentExplainContext: ExplainContext?
    ) async {
        guard !entry.isExplaining, entry.explanation == nil else { return }

        entry.isExplaining = true
        defer { entry.isExplaining = false }

        let entryFen = entry.fen ?? userExplainContext?.fen ?? opponentExplainContext?.fen
        guard let fen = entryFen else { return }

        let studentColor = opening.color == .white ? "White" : "Black"
        let opponentColor = studentColor == "White" ? "Black" : "White"
        let boardState = LLMService.boardStateSummary(fen: fen, studentColor: studentColor)
        let occupied = LLMService.occupiedSquares(fen: fen)

        let prompt: String

        if entry.isDeviation, let expectedSAN = entry.expectedSAN, let expectedUCI = entry.expectedUCI {
            let playedSAN = entry.whiteSAN ?? entry.blackSAN ?? "the played move"
            let evalNote = evalScore != 0
                ? "Current engine evaluation: \(evalScore > 0 ? "+" : "")\(evalScore) centipawns."
                : ""
            prompt = PromptCatalog.offBookExplanationPrompt(params: .init(
                openingName: opening.name,
                studentColor: studentColor,
                opponentColor: opponentColor,
                userELO: userELO,
                moveHistoryStr: moveHistoryStr,
                boardState: boardState,
                occupiedSquares: occupied,
                who: "The student",
                playedMove: playedSAN,
                expectedSan: expectedSAN,
                expectedUci: expectedUCI,
                evalNote: evalNote
            ))
        } else {
            let whiteSAN = entry.whiteSAN ?? "?"
            let blackSAN = entry.blackSAN ?? ""
            let moveDisplay = blackSAN.isEmpty ? whiteSAN : "\(whiteSAN) \(blackSAN)"

            let perspective = """
            The student plays \(studentColor). Explain the move pair: \(entry.moveNumber). \(moveDisplay).
            Cover both the student's move and the opponent's response as a combined narrative.
            When referring to \(studentColor) pieces, say "your knight" or "\(studentColor)'s knight".
            When referring to \(opponentColor) pieces, say "the opponent's bishop" or "\(opponentColor)'s bishop".
            Explain the strategic ideas behind these moves in the context of the \(opening.name).
            """

            let moveFraming = "\(entry.moveNumber). \(moveDisplay)"

            prompt = PromptCatalog.explanationPrompt(params: .init(
                openingName: opening.name,
                studentColor: studentColor,
                opponentColor: opponentColor,
                userELO: userELO,
                perspective: perspective,
                moveHistoryStr: moveHistoryStr,
                boardState: boardState,
                occupiedSquares: occupied,
                moveDisplay: moveDisplay,
                moveUCI: entry.playedUCI ?? "",
                moveFraming: moveFraming,
                coachingText: entry.coaching ?? "",
                forUserMove: true
            ))
        }

        do {
            let response = try await llmService.generate(prompt: prompt, maxTokens: AppConfig.tokens.explanation)
            let parsed = CoachingValidator.parse(response: response)
            entry.explanation = CoachingValidator.validate(parsed: parsed, fen: fen) ?? parsed.text
        } catch {
            entry.explanation = "Couldn't generate explanation. Try again."
        }
    }
}
