import Foundation
import ChessKit

/// Undo/redo snapshot for GamePlayViewModel, combining PlySnapshot functionality.
struct GamePlaySnapshot {
    let ply: Int
    let fen: String
    let moveHistory: [(from: String, to: String, promotion: PieceKind?)]
    let bookStatus: BookStatus
    let evalScore: Int
    let lastMovePES: PlanExecutionScore?
    let stats: SessionStats
    let feedEntries: [CoachingEntry]
    let arrowFrom: String?
    let arrowTo: String?
    let hintSquare: String?
    let userCoachingText: String?
    let opponentCoachingText: String?

    // Trainer-specific
    let lastEvalScoreBefore: Int?
    let coachingFeedForTrainer: [CoachingEntry]?
}
