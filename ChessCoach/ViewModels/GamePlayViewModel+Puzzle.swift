import Foundation
import SwiftUI

/// Puzzle-mode logic: loading, move checking, retry, mastery integration, and LLM coaching.
extension GamePlayViewModel {

    // MARK: - Load Puzzles

    func loadPuzzles() async {
        let service = PuzzleService(stockfish: stockfish)

        let initial: [Puzzle]
        if case .puzzle(let opening, .opening) = mode, opening != nil {
            // Opening-scoped puzzles — generateForOpening not yet available, fall back to fast
            initial = service.generateFastPuzzles(count: 10, userELO: userELO)
        } else {
            initial = service.generateFastPuzzles(count: 10, userELO: userELO)
        }

        self.puzzles = initial
        self.currentPuzzleIndex = 0
        self.puzzleSessionResult = PuzzleSessionResult()

        if let first = puzzles.first {
            setupPuzzleBoard(first)
            addPuzzleContextEntry(first)
        }

        // Background: append engine-evaluated puzzles
        Task { [weak self] in
            guard let self else { return }
            let enginePuzzles = await service.generateEnginePuzzles(count: 5, userELO: self.userELO)
            guard !enginePuzzles.isEmpty else { return }
            self.puzzles.append(contentsOf: enginePuzzles)
        }
    }

    // MARK: - Setup Board

    func setupPuzzleBoard(_ puzzle: Puzzle) {
        gameState.reset(fen: puzzle.fen)
        puzzleAttemptsRemaining = 3
        isPuzzleShowingSolution = false
        puzzleSolutionArrowFrom = nil
        puzzleSolutionArrowTo = nil
    }

    // MARK: - User Move

    func puzzleUserMoved(from: String, to: String) {
        guard currentPuzzleIndex < puzzles.count else { return }
        let puzzle = puzzles[currentPuzzleIndex]
        let moveUCI = from + to

        // Check correctness — compare full UCI and also prefix(4) for promotion moves
        let isCorrect = moveUCI == puzzle.solutionUCI ||
            moveUCI == String(puzzle.solutionUCI.prefix(4))

        if isCorrect {
            handleCorrectPuzzleAnswer(puzzle: puzzle)
        } else {
            handleWrongPuzzleAnswer(puzzle: puzzle, playedUCI: moveUCI)
        }
    }

    // MARK: - Correct Answer

