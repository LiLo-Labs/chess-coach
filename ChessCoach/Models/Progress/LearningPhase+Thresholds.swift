import Foundation

extension LearningPhase {
    /// Composite score needed for promotion from this phase.
    var promotionThreshold: Double? {
        switch self {
        case .learningMainLine: return 60
        case .naturalDeviations: return 70
        case .widerVariations: return 75
        case .freePlay: return nil
        }
    }

    /// Minimum games required for promotion from this phase.
    var minimumGames: Int? {
        switch self {
        case .learningMainLine: return 3
        case .naturalDeviations: return 5
        case .widerVariations: return 8
        case .freePlay: return nil
        }
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
}
