import Foundation

/// An entry from the ECO TSV database, indexed by FEN.
struct ECOIndexEntry: Sendable {
    let eco: String                    // "B12"
    let name: String                   // "Caro-Kann: Advance"
    let pgn: String                    // Original PGN from TSV
    let depth: Int                     // Number of plies
    let color: Opening.PlayerColor     // Inferred from ECO range
}

/// Dual-perspective opening detection result.
/// Wraps the existing `OpeningDetection` and adds per-side framework info.
struct HolisticDetection: Sendable {
    /// What White is playing.
    let whiteFramework: FrameworkDetection
    /// What Black is playing.
    let blackFramework: FrameworkDetection
    /// All openings matching this position (tree + ECO).
    let intersectingOpenings: [OpeningMatch]
    /// Decision points where alternative openings diverge.
    let branchAlternatives: [BranchPoint]
    /// Original detection for backward compatibility.
    let raw: OpeningDetection

    static let none = HolisticDetection(
        whiteFramework: .empty,
        blackFramework: .empty,
        intersectingOpenings: [],
        branchAlternatives: [],
        raw: .none
    )

    /// Convenience: whether either side is still in book.
    var isInBook: Bool { whiteFramework.isInBook || blackFramework.isInBook }

    /// All book moves across all intersecting openings (for pre-move checking).
    var allNextBookMoves: [OpeningMove] {
        intersectingOpenings.flatMap(\.nextBookMoves)
    }
}

/// What one side (White or Black) is playing.
struct FrameworkDetection: Sendable {
    /// Best match for this side (deepest).
    let primary: OpeningMatch?
    /// Other openings this side could be playing.
    let alternatives: [OpeningMatch]
    /// Whether this side is still in a known book line.
    var isInBook: Bool { primary?.nextBookMoves.isEmpty == false }

    static let empty = FrameworkDetection(primary: nil, alternatives: [])
}

/// A ply where multiple openings diverge.
struct BranchPoint: Sendable {
    let ply: Int
    let alternatives: [OpeningMatch]
}
