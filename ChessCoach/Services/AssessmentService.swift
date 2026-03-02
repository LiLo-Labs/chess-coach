import Foundation

/// Loads curated Lichess puzzles and provides adaptive selection + Elo math
/// for the puzzle gauntlet assessment.
struct AssessmentService: Sendable {

    private let puzzles: [AssessmentPuzzle]

    var hasPuzzles: Bool { !puzzles.isEmpty }

    init() {
        guard let url = Bundle.main.url(forResource: "assessment_puzzles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([AssessmentPuzzle].self, from: data) else {
            puzzles = []
            return
        }
        puzzles = decoded
    }

    /// Select a puzzle within ±200 of the current estimate, avoiding already-used IDs.
    func selectPuzzle(estimatedELO: Int, usedIDs: Set<String>) -> AssessmentPuzzle? {
        // Candidates within ±200 of estimated ELO
        let candidates = puzzles.filter { puzzle in
            !usedIDs.contains(puzzle.id) &&
            abs(puzzle.rating - estimatedELO) <= 200
        }

        if let picked = candidates.randomElement() {
            return picked
        }

        // Widen to ±400 if nothing in tight band
        let wider = puzzles.filter { puzzle in
            !usedIDs.contains(puzzle.id) &&
            abs(puzzle.rating - estimatedELO) <= 400
        }

        if let picked = wider.randomElement() {
            return picked
        }

        // Fallback: any unused puzzle, preferring closest rating
        return puzzles
            .filter { !usedIDs.contains($0.id) }
            .sorted { abs($0.rating - estimatedELO) < abs($1.rating - estimatedELO) }
            .first
    }

    /// Elo update formula with K=150.
    /// Returns the new estimated ELO, clamped to [400, 2000].
    static func updateEstimate(current: Int, puzzleRating: Int, correct: Bool) -> Int {
        let expected = 1.0 / (1.0 + pow(10.0, Double(puzzleRating - current) / 400.0))
        let delta: Double
        if correct {
            delta = 150.0 * (1.0 - expected)
        } else {
            delta = -150.0 * expected
        }
        return min(2000, max(400, current + Int(delta.rounded())))
    }
}
