import Foundation
import Testing
import ChessKit
@testable import ChessCoach

/// Validates every puzzle in assessment_puzzles.json:
/// 1. FEN loads without crashing
/// 2. The solution move is legal in the FEN position
/// 3. The solutionSAN matches the UCI move
/// 4. Rating is within expected bounds
@Suite(.serialized)
struct AssessmentPuzzleValidationTests {

    let service = AssessmentService()

    private func loadPuzzles() -> [AssessmentPuzzle] {
        guard let url = Bundle.main.url(forResource: "assessment_puzzles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let puzzles = try? JSONDecoder().decode([AssessmentPuzzle].self, from: data) else {
            return []
        }
        return puzzles
    }

    @Test func puzzleFileLoads() {
        let puzzles = loadPuzzles()
        #expect(puzzles.count == 50, "Expected 50 puzzles, got \(puzzles.count)")
    }

    @Test func allPuzzleIDsAreUnique() {
        let puzzles = loadPuzzles()
        let ids = Set(puzzles.map(\.id))
        #expect(ids.count == puzzles.count, "Duplicate puzzle IDs found")
    }

    @Test func allRatingsInValidRange() {
        let puzzles = loadPuzzles()
        for puzzle in puzzles {
            #expect(puzzle.rating >= 400 && puzzle.rating <= 2200,
                    "Puzzle \(puzzle.id) has out-of-range rating: \(puzzle.rating)")
        }
    }

    @Test func allFENsProduceLegalPositions() {
        let puzzles = loadPuzzles()
        for puzzle in puzzles {
            let state = GameState(fen: puzzle.fen)
            // A valid FEN should have at least some legal moves (not a stalemate/checkmate)
            #expect(!state.legalMoves.isEmpty,
                    "Puzzle \(puzzle.id) FEN has no legal moves: \(puzzle.fen)")
        }
    }

    @Test func allSolutionMovesAreLegal() {
        let puzzles = loadPuzzles()
        var failures: [String] = []
        for puzzle in puzzles {
            let state = GameState(fen: puzzle.fen)
            let success = state.makeMoveUCI(puzzle.solutionUCI)
            if !success {
                failures.append("\(puzzle.id): \(puzzle.solutionUCI) illegal in \(puzzle.fen)")
            }
        }
        #expect(failures.isEmpty, "Illegal solutions: \(failures.joined(separator: "\n"))")
    }

    @Test func allSolutionSANsMatchUCI() {
        let puzzles = loadPuzzles()
        var failures: [String] = []
        for puzzle in puzzles {
            let state = GameState(fen: puzzle.fen)
            if let san = state.sanForUCI(puzzle.solutionUCI) {
                if san != puzzle.solutionSAN {
                    failures.append("\(puzzle.id): expected '\(puzzle.solutionSAN)' got '\(san)'")
                }
            } else {
                failures.append("\(puzzle.id): cannot convert \(puzzle.solutionUCI) to SAN (illegal move)")
            }
        }
        #expect(failures.isEmpty, "SAN mismatches: \(failures.joined(separator: "\n"))")
    }

    @Test func ratingBandDistribution() {
        let puzzles = loadPuzzles()
        let band1 = puzzles.filter { $0.rating < 800 }.count
        let band2 = puzzles.filter { $0.rating >= 800 && $0.rating < 1200 }.count
        let band3 = puzzles.filter { $0.rating >= 1200 && $0.rating < 1500 }.count
        let band4 = puzzles.filter { $0.rating >= 1500 && $0.rating < 1800 }.count
        let band5 = puzzles.filter { $0.rating >= 1800 }.count

        // Each band should have at least 5 puzzles
        #expect(band1 >= 5, "Band 1 (400-800) has only \(band1) puzzles")
        #expect(band2 >= 5, "Band 2 (800-1200) has only \(band2) puzzles")
        #expect(band3 >= 5, "Band 3 (1200-1500) has only \(band3) puzzles")
        #expect(band4 >= 5, "Band 4 (1500-1800) has only \(band4) puzzles")
        #expect(band5 >= 5, "Band 5 (1800+) has only \(band5) puzzles")
    }

    @Test func adaptiveSelectionPicksFromCorrectBand() {
        // At ELO 1000, should pick puzzles near 1000 (±200)
        let puzzle = service.selectPuzzle(estimatedELO: 1000, usedIDs: [])
        #expect(puzzle != nil, "Should find a puzzle near ELO 1000")
        if let p = puzzle {
            #expect(abs(p.rating - 1000) <= 400,
                    "Puzzle \(p.id) rating \(p.rating) too far from 1000")
        }
    }

    @Test func eloUpdateFormula() {
        // Easy puzzle correct → small gain
        let easyCorrect = AssessmentService.updateEstimate(current: 1200, puzzleRating: 800, correct: true)
        #expect(easyCorrect > 1200 && easyCorrect < 1220,
                "Easy correct should give small gain, got \(easyCorrect)")

        // Hard puzzle correct → large gain
        let hardCorrect = AssessmentService.updateEstimate(current: 800, puzzleRating: 1200, correct: true)
        #expect(hardCorrect > 800 && hardCorrect < 950,
                "Hard correct should give large gain, got \(hardCorrect)")

        // Easy puzzle wrong → large loss
        let easyWrong = AssessmentService.updateEstimate(current: 1200, puzzleRating: 800, correct: false)
        #expect(easyWrong < 1200 && easyWrong > 1050,
                "Easy wrong should give large loss, got \(easyWrong)")

        // Hard puzzle wrong → small loss
        let hardWrong = AssessmentService.updateEstimate(current: 800, puzzleRating: 1200, correct: false)
        #expect(hardWrong < 800 && hardWrong >= 750,
                "Hard wrong should give small loss, got \(hardWrong)")

        // Clamp bounds
        let floor = AssessmentService.updateEstimate(current: 400, puzzleRating: 2000, correct: false)
        #expect(floor == 400, "Should clamp to 400, got \(floor)")

        let ceiling = AssessmentService.updateEstimate(current: 2000, puzzleRating: 400, correct: true)
        #expect(ceiling == 2000, "Should clamp to 2000, got \(ceiling)")
    }

    @Test func allThemesAreNonEmpty() {
        let puzzles = loadPuzzles()
        for puzzle in puzzles {
            #expect(!puzzle.themes.isEmpty,
                    "Puzzle \(puzzle.id) has no themes")
        }
    }
}
