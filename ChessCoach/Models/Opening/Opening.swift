import Foundation

struct OpeningMove: Codable, Sendable, Equatable {
    let uci: String
    let san: String
    let explanation: String

    /// Returns display text for the given notation style (improvement 25).
    func displayText(style: String) -> String {
        switch style {
        case "uci": return uci
        case "english": return sanToEnglish(san)
        default: return san  // "san" or any fallback
        }
    }

    /// Convert SAN like "Nf3" to English-style "Knight f3".
    private func sanToEnglish(_ san: String) -> String {
        let pieceMap: [Character: String] = [
            "K": "King", "Q": "Queen", "R": "Rook",
            "B": "Bishop", "N": "Knight"
        ]
        guard let first = san.first, let pieceName = pieceMap[first] else {
            // Pawn move or castling
            if san.hasPrefix("O-O-O") { return "Queenside Castle" }
            if san.hasPrefix("O-O") { return "Kingside Castle" }
            return "Pawn " + san.replacingOccurrences(of: "x", with: " takes ")
        }
        let rest = String(san.dropFirst())
            .replacingOccurrences(of: "x", with: " takes ")
        return pieceName + " " + rest
    }
}

// MARK: - Tree Data Structures

struct OpeningNode: Codable, Sendable, Identifiable {
    let id: String
    let move: OpeningMove?  // nil for root node
    var children: [OpeningNode]
    var isMainLine: Bool
    var variationName: String?
    var weight: UInt16  // from polyglot book

    init(id: String = UUID().uuidString, move: OpeningMove? = nil, children: [OpeningNode] = [], isMainLine: Bool = false, variationName: String? = nil, weight: UInt16 = 0) {
        self.id = id
        self.move = move
        self.children = children
        self.isMainLine = isMainLine
        self.variationName = variationName
        self.weight = weight
    }

    /// Generate a human-readable line name from the last 2-3 SAN moves (e.g. "d3 Nf6 O-O line").
    static func generateLineName(moves: [OpeningMove]) -> String {
        let suffix = moves.suffix(3).map(\.san).joined(separator: " ")
        guard !suffix.isEmpty else { return "Starting Position" }
        return "\(suffix) line"
    }

    /// Flatten the tree into lines by walking each path from root to leaf.
    func allLines(prefix: [OpeningMove] = [], branchPly: Int = 0, parentLineID: String? = nil, inheritedName: String? = nil) -> [OpeningLine] {
        var results: [OpeningLine] = []
        let currentMoves = move.map { prefix + [$0] } ?? prefix
        let currentBranch = move != nil && !isMainLine ? currentMoves.count - 1 : branchPly
        // Use this node's variationName if set, otherwise carry forward the inherited name
        let effectiveName = variationName ?? inheritedName

        if children.isEmpty {
            // Leaf node — this path is a line
            let line = OpeningLine(
                id: id,
                name: effectiveName ?? Self.generateLineName(moves: currentMoves),
                moves: currentMoves,
                branchPoint: currentBranch,
                parentLineID: parentLineID
            )
            results.append(line)
        } else {
            for child in children {
                let childParent = isMainLine ? parentLineID : id
                results.append(contentsOf: child.allLines(
                    prefix: currentMoves,
                    branchPly: currentBranch,
                    parentLineID: childParent,
                    inheritedName: effectiveName
                ))
            }
        }
        return results
    }
}

struct OpeningLine: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let moves: [OpeningMove]
    let branchPoint: Int  // ply where this line diverges from parent
    let parentLineID: String?
}

// MARK: - Opening

struct Opening: Codable, Sendable, Identifiable, Hashable {
    static func == (lhs: Opening, rhs: Opening) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    let id: String
    let name: String
    let description: String
    let color: PlayerColor
    let difficulty: Int // 1-5
    let mainLine: [OpeningMove]

    // Tree-based opening data (nil for legacy hardcoded openings)
    var tree: OpeningNode?
    var lines: [OpeningLine]?

    // Plan-first learning data (v2)
    var plan: OpeningPlan?
    var opponentResponses: OpponentResponseCatalogue?

    enum PlayerColor: String, Codable, Sendable {
        case white
        case black
    }

    // MARK: - Backward-compatible main line queries

    func isDeviation(atPly ply: Int, move: String) -> Bool {
        guard ply < mainLine.count else { return true }
        return mainLine[ply].uci != move
    }

    func expectedMove(atPly ply: Int) -> OpeningMove? {
        guard ply < mainLine.count else { return nil }
        return mainLine[ply]
    }

    // MARK: - Tree-aware queries

    /// Returns available continuations after a given sequence of UCI moves.
    func continuations(afterMoves moves: [String]) -> [OpeningMove] {
        guard let tree else {
            // Fallback: main line only
            if moves.count < mainLine.count {
                let expected = mainLine[moves.count]
                // Verify the move sequence matches main line up to this point
                for (i, m) in moves.enumerated() {
                    if i < mainLine.count && mainLine[i].uci != m {
                        return []
                    }
                }
                return [expected]
            }
            return []
        }

        // Walk the tree following the given moves
        var node = tree
        for move in moves {
            guard let child = node.children.first(where: { $0.move?.uci == move }) else {
                return []
            }
            node = child
        }

        return node.children.compactMap(\.move)
    }

    /// Finds which lines match a partial game (sequence of UCI moves).
    func matchingLines(forMoveSequence moves: [String]) -> [OpeningLine] {
        guard let lines else {
            // Fallback: check if moves match main line
            for (i, m) in moves.enumerated() {
                if i >= mainLine.count || mainLine[i].uci != m {
                    return []
                }
            }
            return [OpeningLine(id: "\(id)/main", name: OpeningNode.generateLineName(moves: mainLine), moves: mainLine, branchPoint: 0, parentLineID: nil)]
        }

        return lines.filter { line in
            for (i, m) in moves.enumerated() {
                if i >= line.moves.count || line.moves[i].uci != m {
                    return false
                }
            }
            return true
        }
    }

    /// Check if a given move matches any known continuation at the given ply.
    func isKnownContinuation(atPly ply: Int, move: String, afterMoves: [String]) -> Bool {
        let continuationMoves = continuations(afterMoves: afterMoves)
        return continuationMoves.contains { $0.uci == move }
    }

    /// Returns the child OpeningNodes at a given position in the tree.
    /// Used for Polyglot weight lookups.
    func childNodes(afterMoves moves: [String]) -> [OpeningNode] {
        guard let tree else { return [] }
        var node = tree
        for move in moves {
            guard let child = node.children.first(where: { $0.move?.uci == move }) else {
                return []
            }
            node = child
        }
        return node.children
    }
}
