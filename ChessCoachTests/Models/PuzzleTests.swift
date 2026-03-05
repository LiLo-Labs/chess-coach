import Testing
import Foundation
@testable import ChessCoach

@Suite(.serialized)
struct PuzzleSessionResultTests {

    @Test func initialStateIsZero() {
        let result = PuzzleSessionResult()
        #expect(result.solved == 0)
        #expect(result.failed == 0)
        #expect(result.streak == 0)
        #expect(result.bestStreak == 0)
        #expect(result.accuracy == 0)
    }

    @Test func recordSolveIncrementsCountAndStreak() {
        var result = PuzzleSessionResult()
        result.recordSolve()
        #expect(result.solved == 1)
        #expect(result.streak == 1)
        #expect(result.bestStreak == 1)
        #expect(result.failed == 0)
    }

    @Test func recordFailIncrementsFailedAndResetsStreak() {
        var result = PuzzleSessionResult()
        result.recordSolve()
        result.recordSolve()
        #expect(result.streak == 2)

        result.recordFail()
        #expect(result.failed == 1)
        #expect(result.streak == 0)
        #expect(result.solved == 2)
    }

    @Test func accuracyIsCorrectlyComputed() {
        var result = PuzzleSessionResult()
        result.recordSolve()
        result.recordSolve()
        result.recordFail()
        // 2 solved, 1 failed => 2/3
        let expected = 2.0 / 3.0
        #expect(abs(result.accuracy - expected) < 0.001)
    }

    @Test func accuracyIsZeroWhenNoAttempts() {
        let result = PuzzleSessionResult()
        #expect(result.accuracy == 0)
    }

    @Test func bestStreakTrackedAcrossSolveFailSequences() {
        var result = PuzzleSessionResult()
        // Build a streak of 3
        result.recordSolve()
        result.recordSolve()
        result.recordSolve()
        #expect(result.bestStreak == 3)

        // Fail resets current streak but not best
        result.recordFail()
        #expect(result.streak == 0)
        #expect(result.bestStreak == 3)

        // Build a smaller streak of 2
        result.recordSolve()
        result.recordSolve()
        #expect(result.streak == 2)
        #expect(result.bestStreak == 3) // best unchanged

        // Build a new best of 4
        result.recordSolve()
        result.recordSolve()
        #expect(result.streak == 4)
        #expect(result.bestStreak == 4) // new best
    }

    @Test func totalCountsCombinedSolvesAndFails() {
        var result = PuzzleSessionResult()
        result.recordSolve()
        result.recordSolve()
        result.recordFail()
        result.recordSolve()
        #expect(result.total == 4)
    }
}

@Suite(.serialized)
struct PuzzleModelTests {

    @Test func puzzleCanBeConstructed() {
        let puzzle = Puzzle(
            id: "test_1",
            fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
            solutionUCI: "e7e5",
            solutionSAN: "e5",
            theme: .openingKnowledge,
            difficulty: 2,
            openingID: "italian",
            explanation: "Symmetrical response"
        )
        #expect(puzzle.id == "test_1")
        #expect(puzzle.theme == .openingKnowledge)
        #expect(puzzle.difficulty == 2)
        #expect(puzzle.openingID == "italian")
    }

    @Test func puzzleThemeHasExpectedCases() {
        let allThemes = Puzzle.Theme.allCases
        #expect(allThemes.contains(.findTheBestMove))
        #expect(allThemes.contains(.openingKnowledge))
        #expect(allThemes.contains(.mistakeReview))
    }
}
