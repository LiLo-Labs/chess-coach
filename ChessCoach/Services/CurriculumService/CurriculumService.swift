import Foundation

final class CurriculumService: Sendable {
    let opening: Opening
    let activeLine: OpeningLine?
    let familiarity: Double

    /// The moves to check against — active line or main line.
    private var moves: [OpeningMove] {
        activeLine?.moves ?? opening.mainLine
    }

    init(opening: Opening, activeLine: OpeningLine? = nil, familiarity: Double) {
        self.opening = opening
        self.activeLine = activeLine
        self.familiarity = familiarity
    }

    /// Returns the forced UCI move for the opponent at the given ply, or nil if Maia/Stockfish should play freely.
    /// - familiarity < 0.3: force all book moves (learning)
    /// - familiarity 0.3–0.7: force first 4 plies (practicing)
    /// - familiarity >= 0.7: no override (familiar)
    func getMaiaOverride(atPly ply: Int) -> String? {
        let line = moves

        if familiarity < 0.3 {
            guard ply < line.count else { return nil }
            return line[ply].uci
        } else if familiarity < 0.7 {
            if ply < 4 && ply < line.count {
                return line[ply].uci
            }
            return nil
        } else {
            return nil
        }
    }

    /// Whether coaching should be shown for this move.
    /// - familiarity < 0.3: always coach
    /// - familiarity 0.3–0.7: coach on non-good moves
    /// - familiarity >= 0.7: only coach on mistakes
    func shouldCoach(moveCategory: MoveCategory) -> Bool {
        if familiarity < 0.3 {
            return true
        } else if familiarity < 0.7 {
            return moveCategory != .goodMove
        } else {
            return moveCategory == .mistake
        }
    }

    /// Categorize the user's move for coaching purposes.
    func categorizeUserMove(atPly ply: Int, move: String, stockfishScore: Int) -> MoveCategory {
        let isOnLine = !isDeviation(atPly: ply, move: move)

        if familiarity < 0.3 {
            if isOnLine { return .goodMove }
            if abs(stockfishScore) < 50 { return .okayMove }
            return .mistake
        } else if familiarity < 0.7 {
            if isOnLine { return .goodMove }
            if abs(stockfishScore) < 100 { return .okayMove }
            return .mistake
        } else {
            if abs(stockfishScore) < 30 { return .goodMove }
            if abs(stockfishScore) < 100 { return .okayMove }
            return .mistake
        }
    }

    /// Check if a move is a deviation from the active line at a given ply.
    func isDeviation(atPly ply: Int, move: String) -> Bool {
        let line = moves
        guard ply < line.count else { return true }
        return line[ply].uci != move
    }

    // MARK: - Discovery Mode

    /// Returns true when at a multi-child node and familiarity >= 0.3.
    func shouldDiscover(atPly ply: Int) -> Bool {
        guard familiarity >= 0.3 else { return false }
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
}
