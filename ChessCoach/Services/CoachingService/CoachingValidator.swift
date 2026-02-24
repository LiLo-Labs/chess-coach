import ChessKit

struct CoachingValidator {
    struct ParsedCoaching {
        let text: String
        let claims: [PieceSquareClaim]
    }

    struct PieceSquareClaim {
        let pieceKind: PieceKind
        let square: String
    }

    /// Parse structured LLM response into coaching text + declared claims.
    /// Expected format:
    ///   REFS: bishop e5, knight c3
    ///   COACHING: Your bishop controls the center...
    static func parse(response: String) -> ParsedCoaching {
        let lines = response.components(separatedBy: "\n")
        var refs: [PieceSquareClaim] = []
        var coachingText = response

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("REFS:") {
                let refStr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                refs = parseRefs(refStr)
            } else if trimmed.uppercased().hasPrefix("COACHING:") {
                coachingText = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            }
        }

        // If no COACHING: prefix found, strip REFS line and use the rest
        if !response.uppercased().contains("COACHING:") {
            coachingText = lines.filter { !$0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("REFS:") }
                .joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }

        return ParsedCoaching(text: coachingText, claims: refs)
    }

    /// Validate parsed claims against actual board position.
    /// Returns coaching text if valid, nil if any claim is wrong.
    static func validate(parsed: ParsedCoaching, fen: String) -> String? {
        guard !parsed.claims.isEmpty else {
            return parsed.text
        }

        let position = FenSerialization.default.deserialize(fen: fen)
        let board = position.board

        for claim in parsed.claims {
            let piece = board[claim.square]
            if piece == nil || piece!.kind != claim.pieceKind {
                return nil
            }
        }
        return parsed.text
    }

    // Parse "bishop e5, knight c3" → [PieceSquareClaim]
    private static func parseRefs(_ str: String) -> [PieceSquareClaim] {
        let lowered = str.trimmingCharacters(in: .whitespaces).lowercased()
        if lowered == "none" || lowered.isEmpty {
            return []
        }

        let pieceMap: [String: PieceKind] = [
            "king": .king, "queen": .queen, "rook": .rook,
            "bishop": .bishop, "knight": .knight, "pawn": .pawn
        ]
        return str.components(separatedBy: ",")
            .compactMap { part in
                let tokens = part.trimmingCharacters(in: .whitespaces)
                    .lowercased().split(separator: " ")
                guard tokens.count == 2,
                      let kind = pieceMap[String(tokens[0])],
                      tokens[1].count == 2 else { return nil }
                return PieceSquareClaim(pieceKind: kind, square: String(tokens[1]))
            }
    }
}
