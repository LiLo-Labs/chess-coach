import Foundation

/// A curated Lichess puzzle used for adaptive ELO assessment.
/// Lichess puzzles are CC0 licensed.
struct AssessmentPuzzle: Codable, Identifiable, Sendable {
    let id: String
    let fen: String           // puzzle position (AFTER opponent's setup move)
    let setupMoveUCI: String  // opponent's move that created the tactic (metadata only)
    let solutionUCI: String   // the correct response
    let solutionSAN: String
    let themes: [String]
    let rating: Int           // Lichess Glicko rating
    let explanation: String?
}
