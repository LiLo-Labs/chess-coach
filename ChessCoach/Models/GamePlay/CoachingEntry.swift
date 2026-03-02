import Foundation

/// Unified per-ply coaching feed entry, replacing both TrainerCoachingEntry and CoachingFeedEntry.
/// Per-ply is the atomic unit; move-pair grouping is done at the view layer.
@Observable
@MainActor
final class CoachingEntry: Identifiable {
    nonisolated(unsafe) private static var counter = 0

    let id: Int
    let ply: Int                // 0-based ply index
    let moveNumber: Int         // 1-based full move number
    let moveSAN: String
    let moveUCI: String
    let isPlayerMove: Bool
    var coaching: String
    let category: MoveCategory
    let soundness: Int?
    let scoreCategory: ScoreCategory?
    let openingName: String?
    let isInBook: Bool
    var fen: String?            // FEN after move
    var fenBeforeMove: String?

    // Deviation (session modes)
    var isDeviation: Bool
    var expectedSAN: String?
    var expectedUCI: String?
    var playedUCI: String?

    // On-demand LLM explanation
    var explanation: String?
    var isExplaining: Bool = false

    var isWhiteMove: Bool { ply % 2 == 0 }

    var moveLabel: String {
        isWhiteMove ? "\(moveNumber). \(moveSAN)" : "\(moveNumber)... \(moveSAN)"
    }

    init(
        ply: Int,
        moveNumber: Int,
        moveSAN: String,
        moveUCI: String = "",
        isPlayerMove: Bool,
        coaching: String,
        category: MoveCategory = .goodMove,
        soundness: Int? = nil,
        scoreCategory: ScoreCategory? = nil,
        openingName: String? = nil,
        isInBook: Bool = false,
        fen: String? = nil,
        fenBeforeMove: String? = nil,
        isDeviation: Bool = false,
        expectedSAN: String? = nil,
        expectedUCI: String? = nil,
        playedUCI: String? = nil
    ) {
        CoachingEntry.counter += 1
        self.id = CoachingEntry.counter
        self.ply = ply
        self.moveNumber = moveNumber
        self.moveSAN = moveSAN
        self.moveUCI = moveUCI
        self.isPlayerMove = isPlayerMove
        self.coaching = coaching
        self.category = category
        self.soundness = soundness
        self.scoreCategory = scoreCategory
        self.openingName = openingName
        self.isInBook = isInBook
        self.fen = fen
        self.fenBeforeMove = fenBeforeMove
        self.isDeviation = isDeviation
        self.expectedSAN = expectedSAN
        self.expectedUCI = expectedUCI
        self.playedUCI = playedUCI
    }
}
