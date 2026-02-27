import Foundation

extension LearningPhase {
    /// Composite score needed for promotion from this phase.
    var promotionThreshold: Double? {
        AppConfig.learning.threshold(for: self).promotionThreshold
    }

    /// Minimum games required for promotion from this phase.
    var minimumGames: Int? {
        AppConfig.learning.threshold(for: self).minimumGames
    }

    var nextPhase: LearningPhase? {
        switch self {
        case .learningMainLine: return .naturalDeviations
        case .naturalDeviations: return .widerVariations
        case .widerVariations: return .freePlay
        case .freePlay: return nil
        }
    }

    var displayName: String {
        switch self {
        case .learningMainLine: return "Learning"
        case .naturalDeviations: return "Deviations"
        case .widerVariations: return "Variations"
        case .freePlay: return "Free Play"
        }
    }

    var phaseDescription: String {
        switch self {
        case .learningMainLine: return "Learn the exact main line moves"
        case .naturalDeviations: return "Handle common opponent deviations"
        case .widerVariations: return "Master wider variations and transpositions"
        case .freePlay: return "Play freely with full opening knowledge"
        }
    }

    /// Map legacy phase to the new learning layer system.
    var correspondingLayer: LearningLayer {
        switch self {
        case .learningMainLine: return .understandPlan
        case .naturalDeviations: return .executePlan
        case .widerVariations: return .handleVariety
        case .freePlay: return .realConditions
        }
    }
}
