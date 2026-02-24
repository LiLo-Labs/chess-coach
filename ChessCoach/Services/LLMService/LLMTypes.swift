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
    let openingDescription: String
    let expectedMoveExplanation: String?
    let expectedMoveSAN: String?
    let userELO: Int
    let phase: LearningPhase
    let moveCategory: MoveCategory
    let moveHistory: String
    let isUserMove: Bool
    let studentColor: String?
    let plyNumber: Int
    let mainLineSoFar: String
}

enum LLMProvider: Sendable {
    case onDevice
    case ollama
    case claude
}

struct BatchedCoachingContext: Sendable {
    let userContext: CoachingContext
    let opponentContext: CoachingContext
}

struct BatchedCoachingResult: Sendable {
    let userCoaching: String
    let opponentCoaching: String
}

/// Context for AI chat during line study (Stage 1 Pro feature).
struct ChatContext: Sendable {
    let fen: String
    let openingName: String
    let lineName: String
    let moveHistory: [String]
    let currentPly: Int
}
