import Foundation

/// Guidance generated when a game goes off-book (deviates from known opening theory).
struct OffBookGuidance: Sendable {
    /// e.g. "You left the Italian Game at move 7"
    let summary: String
    /// e.g. "The plan is to target f7 with your bishop"
    let planReminder: String
    /// e.g. "Consider developing your bishop to c4"
    let suggestion: String?
    /// Strategic goals that are still relevant given the current position
    let relevantGoals: [StrategicGoal]
}

/// Generates plan-based coaching when the game goes off-book.
///
/// This service is pure logic — no LLM calls, no async. It inspects the FEN
/// to determine which strategic goals and piece targets are still relevant,
/// then builds human-readable guidance from the opening's plan.
struct OffBookCoachingService: Sendable {

    /// Generate coaching guidance for an off-book position.
    ///
    /// - Parameters:
    ///   - fen: Current board position in FEN notation
    ///   - opening: The opening the player was studying
    ///   - deviationPly: The half-move (ply) at which the game went off-book
    ///   - moveHistory: SAN move list up to this point
    ///   - opponentDeviation: If the *opponent* deviated, what they played vs. expected
    /// - Returns: Structured guidance for the coaching UI
    func generateGuidance(
        fen: String,
        opening: Opening,
        deviationPly: Int,
        moveHistory: [String],
        opponentDeviation: (played: String, expected: String)? = nil
    ) -> OffBookGuidance {
        guard let plan = opening.plan else {
            return genericGuidance(opening: opening, deviationPly: deviationPly, opponentDeviation: opponentDeviation)
        }

        let board = FENParser.boardString(from: fen)
        let isWhite = opening.color == .white

        // 1. Filter strategic goals to those still relevant
        let relevantGoals = plan.strategicGoals.filter { goal in
            guard let condition = goal.checkCondition else {
                // No condition means always relevant
                return true
            }
            return !isConditionMet(condition, board: board, fen: fen, isWhite: isWhite)
        }.sorted { $0.priority < $1.priority }

        // 2. Find unmet piece targets
        let unmetTargets = plan.pieceTargets.filter { target in
            let pieceChar = Self.pieceChar(name: target.piece, isWhite: isWhite)
            return !target.idealSquares.contains { square in
                FENParser.isPieceOnSquare(piece: pieceChar, square: square, board: board)
            }
        }

        // 3. Build summary
        let moveNumber = (deviationPly / 2) + 1
        let summary: String
        if let deviation = opponentDeviation {
            summary = "Your opponent left the \(opening.name) at move \(moveNumber) — they played \(deviation.played) instead of the expected \(deviation.expected)."
        } else {
            summary = "You left the \(opening.name) at move \(moveNumber)."
        }

        // 4. Build plan reminder
        let planReminder = plan.summary

        // 5. Build suggestion from unmet targets or top relevant goal
        let suggestion: String?
        if let firstUnmet = unmetTargets.first {
            let squares = firstUnmet.idealSquares.joined(separator: " or ")
            suggestion = "Consider developing your \(firstUnmet.piece) to \(squares) — \(firstUnmet.reasoning.lowercasedFirst)"
        } else if let topGoal = relevantGoals.first {
            suggestion = topGoal.description
        } else {
            suggestion = nil
        }

        return OffBookGuidance(
            summary: summary,
            planReminder: planReminder,
            suggestion: suggestion,
            relevantGoals: relevantGoals
        )
    }

    // MARK: - Private

    /// Generic guidance when the opening has no plan data.
    private func genericGuidance(
        opening: Opening,
        deviationPly: Int,
        opponentDeviation: (played: String, expected: String)?
    ) -> OffBookGuidance {
        let moveNumber = (deviationPly / 2) + 1
        let summary: String
        if let deviation = opponentDeviation {
            summary = "Your opponent left the \(opening.name) at move \(moveNumber) — they played \(deviation.played) instead of the expected \(deviation.expected)."
        } else {
            summary = "You left the \(opening.name) at move \(moveNumber)."
        }
        return OffBookGuidance(
            summary: summary,
            planReminder: "Keep developing your pieces toward the center and castle early.",
            suggestion: "Focus on getting your knights and bishops out before moving the same piece twice.",
            relevantGoals: []
        )
    }

    /// Check whether a condition string is already met in the current position.
    private func isConditionMet(_ condition: String, board: String, fen: String, isWhite: Bool) -> Bool {
        // bishop_on_diagonal_a2g8
        if condition.hasPrefix("bishop_on_diagonal_") {
            let diagonal = String(condition.dropFirst("bishop_on_diagonal_".count))
            return FENParser.isBishopOnDiagonal(diagonal: diagonal, board: board, isWhite: isWhite)
        }
        // pawn_on_e4
        if condition.hasPrefix("pawn_on_") {
            let square = String(condition.dropFirst("pawn_on_".count))
            let pawnChar: Character = isWhite ? "P" : "p"
            return FENParser.isPieceOnSquare(piece: pawnChar, square: square, board: board)
        }
        // castled_kingside
        if condition == "castled_kingside" {
            return FENParser.isCastled(kingside: true, fen: fen, isWhite: isWhite)
        }
        // castled_queenside
        if condition == "castled_queenside" {
            return FENParser.isCastled(kingside: false, fen: fen, isWhite: isWhite)
        }
        // knight_on_f3, etc.
        if condition.hasPrefix("knight_on_") {
            let square = String(condition.dropFirst("knight_on_".count))
            let knightChar: Character = isWhite ? "N" : "n"
            return FENParser.isPieceOnSquare(piece: knightChar, square: square, board: board)
        }
        // Unknown condition — treat as not met (goal stays relevant)
        return false
    }

