import Foundation

/// A single entry in the trainer's per-move coaching feed.
/// Class (not struct) so explanation state can be mutated in-place.
@Observable
@MainActor
final class TrainerCoachingEntry: Identifiable {
    let id = UUID()
    let ply: Int
    let moveNumber: Int        // Full move number (1-based)
    let moveSAN: String
    let isPlayerMove: Bool
    let coaching: String
    let category: MoveCategory
    let soundness: Int?        // 0-100, nil if eval not available
    let scoreCategory: ScoreCategory?
    let openingName: String?
    let isInBook: Bool
    let fen: String?          // Position FEN after this move (for replay)

    // LLM explanation (requested on-demand via sparkle button)
    var explanation: String?
    var isExplaining: Bool = false

    /// Whether this move was made by White (ply is odd: 1, 3, 5...)
    var isWhiteMove: Bool { ply % 2 == 1 }

    var moveLabel: String {
        if isWhiteMove {
            return "\(moveNumber). \(moveSAN)"
        } else {
            return "\(moveNumber)... \(moveSAN)"
        }
    }

    init(ply: Int, moveNumber: Int, moveSAN: String, isPlayerMove: Bool, coaching: String, category: MoveCategory, soundness: Int?, scoreCategory: ScoreCategory?, openingName: String?, isInBook: Bool, fen: String?) {
        self.ply = ply
        self.moveNumber = moveNumber
        self.moveSAN = moveSAN
        self.isPlayerMove = isPlayerMove
        self.coaching = coaching
        self.category = category
        self.soundness = soundness
        self.scoreCategory = scoreCategory
        self.openingName = openingName
        self.isInBook = isInBook
        self.fen = fen
    }
}
