import Foundation

/// Dual-perspective opening detection that identifies what each side is playing independently.
/// Wraps the existing `OpeningDetector` and augments with ECO database lookups.
final class HolisticDetector: Sendable {
    private let openingDetector: OpeningDetector
    private let database: OpeningDatabase

    init(database: OpeningDatabase = .shared) {
        self.database = database
        self.openingDetector = OpeningDetector(database: database)
    }

    /// Detect openings from a dual-perspective: what White is playing and what Black is playing.
    func detect(moves: [String]) -> HolisticDetection {
        guard !moves.isEmpty else { return .none }

        // 1. Run existing tree-based detection
        let raw = openingDetector.detect(moves: moves)

        // 2. Replay moves to get current FEN, then query ECO index
        let gs = GameState()
        for move in moves {
            guard gs.makeMoveUCI(move) else {
                return HolisticDetection(
                    whiteFramework: .empty,
                    blackFramework: .empty,
                    intersectingOpenings: raw.matches,
                    branchAlternatives: [],
                    raw: raw
                )
            }
        }
        let ecoEntries = database.lookupECO(gs.fen)

        // 3. Merge tree matches with ECO matches, deduplicating by name
        var allMatches = raw.matches
        var seenNames = Set(allMatches.map { $0.variationName ?? $0.opening.name })

        for eco in ecoEntries {
            let name = eco.name
            guard !seenNames.contains(name) else { continue }
            seenNames.insert(name)

            // Create a synthetic OpeningMatch for ECO entries
            let syntheticOpening = Opening(
                id: "eco-\(eco.eco)-\(eco.depth)",
                name: eco.name,
                description: "",
                color: eco.color,
                difficulty: 0,
                tags: [eco.eco],
                mainLine: [],
                tree: nil,
                lines: nil,
                plan: nil,
                opponentResponses: nil
            )
            let match = OpeningMatch(
                opening: syntheticOpening,
                line: nil,
                variationName: nil,
                matchDepth: eco.depth,
                nextBookMoves: [],
                isMainLine: false
            )
            allMatches.append(match)
        }

        // Sort by depth (most specific first)
        allMatches.sort { $0.matchDepth > $1.matchDepth }

        // 4. Partition by color: White openings vs Black openings
        var whiteMatches: [OpeningMatch] = []
        var blackMatches: [OpeningMatch] = []

        for match in allMatches {
            switch match.opening.color {
            case .white:
                whiteMatches.append(match)
            case .black:
                blackMatches.append(match)
            }
        }

        let whiteFramework = FrameworkDetection(
            primary: whiteMatches.first,
            alternatives: Array(whiteMatches.dropFirst())
        )
        let blackFramework = FrameworkDetection(
            primary: blackMatches.first,
            alternatives: Array(blackMatches.dropFirst())
        )

        // 5. Compute branch points
        let branchPoints = computeBranchPoints(moves: moves, allMatches: allMatches)

        return HolisticDetection(
            whiteFramework: whiteFramework,
            blackFramework: blackFramework,
            intersectingOpenings: allMatches,
            branchAlternatives: branchPoints,
            raw: raw
        )
    }

    // MARK: - Private

    /// Find plies where multiple openings diverge — i.e., a different move would enter a different opening.
    private func computeBranchPoints(moves: [String], allMatches: [OpeningMatch]) -> [BranchPoint] {
        var branchPoints: [BranchPoint] = []

        // Check each ply to see if there were alternatives
        for ply in 1...moves.count {
            let prefix = Array(moves.prefix(ply - 1))

            // Get all openings that were still in book at the parent position
            var candidatesAtPly: [OpeningMatch] = []
            for match in allMatches {
                // Only include matches that were still valid at this depth
                guard match.matchDepth >= ply else { continue }
                candidatesAtPly.append(match)
            }

            // If multiple openings are still valid but one is about to diverge, record it
            if candidatesAtPly.count > 1 {
                // Check if any openings would diverge with a different move at this ply
                let currentMove = moves[ply - 1]
                let allOpenings = database.openings(forColor: .white) + database.openings(forColor: .black)

                var alternativesAtPly: [OpeningMatch] = []
                for opening in allOpenings {
                    let continuations = opening.continuations(afterMoves: prefix)
                    let hasAlternative = continuations.contains(where: { $0.uci != currentMove })
                    if hasAlternative {
                        // This opening has a different continuation here
                        let altMatch = OpeningMatch(
                            opening: opening,
                            line: nil,
                            variationName: nil,
                            matchDepth: ply - 1,
                            nextBookMoves: continuations.filter { $0.uci != currentMove },
                            isMainLine: false
                        )
                        alternativesAtPly.append(altMatch)
                    }
                }

                if !alternativesAtPly.isEmpty {
                    branchPoints.append(BranchPoint(ply: ply, alternatives: alternativesAtPly))
                }
            }
        }

        return branchPoints
    }
}
