import Foundation

/// Builds opening trees by walking a polyglot book from the starting position.
struct OpeningTreeBuilder: Sendable {
    let book: PolyglotBook

    /// Configuration for tree building.
    struct Config: Sendable {
        var maxDepth: Int = 30          // max plies to walk
        var maxBranching: Int = 3       // max children per node
        var minWeightFraction: Double = 0.05  // min weight as fraction of total at position
        var minAbsoluteWeight: UInt16 = 1     // min absolute weight to include
    }

    /// Build a tree from the starting position (or a given FEN).
    func buildTree(
        from fen: String = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        config: Config = Config()
    ) -> OpeningNode {
        let hash = PolyglotZobrist.hash(fen: fen)
        return buildNode(hash: hash, fen: fen, depth: 0, config: config)
    }

    /// Build a tree rooted at a specific opening's starting moves.
    /// Plays through the given moves first, then explores branches.
    func buildTree(
        afterMoves moves: [String],
        startFEN: String = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        config: Config = Config()
    ) -> OpeningNode {
        // Walk through the given moves to reach the position
        var board = SimpleBoard(fen: startFEN)
        for move in moves {
            board.applyUCIMove(move)
        }
        let fen = board.toFEN()
        let hash = PolyglotZobrist.hash(fen: fen)
        return buildNode(hash: hash, fen: fen, depth: 0, config: config)
    }

    private func buildNode(
        hash: UInt64,
        fen: String,
        depth: Int,
        config: Config
    ) -> OpeningNode {
        guard depth < config.maxDepth else {
            return OpeningNode(children: [], weight: 0)
        }

        let entries = book.lookup(hash: hash)
        guard !entries.isEmpty else {
            return OpeningNode(children: [], weight: 0)
        }

        // Filter by weight threshold
        let totalWeight = entries.reduce(0) { $0 + UInt32($1.weight) }
        let minWeight = max(
            config.minAbsoluteWeight,
            UInt16(Double(totalWeight) * config.minWeightFraction)
        )

        let filtered = entries
            .filter { $0.weight >= minWeight }
            .prefix(config.maxBranching)

        var children: [OpeningNode] = []
        let isFirst = true

        for (i, entry) in filtered.enumerated() {
            var board = SimpleBoard(fen: fen)
            let san = board.moveToSAN(uci: entry.move)
            board.applyUCIMove(entry.move)
            let newFEN = board.toFEN()
            let newHash = PolyglotZobrist.hash(fen: newFEN)

            let move = OpeningMove(uci: entry.move, san: san, explanation: "")

            var child = buildNode(
                hash: newHash,
                fen: newFEN,
                depth: depth + 1,
                config: config
            )
            child = OpeningNode(
                id: child.id,
                move: move,
                children: child.children,
                isMainLine: i == 0 && isFirst,
                variationName: nil,
                weight: entry.weight
            )
            children.append(child)
        }

        return OpeningNode(children: children, weight: 0)
    }
}

// MARK: - Minimal board representation for FEN generation

/// A minimal chess board that can apply UCI moves and generate FENs.
/// Used by the tree builder to walk positions without depending on ChessKit.
struct SimpleBoard: Sendable {
    var squares: [Character?]  // 64 squares, a1=0, h8=63
    var whiteToMove: Bool
    var castling: String
    var enPassant: String
    var halfmove: Int
    var fullmove: Int

    init(fen: String = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1") {
        squares = Array(repeating: nil, count: 64)
        whiteToMove = true
        castling = "KQkq"
        enPassant = "-"
        halfmove = 0
        fullmove = 1

        let parts = fen.split(separator: " ")
        guard parts.count >= 4 else { return }

        // Parse board
        let rows = parts[0].split(separator: "/")
        for (rankIdx, row) in rows.enumerated() {
            let rank = 7 - rankIdx
            var file = 0
            for ch in row {
                if let skip = ch.wholeNumberValue {
                    file += skip
                } else {
                    squares[rank * 8 + file] = ch
                    file += 1
                }
            }
        }

        whiteToMove = parts[1] == "w"
        castling = String(parts[2])
        enPassant = String(parts[3])
        if parts.count > 4 { halfmove = Int(parts[4]) ?? 0 }
        if parts.count > 5 { fullmove = Int(parts[5]) ?? 1 }
    }

    private func squareIndex(_ sq: String) -> Int {
        let file = Int(sq.first!.asciiValue!) - 97
        let rank = Int(String(sq.last!))! - 1
        return rank * 8 + file
    }

    private func indexToSquare(_ idx: Int) -> String {
        let file = idx % 8
        let rank = idx / 8
        return "\(Character(UnicodeScalar(97 + file)!))\(rank + 1)"
    }

