import Foundation

struct SessionResult {
    let accuracy: Double
    let isPersonalBest: Bool
    let phasePromotion: PhasePromotion?
    let linePhasePromotion: PhasePromotion?
    let newlyUnlockedLines: [String]
    let dueReviewCount: Int
    let compositeScore: Double
    let nextPhaseThreshold: Double?
    let gamesUntilMinimum: Int?
    /// Total wall-clock seconds the session lasted (nil if not tracked).
    let timeSpent: TimeInterval?
    /// User moves played per minute (nil if time not tracked or zero).
    let movesPerMinute: Double?

    struct PhasePromotion {
        let from: LearningPhase
        let to: LearningPhase
    }
}
