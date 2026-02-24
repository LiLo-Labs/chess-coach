import Foundation

/// Service that provides varied opponent moves for Practice Opening mode (Stage 4).
/// Selects from known opening continuations weighted by user familiarity, then
/// falls back to Maia for natural off-book play.
final class VariedOpponentService: Sendable {
    let opening: Opening
    private let recentPathsKey: String

    init(opening: Opening) {
        self.opening = opening
        self.recentPathsKey = "chess_coach_practice_paths_\(opening.id)"
    }

    /// Recent session move paths (last 5 sessions) to avoid repetition.
    var recentPaths: [[String]] {
        get {
            (UserDefaults.standard.array(forKey: recentPathsKey) as? [[String]]) ?? []
        }
    }

    func recordPath(_ moves: [String]) {
        var paths = recentPaths
        paths.append(moves)
        // Keep last 5 sessions only
        if paths.count > 5 {
            paths = Array(paths.suffix(5))
        }
        UserDefaults.standard.set(paths, forKey: recentPathsKey)
    }

    /// Pick an opponent move from known opening continuations, weighted by inverse practice count.
    /// Returns nil if no book moves are available (caller should use Maia).
    func pickOpponentMove(
        atPly ply: Int,
        afterMoves moves: [String],
        lineProgress: [String: LineProgress]
    ) -> String? {
        let continuations = opening.continuations(afterMoves: moves)
        guard !continuations.isEmpty else { return nil }

        // If only one continuation, return it directly
        if continuations.count == 1 {
            return continuations[0].uci
        }

        // Weight by inverse familiarity — less-practiced branches get higher weight
        var weights: [(move: String, weight: Double)] = []
        let recentMoveSequences = recentPaths

        for continuation in continuations {
            let testPath = moves + [continuation.uci]
            let matchingLines = opening.matchingLines(forMoveSequence: testPath)

            // Calculate practice count for lines that match this continuation
            var practiceCount = 0
            for line in matchingLines {
                if let lp = lineProgress[line.id] {
                    practiceCount += lp.guidedCompletions + lp.unguidedCompletions
                }
            }

            // Inverse weight: less practice = higher probability
            var weight = 1.0 / Double(max(practiceCount, 1))

            // Penalize paths seen in recent sessions
            for recentPath in recentMoveSequences {
                if recentPath.count > ply,
                   Array(recentPath.prefix(ply + 1)) == testPath {
                    weight *= 0.3 // Reduce probability of repeating exact recent path
                }
            }

            weights.append((move: continuation.uci, weight: weight))
        }

        // Weighted random selection
        let totalWeight = weights.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return continuations[0].uci }

        var roll = Double.random(in: 0..<totalWeight)
        for item in weights {
            roll -= item.weight
            if roll <= 0 {
                return item.move
            }
        }

        return weights.last?.move ?? continuations[0].uci
    }
}