    /// Map piece name to FEN character.
    static func pieceChar(name: String, isWhite: Bool) -> Character {
        let lower = name.lowercased()
        let base: Character
        if lower.contains("bishop") {
            base = "B"
        } else if lower.contains("knight") {
            base = "N"
        } else if lower.contains("rook") {
            base = "R"
        } else if lower.contains("queen") {
            base = "Q"
        } else if lower.contains("king") && !lower.contains("knight") {
            base = "K"
        } else if lower.contains("pawn") {
            base = "P"
        } else {
            base = "P" // fallback
        }
        return isWhite ? base : Character(base.lowercased())
    }
}

// MARK: - FEN Parsing Utilities

/// Lightweight FEN parsing for positional checks — no full board representation needed.
enum FENParser {

    /// Extract just the board placement string (rank 8 down to rank 1) from a FEN.
    static func boardString(from fen: String) -> String {
        String(fen.prefix(while: { $0 != " " }))
    }

    /// Check if a specific piece character is on a specific square.
    ///
    /// - Parameters:
    ///   - piece: FEN character, e.g. 'B' for white bishop, 'n' for black knight
    ///   - square: Algebraic square, e.g. "c4"
    ///   - board: FEN board string (ranks separated by '/')
    static func isPieceOnSquare(piece: Character, square: String, board: String) -> Bool {
        guard let (file, rank) = parseSquare(square) else { return false }
        let ranks = board.split(separator: "/")
        // FEN ranks go from 8 (index 0) to 1 (index 7)
        let rankIndex = 7 - rank
        guard rankIndex >= 0, rankIndex < ranks.count else { return false }
        let rankStr = String(ranks[rankIndex])

        var currentFile = 0
        for ch in rankStr {
            if ch.isNumber {
                currentFile += ch.wholeNumberValue ?? 0
            } else {
                if currentFile == file && ch == piece {
                    return true
                }
                currentFile += 1
            }
        }
        return false
    }

    /// Check if any bishop (of the specified color) is on a named diagonal like "a2g8".
    ///
    /// The diagonal is specified by two corner squares, e.g. "a2g8" means
    /// the diagonal from a2 to g8 (all squares where file + rank share the
    /// same light/dark color and lie on that line).
    static func isBishopOnDiagonal(diagonal: String, board: String, isWhite: Bool) -> Bool {
        let diagonalSquares = squaresOnDiagonal(diagonal)
        let bishopChar: Character = isWhite ? "B" : "b"
        return diagonalSquares.contains { square in
            isPieceOnSquare(piece: bishopChar, square: square, board: board)
        }
    }

    /// Proxy check for castling via castling rights in FEN.
    ///
    /// If the player has lost castling rights on a given side, we assume they've castled
    /// (or moved their king/rook, which is close enough for coaching purposes).
    static func isCastled(kingside: Bool, fen: String, isWhite: Bool) -> Bool {
        let parts = fen.split(separator: " ")
        guard parts.count >= 3 else { return false }
        let castling = String(parts[2])
        if castling == "-" { return true } // All rights gone — likely castled
        if isWhite {
            let right: Character = kingside ? "K" : "Q"
            return !castling.contains(right)
        } else {
            let right: Character = kingside ? "k" : "q"
            return !castling.contains(right)
        }
    }

    /// Parse an algebraic square like "c4" into (file: 2, rank: 3) — both 0-indexed.
    static func parseSquare(_ square: String) -> (file: Int, rank: Int)? {
        guard square.count == 2,
              let fileChar = square.first,
              let rankChar = square.last,
              fileChar >= "a", fileChar <= "h",
              let rankNum = rankChar.wholeNumberValue,
              rankNum >= 1, rankNum <= 8 else {
            return nil
        }
        let file = Int(fileChar.asciiValue! - Character("a").asciiValue!)
        let rank = rankNum - 1
        return (file, rank)
    }

    /// Compute all algebraic squares on a diagonal defined by two corner squares.
    ///
    /// e.g. "a2g8" → ["a2", "b3", "c4", "d5", "e6", "f7", "g8"]
    static func squaresOnDiagonal(_ diagonal: String) -> [String] {
        // Parse the two endpoint squares
        let chars = Array(diagonal)
        guard chars.count == 4 else { return [] }
        let startSquare = String(chars[0...1])
        let endSquare = String(chars[2...3])
        guard let start = parseSquare(startSquare),
              let end = parseSquare(endSquare) else { return [] }

        let fileDelta = end.file > start.file ? 1 : -1
        let rankDelta = end.rank > start.rank ? 1 : -1

        var squares: [String] = []
        var f = start.file
        var r = start.rank
        while f >= 0 && f <= 7 && r >= 0 && r <= 7 {
            let fileChar = Character(UnicodeScalar(UInt8(f) + Character("a").asciiValue!))
            squares.append("\(fileChar)\(r + 1)")
            if f == end.file && r == end.rank { break }
            f += fileDelta
            r += rankDelta
        }
        return squares
    }
}

// MARK: - String Helper

private extension String {
    /// Returns a copy with the first character lowercased.
    var lowercasedFirst: String {
        guard let first = self.first else { return self }
        return first.lowercased() + self.dropFirst()
    }
}
