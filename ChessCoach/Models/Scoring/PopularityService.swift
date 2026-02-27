import Foundation

/// Provides a popularity adjustment (-5 to +10) based on Polyglot book weights
/// at a given position. Rewards moves that have stood the test of millions of games
/// without over-penalizing novelties.
enum PopularityService {
    /// Compute the popularity adjustment for a move given the Polyglot weights
    /// of all continuations at this position.
    ///
    /// - Parameters:
    ///   - moveWeight: The Polyglot weight of the move played (0 if not in book)
    ///   - allWeights: All continuation weights at this position, sorted descending
    /// - Returns: Adjustment from -5 to +10
    static func adjustment(moveWeight: UInt16, allWeights: [UInt16]) -> Int {
        guard !allWeights.isEmpty else { return 0 }

        let sorted = allWeights.sorted(by: >)

        let cfg = AppConfig.scoring

        if moveWeight == 0 {
            // Move not found in Polyglot book at all
            return cfg.popularityNotInBook
        }

        if moveWeight == sorted[0] {
            // Top move by weight — well-established book move
            return cfg.popularityTopMove
        }

        if sorted.count >= 2 && moveWeight >= sorted[min(2, sorted.count - 1)] {
            // Top 3 move
            return cfg.popularityTop3Move
        }

        // In book but rare
        return cfg.popularityRareMove
    }

    /// Look up Polyglot weights for a move from an array of sibling OpeningNodes.
    /// Returns (moveWeight, allWeights) tuple.
    static func lookupWeights(
        move: String,
        siblings: [OpeningNode]
    ) -> (moveWeight: UInt16, allWeights: [UInt16]) {
        let allWeights: [UInt16] = siblings.map { $0.weight }
        let moveWeight = siblings.first(where: { $0.move?.uci == move })?.weight ?? 0
        return (moveWeight, allWeights)
    }
}