    mutating func applyUCIMove(_ uci: String) {
        let from = String(uci.prefix(2))
        let to = String(uci.dropFirst(2).prefix(2))
        let fromIdx = squareIndex(from)
        let toIdx = squareIndex(to)
        let piece = squares[fromIdx]

        // Detect en passant capture
        if (piece == "P" || piece == "p") && to == enPassant {
            let captureRank = piece == "P" ? (toIdx / 8 - 1) : (toIdx / 8 + 1)
            squares[captureRank * 8 + (toIdx % 8)] = nil
        }

        // Set en passant
        if (piece == "P" && fromIdx / 8 == 1 && toIdx / 8 == 3) {
            enPassant = indexToSquare(fromIdx + 8)
        } else if (piece == "p" && fromIdx / 8 == 6 && toIdx / 8 == 4) {
            enPassant = indexToSquare(fromIdx - 8)
        } else {
            enPassant = "-"
        }

        // Handle castling move
        if piece == "K" || piece == "k" {
            let fileDiff = (toIdx % 8) - (fromIdx % 8)
            if abs(fileDiff) == 2 {
                // Castling
                let rank = fromIdx / 8
                if fileDiff > 0 {
                    // Kingside
                    squares[rank * 8 + 5] = squares[rank * 8 + 7]
                    squares[rank * 8 + 7] = nil
                } else {
                    // Queenside
                    squares[rank * 8 + 3] = squares[rank * 8 + 0]
                    squares[rank * 8 + 0] = nil
                }
            }
        }

        // Update castling rights
        if piece == "K" { castling = castling.replacingOccurrences(of: "K", with: "").replacingOccurrences(of: "Q", with: "") }
        if piece == "k" { castling = castling.replacingOccurrences(of: "k", with: "").replacingOccurrences(of: "q", with: "") }
        if from == "a1" || to == "a1" { castling = castling.replacingOccurrences(of: "Q", with: "") }
        if from == "h1" || to == "h1" { castling = castling.replacingOccurrences(of: "K", with: "") }
        if from == "a8" || to == "a8" { castling = castling.replacingOccurrences(of: "q", with: "") }
        if from == "h8" || to == "h8" { castling = castling.replacingOccurrences(of: "k", with: "") }

        // Move piece
        squares[toIdx] = piece
        squares[fromIdx] = nil

        // Handle promotion
        if uci.count == 5 {
            let promoChar = uci.last!
            if whiteToMove {
                squares[toIdx] = Character(promoChar.uppercased())
            } else {
                squares[toIdx] = Character(promoChar.lowercased())
            }
        }

        // Update halfmove clock
        if piece == "P" || piece == "p" || squares[toIdx] != nil {
            halfmove = 0
        } else {
            halfmove += 1
        }

        // Toggle turn
        if !whiteToMove { fullmove += 1 }
        whiteToMove.toggle()

        // Fix empty castling
        if castling.isEmpty { castling = "-" }
    }

    func toFEN() -> String {
        var fen = ""
        for rank in stride(from: 7, through: 0, by: -1) {
            var empty = 0
            for file in 0..<8 {
                if let piece = squares[rank * 8 + file] {
                    if empty > 0 {
                        fen += "\(empty)"
                        empty = 0
                    }
                    fen += String(piece)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { fen += "\(empty)" }
            if rank > 0 { fen += "/" }
        }
        fen += " \(whiteToMove ? "w" : "b")"
        fen += " \(castling)"
        fen += " \(enPassant)"
        fen += " \(halfmove)"
        fen += " \(fullmove)"
        return fen
    }

    /// Convert a UCI move to SAN notation (approximate — handles common cases).
    func moveToSAN(uci: String) -> String {
        let from = String(uci.prefix(2))
        let to = String(uci.dropFirst(2).prefix(2))
        let fromIdx = squareIndex(from)
        let piece = squares[fromIdx]

        guard let piece else { return uci }

        let isCapture = squares[squareIndex(to)] != nil || (to == enPassant && (piece == "P" || piece == "p"))
        let captureStr = isCapture ? "x" : ""

        // Castling
        if (piece == "K" || piece == "k") {
            let fileDiff = (squareIndex(to) % 8) - (fromIdx % 8)
            if fileDiff == 2 { return "O-O" }
            if fileDiff == -2 { return "O-O-O" }
        }

        // Pawn moves
        if piece == "P" || piece == "p" {
            var san = ""
            if isCapture {
                san = "\(from.first!)\(captureStr)\(to)"
            } else {
                san = to
            }
            // Promotion
            if uci.count == 5 {
                san += "=\(uci.last!.uppercased())"
            }
            return san
        }

        // Piece moves
        let pieceChar = String(piece.uppercased())
        return "\(pieceChar)\(captureStr)\(to)"
    }
}
