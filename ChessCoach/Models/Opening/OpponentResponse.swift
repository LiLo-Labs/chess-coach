import Foundation

/// Catalogue of known opponent responses at a key decision point in an opening.
struct OpponentResponseCatalogue: Codable, Sendable {
    let afterMoves: [String]              // UCI moves leading to this decision point
    let responses: [OpponentResponse]     // possible opponent continuations
}

/// A single opponent response with context about what it means for the plan.
struct OpponentResponse: Codable, Sendable, Identifiable {
    let id: String                        // unique ID (typically UCI move string)
    let move: OpeningMove                 // the response move
    let name: String                      // "Giuoco Piano", "Two Knights Defense"
    let eco: String                       // ECO code
    let frequency: Double                 // 0.0-1.0, from Polyglot weights
    let description: String               // human-readable explanation
    let planAdjustment: String            // how the player's plan changes
}
