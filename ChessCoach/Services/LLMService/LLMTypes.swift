import Foundation

enum MoveCategory: String, Codable, Sendable {
    case goodMove
    case okayMove
    case mistake
    case opponentMove
    case deviation
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
    let familiarityPercent: Int
    let moveCategory: MoveCategory
    let moveHistory: String
    let isUserMove: Bool
    let studentColor: String?
    let plyNumber: Int
    let mainLineSoFar: String
    let matchedResponseName: String?
    let matchedResponseAdjustment: String?
    let coachPersonalityPrompt: String?
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
    /// Prior conversation turns (coaching + user Q&A) for continuity.
    let conversationHistory: [(role: String, text: String)]

    init(fen: String, openingName: String, lineName: String, moveHistory: [String], currentPly: Int, conversationHistory: [(role: String, text: String)] = []) {
        self.fen = fen
        self.openingName = openingName
        self.lineName = lineName
        self.moveHistory = moveHistory
        self.currentPly = currentPly
        self.conversationHistory = conversationHistory
    }
}
