import Foundation
import SwiftUI

/// Puzzle-mode logic: loading, move checking, retry, mastery integration, and LLM coaching.
extension GamePlayViewModel {

    // MARK: - Load Puzzles

    func loadPuzzles() async {
        // Cancel any pending tasks from previous session
        puzzleAdvanceTask?.cancel()
        puzzleAdvanceTask = nil
        puzzleEngineTask?.cancel()
        puzzleEngineTask = nil

        let service = PuzzleService(stockfish: stockfish)

        let initial: [Puzzle]
        if case .puzzle(_, let source) = mode {
            switch source {
            case .opening(let opening):
                initial = service.generateForOpening(opening)
            case .standalone:
                initial = service.generateFastPuzzles(count: 10, userELO: userELO)
            }
        } else {
            initial = service.generateFastPuzzles(count: 10, userELO: userELO)
        }

        self.puzzles = initial
        self.currentPuzzleIndex = 0
        self.puzzleSessionResult = PuzzleSessionResult()
        self.isPuzzleComplete = false

        if let first = puzzles.first {
            setupPuzzleBoard(first)
            addPuzzleContextEntry(first)
        }

        // Background: append engine-evaluated puzzles
        puzzleEngineTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let enginePuzzles = await service.generateEnginePuzzles(count: 5, userELO: self.userELO)
            guard !Task.isCancelled, !enginePuzzles.isEmpty else { return }
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
        puzzleAdvanceTask?.cancel()
        puzzleAdvanceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
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
        } else {
            // Out of attempts
            puzzleSessionResult.recordFail()
            updatePositionMastery(puzzle: puzzle, quality: 1, correct: false)
            recordPuzzleMistake(puzzle: puzzle, playedUCI: playedUCI)
            showPuzzleSolution(puzzle: puzzle)
            requestPuzzleLLMCoaching(puzzle: puzzle, playedUCI: playedUCI)
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
        puzzleAdvanceTask?.cancel()
        puzzleAdvanceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
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
        let pct = result.total > 0 ? Int(result.accuracy * 100) : 0
        let summary = "Session complete: \(result.solved)/\(result.total) correct (\(pct)%). Best streak: \(result.bestStreak)."

        insertFeedEntry(CoachingEntry(
            ply: 0,
            moveNumber: 0,
            moveSAN: "",
            isPlayerMove: true,
            coaching: summary,
            category: .goodMove
        ))
    }

    // MARK: - Feed Entry Helpers

    private func resolveOpeningName(for puzzle: Puzzle) -> String? {
        puzzle.openingID.flatMap { OpeningDatabase.shared.opening(byID: $0)?.name }
    }

    func insertFeedEntry(_ entry: CoachingEntry) {
        withAnimation(.easeInOut(duration: 0.2)) {
            feedEntries.insert(entry, at: 0)
        }
    }

    private func addPuzzleContextEntry(_ puzzle: Puzzle) {
        let openingName = resolveOpeningName(for: puzzle) ?? puzzle.theme.rawValue

        let progress = "\(currentPuzzleIndex + 1)/\(puzzles.count)"
        let coaching = "Find the book move \u{2014} \(openingName) (\(progress))"

        insertFeedEntry(CoachingEntry(
            ply: 0,
            moveNumber: currentPuzzleIndex + 1,
            moveSAN: "",
            isPlayerMove: true,
            coaching: coaching,
            category: .goodMove,
            openingName: openingName
        ))
    }

    private func addPuzzleFeedEntry(puzzle: Puzzle, coaching: String, category: MoveCategory) {
        insertFeedEntry(CoachingEntry(
            ply: currentPuzzleIndex,
            moveNumber: currentPuzzleIndex + 1,
            moveSAN: puzzle.solutionSAN,
            moveUCI: puzzle.solutionUCI,
            isPlayerMove: true,
            coaching: coaching,
            category: category,
            openingName: resolveOpeningName(for: puzzle)
        ))
    }

    // MARK: - Mastery Integration

    private func updatePositionMastery(puzzle: Puzzle, quality: Int, correct: Bool) {
        guard let scheduler = spacedRepScheduler else { return }
        let ply = puzzle.ply

        // Ensure item exists
        scheduler.addItem(
            openingID: puzzle.openingID ?? Puzzle.unknownOpeningID,
            fen: puzzle.fen,
            ply: ply,
            correctMove: puzzle.solutionUCI
        )

        // Find and review
        if let item = scheduler.findItem(openingID: puzzle.openingID ?? Puzzle.unknownOpeningID, ply: ply) {
            scheduler.review(itemID: item.id, quality: quality)
            scheduler.recordAttempt(id: item.id, correct: correct)
        }
    }

    private func recordPuzzleMistake(puzzle: Puzzle, playedUCI: String) {
        mistakeTracker.recordMistake(
            openingID: puzzle.openingID ?? Puzzle.unknownOpeningID,
            lineID: nil,
            ply: puzzle.ply,
            expectedMove: puzzle.solutionUCI,
            playedMove: playedUCI
        )
        PersistenceService.shared.saveMistakeTracker(mistakeTracker)
    }


    // MARK: - LLM Coaching (Paid Tier)

    private func requestPuzzleLLMCoaching(puzzle: Puzzle, playedUCI: String) {
        guard let featureAccess else { return }
        // Capture the target entry before the async gap to avoid appending to wrong entry
        guard let targetEntry = feedEntries.first else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let hasLLM = await featureAccess.isUnlocked(.llmCoaching)
            guard hasLLM else { return }

            let openingName = puzzle.openingID.flatMap { OpeningDatabase.shared.opening(byID: $0)?.name } ?? "this opening"
            let boardSummary = LLMService.boardStateSummary(fen: puzzle.fen)
            let prompt = PromptCatalog.puzzleCoachingPrompt(
                fen: puzzle.fen,
                playedMove: playedUCI,
                correctMove: puzzle.solutionSAN,
                openingName: openingName,
                boardSummary: boardSummary
            )

            do {
                let response = try await self.llmService.generate(prompt: prompt, maxTokens: 100)
                let parsed = CoachingValidator.parse(response: response).text
                if !parsed.isEmpty {
                    targetEntry.coaching += "\n\n\(parsed)"
                }
            } catch {
                #if DEBUG
                print("[Puzzle] LLM coaching failed: \(error)")
                #endif
            }
        }
    }
}
