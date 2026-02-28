import Foundation

/// A single entry in the trainer's per-move coaching feed.
struct TrainerCoachingEntry: Identifiable {
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

    /// Whether this move was made by White (ply is odd: 1, 3, 5...)
    var isWhiteMove: Bool { ply % 2 == 1 }

    var moveLabel: String {
        if isWhiteMove {
            return "\(moveNumber). \(moveSAN)"
        } else {
            return "\(moveNumber)... \(moveSAN)"
        }
    }
}
