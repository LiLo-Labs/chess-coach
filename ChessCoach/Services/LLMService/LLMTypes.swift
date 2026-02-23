import Foundation

enum MoveCategory: String, Codable, Sendable {
    case goodMove
    case okayMove
    case mistake
    case opponentMove
    case deviation
}

enum LearningPhase: String, Codable, Sendable {
    case learningMainLine
    case naturalDeviations
    case widerVariations
    case freePlay
}

struct CoachingContext: Sendable {
    let fen: String
    let lastMove: String
    let scoreBefore: Int
    let scoreAfter: Int
    let openingName: String
    let userELO: Int
    let phase: LearningPhase
    let moveCategory: MoveCategory
}

enum LLMProvider: Sendable {
    case ollama
    case claude
}
