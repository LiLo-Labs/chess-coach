import Foundation

/// A composite 0-100 score that answers: "How well did this move serve the opening's plan?"
struct PlanExecutionScore: Codable, Sendable {
    let total: Int              // 0-100 final score
    let soundness: Int          // 0-100 from Stockfish centipawn loss
    let alignment: Int          // 0-100 from LLM plan alignment
    let popularity: Int         // -3 to +5 from Polyglot book weights
    let reasoning: String       // LLM explanation (becomes coaching text)
    let category: ScoreCategory
    let rubric: AlignmentRubric?

    /// Computed from components: weighted blend of soundness and alignment + popularity.
    /// Soundness acts as a drag when low (bad moves) but doesn't hard-cap good opening moves
    /// that Stockfish slightly disagrees with at depth 12.
    static func compute(
        soundness: Int,
        alignment: Int,
        popularity: Int,
        reasoning: String,
        rubric: AlignmentRubric? = nil
    ) -> PlanExecutionScore {
        let adjusted = max(0, min(100, alignment + popularity))
        // Blend: 40% soundness, 60% alignment+popularity.
        // If soundness is very low (blunder), it still drags the score down hard.
        let blended = (soundness * 40 + adjusted * 60) / 100
        let total = max(0, min(100, blended))
        return PlanExecutionScore(
            total: total,
            soundness: soundness,
            alignment: alignment,
            popularity: popularity,
            reasoning: reasoning,
            category: ScoreCategory.from(score: total),
            rubric: rubric
        )
    }
}

enum ScoreCategory: String, Codable, Sendable {
    case masterful
    case strong
    case solid
    case developing
    case needsWork

    static func from(score: Int) -> ScoreCategory {
        switch score {
        case 90...100: return .masterful
        case 75...89: return .strong
        case 60...74: return .solid
        case 40...59: return .developing
        default: return .needsWork
        }
    }

    var displayName: String {
        switch self {
        case .masterful: return "Masterful"
        case .strong: return "Strong"
        case .solid: return "Solid"
        case .developing: return "Developing"
        case .needsWork: return "Needs Work"
        }
    }

    var colorName: String {
        switch self {
        case .masterful: return "gold"
        case .strong: return "green"
        case .solid: return "blue"
        case .developing: return "yellow"
        case .needsWork: return "red"
        }
    }
}

/// Structured rubric from LLM plan alignment evaluation.
struct AlignmentRubric: Codable, Sendable {
    let development: Bool
    let pawnStructure: Bool
    let strategicGoal: Bool
    let kingSafety: String  // "positive", "negative", "neutral"
}
