import Foundation

/// Result of opening detection — which opening(s) match the current game position.
struct OpeningDetection: Sendable {
    /// Matching openings sorted by specificity (most specific line first).
    let matches: [OpeningMatch]

    /// The best (most specific) match, if any.
    var best: OpeningMatch? { matches.first }

    /// Whether we're still in a known opening book.
    var isInBook: Bool { !matches.isEmpty }

    /// The ply (0-indexed) where we left book. Nil if still in book.
    let leftBookAtPly: Int?

    static let none = OpeningDetection(matches: [], leftBookAtPly: nil)
}

/// A single opening that matches the current move sequence.
struct OpeningMatch: Sendable {
    let opening: Opening
    let line: OpeningLine?         // Specific line within the opening (nil = still in trunk)
    let variationName: String?     // Named variation (e.g., "Giuoco Piano")
    let matchDepth: Int            // How many plies matched
    let nextBookMoves: [OpeningMove] // Available continuations from this position
    let isMainLine: Bool           // Whether we're on the main line
}

/// Real-time opening detection service.
/// Maintains state across moves for efficient incremental detection.
final class OpeningDetector: Sendable {
    private let database: OpeningDatabase

    init(database: OpeningDatabase = .shared) {
        self.database = database
    }

    /// Detect which opening(s) match a sequence of UCI moves.
    /// Call this after each move in a game.
    func detect(moves: [String]) -> OpeningDetection {
        guard !moves.isEmpty else {
            return OpeningDetection(matches: [], leftBookAtPly: nil)
        }

        let allOpenings = database.openings(forColor: .white) + database.openings(forColor: .black)
        var matches: [OpeningMatch] = []

        for opening in allOpenings {
            // Check if this opening matches the move sequence
            let continuations = opening.continuations(afterMoves: moves)
            let matchingLines = opening.matchingLines(forMoveSequence: moves)

            // We need at least the first few moves to match
            // Walk backwards to find the deepest match
            var deepestMatch = 0
            for i in 1...moves.count {
                let prefix = Array(moves.prefix(i))
                let conts = opening.continuations(afterMoves: Array(prefix.dropLast()))
                if conts.contains(where: { $0.uci == prefix.last }) {
                    deepestMatch = i
                } else {
                    break
                }
            }

            guard deepestMatch > 0 else { continue }

            // Find the best matching line
            let bestLine = matchingLines
                .sorted { $0.moves.count > $1.moves.count }
                .first

            // Check if we're on the main line
            let isMainLine = checkMainLine(opening: opening, moves: Array(moves.prefix(deepestMatch)))

            // Get variation name from tree
            let variationName = findVariationName(opening: opening, moves: Array(moves.prefix(deepestMatch)))

            let match = OpeningMatch(
                opening: opening,
                line: bestLine,
                variationName: variationName ?? bestLine?.name,
                matchDepth: deepestMatch,
                nextBookMoves: continuations,
                isMainLine: isMainLine
            )
            matches.append(match)
        }

        // Sort by match depth (most specific first), then by whether we're still in book
        matches.sort { a, b in
            if a.matchDepth != b.matchDepth { return a.matchDepth > b.matchDepth }
            if a.nextBookMoves.isEmpty != b.nextBookMoves.isEmpty { return !a.nextBookMoves.isEmpty }
            return a.isMainLine && !b.isMainLine
        }

        // Determine if we've left book
        let leftBookAtPly: Int?
        if matches.isEmpty {
            // Find where we diverged by checking shorter prefixes
            leftBookAtPly = findDivergencePly(moves: moves, allOpenings: allOpenings)
        } else if matches.first!.matchDepth < moves.count {
            // Partial match — we're off-book after the match depth
            leftBookAtPly = matches.first!.matchDepth
        } else {
            leftBookAtPly = nil
        }

        return OpeningDetection(matches: matches, leftBookAtPly: leftBookAtPly)
    }

    /// Detect the specific book move the user should have played when they deviate.
    func bookMoveAt(moves: [String]) -> [OpeningMove] {
        let prefix = Array(moves.dropLast())
        let allOpenings = database.openings(forColor: .white) + database.openings(forColor: .black)

        var bookMoves: [OpeningMove] = []
        for opening in allOpenings {
            let continuations = opening.continuations(afterMoves: prefix)
            bookMoves.append(contentsOf: continuations)
        }

        // Deduplicate by UCI
        var seen = Set<String>()
        return bookMoves.filter { seen.insert($0.uci).inserted }
    }

    // MARK: - Private

    private func checkMainLine(opening: Opening, moves: [String]) -> Bool {
        guard let tree = opening.tree else { return true }
        var node = tree
        for move in moves {
            guard let child = node.children.first(where: { $0.move?.uci == move }) else {
                return false
            }
            if !child.isMainLine { return false }
            node = child
        }
        return true
    }

    private func findVariationName(opening: Opening, moves: [String]) -> String? {
        guard let tree = opening.tree else { return nil }
        var node = tree
        var lastVariation: String?
        for move in moves {
            guard let child = node.children.first(where: { $0.move?.uci == move }) else {
                break
            }
            if let name = child.variationName {
                lastVariation = name
            }
            node = child
        }
        return lastVariation
    }

    private func findDivergencePly(moves: [String], allOpenings: [Opening]) -> Int? {
        // Walk backwards to find where we were last in book
        for i in stride(from: moves.count - 1, through: 1, by: -1) {
            let prefix = Array(moves.prefix(i))
            for opening in allOpenings {
                let conts = opening.continuations(afterMoves: prefix)
                if !conts.isEmpty {
                    return i // We were in book up to this ply
                }
            }
        }
        return 0 // Never in book (unusual opening)
    }
}
