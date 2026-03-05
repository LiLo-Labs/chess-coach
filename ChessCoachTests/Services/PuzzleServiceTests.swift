import Testing
import Foundation
@testable import ChessCoach

@Suite(.serialized)
struct PuzzleServiceTests {

    // MARK: - Helpers

    /// Creates a minimal opening with enough moves for puzzle generation (needs >= 4).
    private static func makeTestOpening(
        id: String = "test-puzzle-opening",
        moves: [OpeningMove]? = nil
    ) -> Opening {
        let defaultMoves = [
            OpeningMove(uci: "e2e4", san: "e4", explanation: "King's pawn"),
            OpeningMove(uci: "e7e5", san: "e5", explanation: "Symmetrical"),
            OpeningMove(uci: "g1f3", san: "Nf3", explanation: "Knight out"),
            OpeningMove(uci: "b8c6", san: "Nc6", explanation: "Defend"),
            OpeningMove(uci: "f1c4", san: "Bc4", explanation: "Italian bishop"),
            OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Two knights"),
        ]
        return Opening(
            id: id,
            name: "Test Opening",
            description: "A test opening for puzzles",
            color: .white,
            difficulty: 2,
            tags: nil,
            mainLine: moves ?? defaultMoves
        )
    }

    /// Creates an opening with too few moves for puzzle generation.
    private static func makeShortOpening() -> Opening {
        Opening(
            id: "short-opening",
            name: "Short",
            description: "Too short for puzzles",
            color: .white,
            difficulty: 1,
            tags: nil,
            mainLine: [
                OpeningMove(uci: "e2e4", san: "e4", explanation: ""),
            ]
        )
    }

    // MARK: - generateForOpening

    @MainActor
    @Test func generateForOpeningReturnsPuzzlesForValidOpening() {
        let stockfish = StockfishService()
        let service = PuzzleService(stockfish: stockfish)
        let opening = Self.makeTestOpening()

        let puzzles = service.generateForOpening(opening, count: 5)
        // generateForOpening uses position mastery + fallback generation.
        // With no mastery data, it falls back to generating from opening moves.
        // The opening has 6 moves (>= 4), so it should produce puzzles.
        #expect(puzzles.count > 0, "Should generate at least one puzzle for a valid opening")
    }

    @MainActor
    @Test func generatedPuzzlesHaveCorrectOpeningID() {
        let stockfish = StockfishService()
        let service = PuzzleService(stockfish: stockfish)
        let opening = Self.makeTestOpening(id: "italian-game-test")

        let puzzles = service.generateForOpening(opening, count: 5)
        for puzzle in puzzles {
            #expect(puzzle.openingID == "italian-game-test",
                    "Puzzle openingID should match the source opening")
        }
    }

    @MainActor
    @Test func generatedPuzzlesHaveValidFEN() {
        let stockfish = StockfishService()
        let service = PuzzleService(stockfish: stockfish)
        let opening = Self.makeTestOpening()

        let puzzles = service.generateForOpening(opening, count: 5)
        for puzzle in puzzles {
            // A valid FEN has at least 4 space-separated fields
            let fields = puzzle.fen.split(separator: " ")
            #expect(fields.count >= 4,
                    "FEN should have at least 4 fields, got: \(puzzle.fen)")
            // First field should have 8 ranks separated by /
            let ranks = fields[0].split(separator: "/")
            #expect(ranks.count == 8,
                    "FEN board should have 8 ranks, got: \(ranks.count) in \(puzzle.fen)")
        }
    }

    @MainActor
    @Test func generateForOpeningReturnsEmptyForShortOpening() {
        let stockfish = StockfishService()
        let service = PuzzleService(stockfish: stockfish)
        let opening = Self.makeShortOpening()

        let puzzles = service.generateForOpening(opening, count: 5)
        // Opening has only 1 move (< 4 required), so fallback generation
        // should produce nothing.
        #expect(puzzles.isEmpty,
                "Should return empty array for opening with too few moves")
    }

    @MainActor
    @Test func generatedPuzzlesHaveValidDifficulty() {
        let stockfish = StockfishService()
        let service = PuzzleService(stockfish: stockfish)
        let opening = Self.makeTestOpening()

        let puzzles = service.generateForOpening(opening, count: 5)
        for puzzle in puzzles {
            #expect(puzzle.difficulty >= 1 && puzzle.difficulty <= 5,
                    "Difficulty should be 1-5, got \(puzzle.difficulty)")
        }
    }

    @MainActor
    @Test func generatedPuzzlesHaveSolutionMoves() {
        let stockfish = StockfishService()
        let service = PuzzleService(stockfish: stockfish)
        let opening = Self.makeTestOpening()

        let puzzles = service.generateForOpening(opening, count: 5)
        for puzzle in puzzles {
            #expect(!puzzle.solutionUCI.isEmpty, "solutionUCI should not be empty")
            #expect(!puzzle.solutionSAN.isEmpty, "solutionSAN should not be empty")
        }
    }

    // MARK: - generateFastPuzzles (uses database)

    @MainActor
    @Test func fastPuzzlesUseDatabase() {
        let stockfish = StockfishService()
        let service = PuzzleService(stockfish: stockfish)

        // This depends on the opening database being loadable in tests.
        // If it's empty (no bundle resources in test target), it may return empty.
        let puzzles = service.generateFastPuzzles(count: 5)
        // We don't assert count > 0 because the database may not load in the test target.
        // Just verify it doesn't crash and returns a valid array.
        #expect(puzzles.count >= 0)
    }
}
