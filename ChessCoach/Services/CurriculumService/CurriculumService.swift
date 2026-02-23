import Foundation

final class CurriculumService: Sendable {
    let opening: Opening
    let phase: LearningPhase

    init(opening: Opening, phase: LearningPhase) {
        self.opening = opening
        self.phase = phase
    }

    /// Returns the forced UCI move for the opponent at the given ply, or nil if Maia/Stockfish should play freely.
    func getMaiaOverride(atPly ply: Int) -> String? {
        switch phase {
        case .learningMainLine:
            // Always force main line moves
            return opening.expectedMove(atPly: ply)?.uci

        case .naturalDeviations:
            // Force main line for the first few moves, allow deviation after ply 6
            if ply < 6 {
                return opening.expectedMove(atPly: ply)?.uci
            }
            return nil

        case .widerVariations:
            // Force only the first 2 moves, then let the engine play
            if ply < 2 {
                return opening.expectedMove(atPly: ply)?.uci
            }
            return nil

        case .freePlay:
            // Never override — engine plays freely
            return nil
        }
    }

    /// Categorize the user's move for coaching purposes.
    func categorizeUserMove(atPly ply: Int, move: String, stockfishScore: Int) -> MoveCategory {
        let isMainLine = !opening.isDeviation(atPly: ply, move: move)

        switch phase {
        case .learningMainLine, .naturalDeviations:
            if isMainLine {
                return .goodMove
            }
            // Check how bad the deviation is based on score
            if abs(stockfishScore) < 50 {
                return .okayMove
            }
            return .mistake

        case .widerVariations:
            // More lenient — only flag real mistakes
            if abs(stockfishScore) < 30 {
                return .goodMove
            }
            if abs(stockfishScore) < 100 {
                return .okayMove
            }
            return .mistake

        case .freePlay:
            // Only centipawn-based evaluation
            if abs(stockfishScore) < 30 {
                return .goodMove
            }
            if abs(stockfishScore) < 100 {
                return .okayMove
            }
            return .mistake
        }
    }

    /// Check if a move is a deviation from theory at a given ply.
    func isDeviation(atPly ply: Int, move: String) -> Bool {
        opening.isDeviation(atPly: ply, move: move)
    }
}
