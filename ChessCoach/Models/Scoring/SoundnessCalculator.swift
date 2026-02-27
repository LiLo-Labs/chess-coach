import Foundation

/// Maps Stockfish centipawn loss to a 0-100 soundness score, scaled by student ELO.
///
/// The key insight: a "good game" at ELO 500 tolerates more centipawn loss than
/// a "good game" at ELO 1200, because Stockfish eval is relative to perfect play.
/// We use a continuous formula so there are no jarring threshold boundaries.
enum SoundnessCalculator {
    /// Convert centipawn loss to a soundness score (0-100), scaled by student ELO.
    ///
    /// Uses an exponential decay: `score = 100 * exp(-cpLoss / tolerance)`
    /// where `tolerance` scales with ELO — beginners get a wider tolerance band.
    ///
    /// | ELO   | Tolerance | 30cp → | 80cp → | 150cp → | 300cp → |
    /// |-------|-----------|--------|--------|---------|---------|
    /// | 500   | 120       | 78     | 51     | 29      | 8       |
    /// | 800   | 100       | 74     | 45     | 22      | 5       |
    /// | 1000  | 80        | 69     | 37     | 15      | 2       |
    /// | 1200+ | 60        | 61     | 26     | 8       | 1       |
    ///
    /// At all ELOs, 0cp loss → 100 (perfect), and large losses → near 0.
    static func ceiling(centipawnLoss: Int, userELO: Int = 600) -> Int {
        let loss = Double(abs(centipawnLoss))
        guard loss > 0 else { return 100 }

        let tolerance = toleranceForELO(userELO)
        let raw = 100.0 * exp(-loss / tolerance)
        return max(0, min(100, Int(round(raw))))
    }

    /// ELO-scaled tolerance: lower ELO = more forgiving.
    private static func toleranceForELO(_ elo: Int) -> Double {
        AppConfig.scoring.toleranceForELO(elo)
    }

    /// Compute centipawn loss from before/after eval scores.
    /// A positive result means the move lost centipawns (bad).
    /// `playerIsWhite` determines the sign convention.
    static func centipawnLoss(scoreBefore: Int, scoreAfter: Int, playerIsWhite: Bool) -> Int {
        if playerIsWhite {
            // White wants score to stay high; loss = before - after
            return max(0, scoreBefore - scoreAfter)
        } else {
            // Black wants score to stay low (negative); loss = after - before
            return max(0, scoreAfter - scoreBefore)
        }
    }
}