    private func handleCorrectPuzzleAnswer(puzzle: Puzzle) {
        SoundService.shared.play(.correct)
        SoundService.shared.hapticCorrectMove()

        puzzleSessionResult.recordSolve()

        // SM-2 quality: 3 remaining = 5, 2 = 4, 1 = 3
        let quality: Int
        switch puzzleAttemptsRemaining {
        case 3: quality = 5
        case 2: quality = 4
        default: quality = 3
        }
        updatePositionMastery(puzzle: puzzle, quality: quality, correct: true)

        let explanation = puzzle.explanation ?? "This is the main line continuation."
        addPuzzleFeedEntry(
            puzzle: puzzle,
            coaching: "Correct! \(explanation)",
            category: .goodMove
        )

        // Auto-advance after delay
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.advanceToNextPuzzle()
        }
    }

    // MARK: - Wrong Answer

    private func handleWrongPuzzleAnswer(puzzle: Puzzle, playedUCI: String) {
        SoundService.shared.play(.wrong)
        SoundService.shared.hapticDeviation()

        // Undo the incorrect move
        gameState.undoLastMove()

        puzzleAttemptsRemaining -= 1

        if puzzleAttemptsRemaining > 0 {
            addPuzzleFeedEntry(
                puzzle: puzzle,
                coaching: "Not quite \u{2014} try again. (\(puzzleAttemptsRemaining) attempt\(puzzleAttemptsRemaining == 1 ? "" : "s") remaining)",
                category: .mistake
            )
            // Optionally request LLM coaching for paid users
            requestPuzzleLLMCoaching(puzzle: puzzle, playedUCI: playedUCI)
        } else {
            // Out of attempts
            puzzleSessionResult.recordFail()
            updatePositionMastery(puzzle: puzzle, quality: 1, correct: false)
            recordPuzzleMistake(puzzle: puzzle, playedUCI: playedUCI)
            showPuzzleSolution(puzzle: puzzle)
        }
    }

    // MARK: - Show Solution

    private func showPuzzleSolution(puzzle: Puzzle) {
        let solutionUCI = puzzle.solutionUCI
        let fromSquare = String(solutionUCI.prefix(2))
        let toSquare = String(solutionUCI.dropFirst(2).prefix(2))

        puzzleSolutionArrowFrom = fromSquare
        puzzleSolutionArrowTo = toSquare

        // Apply the correct move to the board
        gameState.makeMoveUCI(solutionUCI)
        isPuzzleShowingSolution = true

        let explanation = puzzle.explanation ?? "This follows the opening theory."
        addPuzzleFeedEntry(
            puzzle: puzzle,
            coaching: "The answer is \(puzzle.solutionSAN). \(explanation)",
            category: .deviation
        )

        // Auto-advance after longer delay
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            self?.advanceToNextPuzzle()
        }
    }

    // MARK: - Advance

    func advanceToNextPuzzle() {
        currentPuzzleIndex += 1

        if currentPuzzleIndex < puzzles.count {
            let next = puzzles[currentPuzzleIndex]
            setupPuzzleBoard(next)
            addPuzzleContextEntry(next)
        } else {
            completePuzzleSession()
        }
    }

    // MARK: - Session Complete

    private func completePuzzleSession() {
        isPuzzleComplete = true

        let result = puzzleSessionResult
        let total = result.total
        let pct = total > 0 ? Int(result.accuracy * 100) : 0
        let summary = "Session complete: \(result.solved)/\(total) correct (\(pct)%). Best streak: \(result.bestStreak)."

        let entry = CoachingEntry(
            ply: 0,
            moveNumber: 0,
            moveSAN: "",
            isPlayerMove: true,
            coaching: summary,
            category: .goodMove
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            feedEntries.insert(entry, at: 0)
        }
    }

    // MARK: - Feed Entry Helpers

    private func addPuzzleContextEntry(_ puzzle: Puzzle) {
        let openingName: String
        if let openingID = puzzle.openingID,
           let opening = OpeningDatabase.shared.opening(byID: openingID) {
            openingName = opening.name
        } else {
            openingName = puzzle.theme.rawValue
        }

        let progress = "\(currentPuzzleIndex + 1)/\(puzzles.count)"
        let coaching = "Find the book move \u{2014} \(openingName) (\(progress))"

        let entry = CoachingEntry(
            ply: 0,
            moveNumber: currentPuzzleIndex + 1,
            moveSAN: "",
            isPlayerMove: true,
            coaching: coaching,
            category: .goodMove,
            openingName: openingName
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            feedEntries.insert(entry, at: 0)
        }
    }

    private func addPuzzleFeedEntry(puzzle: Puzzle, coaching: String, category: MoveCategory) {
        let openingName: String?
        if let openingID = puzzle.openingID {
            openingName = OpeningDatabase.shared.opening(byID: openingID)?.name
        } else {
            openingName = nil
        }

        let entry = CoachingEntry(
            ply: currentPuzzleIndex,
            moveNumber: currentPuzzleIndex + 1,
            moveSAN: puzzle.solutionSAN,
            moveUCI: puzzle.solutionUCI,
            isPlayerMove: true,
            coaching: coaching,
            category: category,
            openingName: openingName
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            feedEntries.insert(entry, at: 0)
        }
    }

    // MARK: - Mastery Integration

    private func updatePositionMastery(puzzle: Puzzle, quality: Int, correct: Bool) {
        guard let scheduler = spacedRepScheduler else { return }
        let ply = extractPlyFromPuzzleID(puzzle.id)

        // Ensure item exists
        scheduler.addItem(
            openingID: puzzle.openingID ?? "unknown",
            fen: puzzle.fen,
            ply: ply,
            correctMove: puzzle.solutionUCI
        )

        // Find and review
        if let item = scheduler.findItem(openingID: puzzle.openingID ?? "unknown", ply: ply) {
            scheduler.review(itemID: item.id, quality: quality)
            scheduler.recordAttempt(id: item.id, correct: correct)
        }
    }

    private func recordPuzzleMistake(puzzle: Puzzle, playedUCI: String) {
        let ply = extractPlyFromPuzzleID(puzzle.id)
        mistakeTracker.recordMistake(
            openingID: puzzle.openingID ?? "unknown",
            lineID: nil,
            ply: ply,
            expectedMove: puzzle.solutionUCI,
            playedMove: playedUCI
        )
        PersistenceService.shared.saveMistakeTracker(mistakeTracker)
    }

    /// Parse ply from puzzle ID format "opening_{id}_{ply}_{uuid}" or similar.
    private func extractPlyFromPuzzleID(_ id: String) -> Int {
        let parts = id.split(separator: "_")
        // Try third-from-last component for formats like "opening_italian_4_AbCd"
        if parts.count >= 3, let ply = Int(parts[parts.count - 2]) {
            return ply
        }
        // Fallback: try each numeric component
        for part in parts.reversed() {
            if let ply = Int(part) {
                return ply
            }
        }
        return 0
    }

    // MARK: - LLM Coaching (Paid Tier)

    private func requestPuzzleLLMCoaching(puzzle: Puzzle, playedUCI: String) {
        guard let featureAccess else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let hasLLM = await featureAccess.isUnlocked(.llmCoaching)
            guard hasLLM else { return }

            let openingName = puzzle.openingID.flatMap { OpeningDatabase.shared.opening(byID: $0)?.name } ?? "this opening"
            let prompt = """
            The student is practicing chess opening puzzles in \(openingName).
            Position (FEN): \(puzzle.fen)
            The correct move is \(puzzle.solutionSAN) (\(puzzle.solutionUCI)).
            The student played \(playedUCI) instead.
            Give a brief, encouraging hint (1-2 sentences) about why the correct move is better, without revealing it directly.
            """

            do {
                let response = try await self.llmService.generate(prompt: prompt, maxTokens: 100)
                // Update the latest feed entry with LLM coaching
                if let latest = self.feedEntries.first {
                    latest.coaching += "\n\n\(response)"
                }
            } catch {
                #if DEBUG
                print("[Puzzle] LLM coaching failed: \(error)")
                #endif
            }
        }
    }
}
