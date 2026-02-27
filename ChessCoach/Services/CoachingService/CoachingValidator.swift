import Foundation
import ChessKit

struct CoachingValidator {
    struct ParsedCoaching {
        let text: String
        let claims: [SquareClaim]
        let rawRefs: String
    }

    /// A reference to a square, optionally with a piece type.
    struct SquareClaim {
        let square: String
        let pieceKind: PieceKind?
    }

    /// Parse structured LLM response into coaching text + declared claims.
    /// Supports both formats:
    ///   "bishop e5, knight c3"  (piece + square)
    ///   "e5, c3, f3"           (square only — from constrained prompt)
    static func parse(response: String) -> ParsedCoaching {
        let lines = response.components(separatedBy: "\n")
        var claims: [SquareClaim] = []
        var coachingText = response
        var rawRefs = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("REFS:") {
                rawRefs = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                claims = parseRefs(rawRefs)
            } else if trimmed.uppercased().hasPrefix("COACHING:") {
                coachingText = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            }
        }

        // If no COACHING: prefix found, strip REFS line and use the rest
        if !response.uppercased().contains("COACHING:") {
            coachingText = lines.filter { !$0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("REFS:") }
                .joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }

        return ParsedCoaching(text: coachingText, claims: claims, rawRefs: rawRefs)
    }

    /// Post-validate claims against actual board position.
    /// Removes invalid refs instead of rejecting the entire response.
    /// Returns coaching text if any valid refs remain (or if no refs were claimed).
    /// Returns nil only if coaching text is empty.
    static func validate(parsed: ParsedCoaching, fen: String) -> String? {
        guard !parsed.text.isEmpty else { return nil }

        // No claims = nothing to validate, return coaching as-is
        guard !parsed.claims.isEmpty else {
            return parsed.text
        }

        let position = FenSerialization.default.deserialize(fen: fen)
        let board = position.board
        var validCount = 0
        var invalidCount = 0

        for claim in parsed.claims {
            let piece = board[claim.square]
            if let piece {
                // If claim specifies a piece kind, verify it matches
                if let expectedKind = claim.pieceKind {
                    if piece.kind == expectedKind {
                        validCount += 1
                    } else {
                        invalidCount += 1
                    }
                } else {
                    // Square-only claim: just check a piece exists there
                    validCount += 1
                }
            } else {
                invalidCount += 1
            }
        }

        #if DEBUG
        if invalidCount > 0 {
            print("[CoachingValidator] Post-validation: \(validCount) valid, \(invalidCount) invalid refs removed")
        }
        #endif

        // Return coaching text — post-validation strips bad refs from display,
        // but the coaching sentence itself is still useful
        return parsed.text
    }

    /// Get only the validated square references for board highlighting.
    /// Call this to get the squares that should actually be highlighted on the board.
    static func validatedSquares(parsed: ParsedCoaching, fen: String) -> [String] {
        let position = FenSerialization.default.deserialize(fen: fen)
        let board = position.board

        return parsed.claims.compactMap { claim in
            guard let piece = board[claim.square] else { return nil }
            if let expectedKind = claim.pieceKind, piece.kind != expectedKind {
                return nil
            }
            return claim.square
        }
    }

    // Parse refs string — supports both "bishop e5, knight c3" and "e5, c3, f3" formats
    private static func parseRefs(_ str: String) -> [SquareClaim] {
        let lowered = str.trimmingCharacters(in: .whitespaces).lowercased()
        if lowered == "none" || lowered.isEmpty {
            return []
        }

        let pieceMap: [String: PieceKind] = [
            "king": .king, "queen": .queen, "rook": .rook,
            "bishop": .bishop, "knight": .knight, "pawn": .pawn
        ]

        let squarePattern = try! NSRegularExpression(pattern: "\\b([a-h][1-8])\\b")

        return str.components(separatedBy: ",")
            .compactMap { part -> SquareClaim? in
                let trimmed = part.trimmingCharacters(in: .whitespaces).lowercased()
                let tokens = trimmed.split(separator: " ")

                // Extract piece kind from first token if present
                let kind = tokens.first.flatMap { pieceMap[String($0)] }

                // Find a square ([a-h][1-8]) anywhere in the part — handles
                // "bishop e5", "bishop on e5", "e5", etc.
                let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
                if let match = squarePattern.firstMatch(in: trimmed, range: nsRange),
                   let range = Range(match.range(at: 1), in: trimmed) {
                    return SquareClaim(square: String(trimmed[range]), pieceKind: kind)
                }

                return nil
            }
    }
}
