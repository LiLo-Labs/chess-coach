import Foundation

struct SessionResult {
    let accuracy: Double
    let isPersonalBest: Bool
    let dueReviewCount: Int
    let timeSpent: TimeInterval?
    let movesPerMinute: Double?

    // Plan Execution Score data
    let averagePES: Double?
    let pesCategory: ScoreCategory?
    let moveScores: [PlanExecutionScore]?

    // Familiarity milestone
    var familiarityMilestone: FamiliarityMilestone? = nil
    var familiarityPercentage: Int = 0
    var coachSessionMessage: String? = nil
}
