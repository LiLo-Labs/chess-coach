import Foundation

final class CurriculumService: Sendable {
    let opening: Opening
    let activeLine: OpeningLine?
    let phase: LearningPhase

    /// The moves to check against — active line or main line.
    private var moves: [OpeningMove] {
        activeLine?.moves ?? opening.mainLine
    }

    init(opening: Opening, activeLine: OpeningLine? = nil, phase: LearningPhase) {
        self.opening = opening
        self.activeLine = activeLine
        self.phase = phase
    }

    /// Returns the forced UCI move for the opponent at the given ply, or nil if Maia/Stockfish should play freely.
    func getMaiaOverride(atPly ply: Int) -> String? {
        let line = moves

        switch phase {
        case .learningMainLine:
            // Always force line moves
            guard ply < line.count else { return nil }
            return line[ply].uci

        case .naturalDeviations:
            // Force line for the first few moves, allow deviation after ply 6
            if ply < 6 && ply < line.count {
                return line[ply].uci
            }
            return nil

        case .widerVariations:
            // Force only the first 2 moves, then let the engine play
            if ply < 2 && ply < line.count {
                return line[ply].uci
            }
            return nil

        case .freePlay:
            // Never override — engine plays freely
            return nil
        }
    }

    /// Categorize the user's move for coaching purposes.
    func categorizeUserMove(atPly ply: Int, move: String, stockfishScore: Int) -> MoveCategory {
        let isOnLine = !isDeviation(atPly: ply, move: move)

        switch phase {
        case .learningMainLine, .naturalDeviations:
            if isOnLine {
                return .goodMove
            }
            if abs(stockfishScore) < 50 {
                return .okayMove
            }
            return .mistake

        case .widerVariations:
            if abs(stockfishScore) < 30 {
                return .goodMove
            }
            if abs(stockfishScore) < 100 {
                return .okayMove
            }
            return .mistake

        case .freePlay:
            if abs(stockfishScore) < 30 {
                return .goodMove
            }
            if abs(stockfishScore) < 100 {
                return .okayMove
            }
            return .mistake
        }
    }

    /// Check if a move is a deviation from the active line at a given ply.
    func isDeviation(atPly ply: Int, move: String) -> Bool {
        let line = moves
        guard ply < line.count else { return true }
        return line[ply].uci != move
    }

    // MARK: - Discovery Mode (Phase 6)

    /// Returns true when at a multi-child node and student phase >= naturalDeviations.
    func shouldDiscover(atPly ply: Int) -> Bool {
        guard phase != .learningMainLine else { return false }
        let options = allBookMoves(atPly: ply)
        return options.count > 1
    }

    /// Returns all valid book continuations at this position.
    func allBookMoves(atPly ply: Int) -> [OpeningMove] {
        let moveHistory = moves.prefix(ply).map(\.uci)
        return opening.continuations(afterMoves: Array(moveHistory))
    }

    // MARK: - PES-Based Categorization

    /// Categorize a move based on its Plan Execution Score.
    /// Used when plan data is available (v2 flow).
    func categorizeFromPES(_ pes: PlanExecutionScore) -> MoveCategory {
        switch pes.category {
        case .masterful, .strong:
            return .goodMove
        case .solid:
            return .okayMove
        case .developing, .needsWork:
            return .mistake
        }
    }

    /// Get Maia override for the new layer-based system.
    /// Layers 1-2: Force book moves. Layer 3+: Free play.
    func getMaiaOverrideForLayer(atPly ply: Int, layer: LearningLayer) -> String? {
        let line = moves

        switch layer {
        case .understandPlan:
            // Always force line moves during plan understanding
            guard ply < line.count else { return nil }
            return line[ply].uci

        case .executePlan:
            // Force opponent moves for first 4 plies to set up the position
            if ply < 4 && ply < line.count {
                return line[ply].uci
            }
            return nil

        case .discoverTheory:
            // Force book moves to demonstrate the canonical order
            guard ply < line.count else { return nil }
            return line[ply].uci

        case .handleVariety:
            // Force first 2 plies, then use varied opponent service
            if ply < 2 && ply < line.count {
                return line[ply].uci
            }
            return nil

        case .realConditions:
            // Never override — full freedom
            return nil
        }
    }
}
