import Foundation

/// Pure PGN parser — extracts headers and SAN moves from PGN text.
/// Reuses the proven `GameState.makeSANMove()` path for validation.
struct PGNParser {

    struct ParsedGame: Sendable {
        var headers: [String: String]
        var sanMoves: [String]
    }

    // MARK: - Public

    /// Parse a single PGN game string into headers + SAN moves.
    static func parse(_ pgn: String) -> ParsedGame? {
        let (headers, moveText) = splitHeadersAndMoves(pgn)
        guard !moveText.isEmpty else { return nil }
        let sans = extractSANTokens(from: moveText)
        guard !sans.isEmpty else { return nil }
        return ParsedGame(headers: headers, sanMoves: sans)
    }

    /// Parse a multi-game PGN string (games separated by blank lines between moves and next header).
    static func parseMultiple(_ pgn: String) -> [ParsedGame] {
        let games = splitGames(pgn)
        return games.compactMap { parse($0) }
    }

    /// Replay SAN moves on a GameState, collecting UCI moves and validating legality.
    /// Returns nil if any move is illegal.
    static func replayMoves(_ sanMoves: [String]) -> (uciMoves: [String], fens: [String])? {
        let gs = GameState()
        var uciMoves: [String] = []
        var fens: [String] = []

        for san in sanMoves {
            fens.append(gs.fen)
            let legalBefore = gs.game.legalMoves
            guard gs.makeSANMove(san) else { return nil }

            // Reconstruct UCI from the last move in history
            if let last = gs.moveHistory.last {
                var uci = "\(last.from)\(last.to)"
                if let promo = last.promotion {
                    let promoChar: String
                    switch promo {
                    case .queen: promoChar = "q"
                    case .rook: promoChar = "r"
                    case .bishop: promoChar = "b"
                    case .knight: promoChar = "n"
                    default: promoChar = ""
                    }
                    uci += promoChar
                }
                uciMoves.append(uci)
            }
        }

        return (uciMoves, fens)
    }

    // MARK: - Private

    /// Split PGN into header block and move text block.
    private static func splitHeadersAndMoves(_ pgn: String) -> ([String: String], String) {
        var headers: [String: String] = [:]
        var moveLines: [String] = []
        var inMoves = false

        for line in pgn.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !headers.isEmpty { inMoves = true }
                continue
            }
            if !inMoves && trimmed.hasPrefix("[") {
                // Parse header: [Key "Value"]
                if let match = trimmed.range(of: #"\[(\w+)\s+"([^"]*)"\]"#, options: .regularExpression) {
                    let content = trimmed[match].dropFirst().dropLast() // strip [ ]
                    let parts = String(content)
                    if let spaceIdx = parts.firstIndex(of: " ") {
                        let key = String(parts[parts.startIndex..<spaceIdx])
                        var value = String(parts[parts.index(after: spaceIdx)...])
                        // Strip quotes
                        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        headers[key] = value
                    }
                }
            } else {
                inMoves = true
                moveLines.append(trimmed)
            }
        }

        return (headers, moveLines.joined(separator: " "))
    }

    /// Extract SAN tokens from move text, stripping comments, variations, NAGs, move numbers, and results.
    private static func extractSANTokens(from moveText: String) -> [String] {
        var text = moveText

        // Strip comments {...}
        text = text.replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)

        // Strip variations (...) — handle nested by iterating
        while text.contains("(") {
            text = text.replacingOccurrences(of: #"\([^()]*\)"#, with: "", options: .regularExpression)
        }

        // Strip NAGs ($123, !, ?, !!, ??, !?, ?!)
        text = text.replacingOccurrences(of: #"\$\d+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[!?]+"#, with: "", options: .regularExpression)

        // Split on whitespace
        let tokens = text.split(separator: " ").compactMap { token -> String? in
            let s = token.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { return nil }
            // Skip move numbers (e.g., "1.", "12.", "1...")
            if s.hasSuffix(".") || s.contains("...") { return nil }
            // Also skip pure move numbers like "1" "23" when followed by move
            if s.allSatisfy({ $0.isNumber || $0 == "." }) { return nil }
            // Skip result tokens
            if s == "1-0" || s == "0-1" || s == "1/2-1/2" || s == "*" { return nil }
            return s
        }

        return tokens
    }

    /// Split a multi-game PGN string into individual game strings.
    private static func splitGames(_ pgn: String) -> [String] {
        var games: [String] = []
        var current: [String] = []

        for line in pgn.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // New game starts with a header after we've seen move text
            if trimmed.hasPrefix("[") && !current.isEmpty {
                let hasMoveLine = current.contains { l in
                    let t = l.trimmingCharacters(in: .whitespaces)
                    return !t.isEmpty && !t.hasPrefix("[")
                }
                if hasMoveLine {
                    games.append(current.joined(separator: "\n"))
                    current = []
                }
            }
            current.append(line)
        }

        if !current.isEmpty {
            games.append(current.joined(separator: "\n"))
        }

        return games
    }
}
