import Foundation

/// Result of a trainer game.
struct TrainerGameResult: Codable, Sendable, Identifiable {
    let id: UUID
    let date: Date
    let playerColor: String   // "white" or "black"
    let botELO: Int
    let botName: String
    let engineMode: String    // "humanLike" or "engine"
    let outcome: Outcome
    let moveCount: Int

    enum Outcome: String, Codable, Sendable {
        case win
        case loss
        case draw
        case resigned
    }

    init(playerColor: String, botELO: Int, botName: String, engineMode: TrainerEngineMode, outcome: Outcome, moveCount: Int) {
        self.id = UUID()
        self.date = Date()
        self.playerColor = playerColor
        self.botELO = botELO
        self.botName = botName
        self.engineMode = engineMode.rawValue
        self.outcome = outcome
        self.moveCount = moveCount
    }
}

/// Trainer stats tracked across games, separate for each engine mode.
struct TrainerStats: Codable, Sendable {
    var wins: Int = 0
    var losses: Int = 0
    var draws: Int = 0
    var gamesPlayed: Int { wins + losses + draws }
    var winRate: Double { gamesPlayed > 0 ? Double(wins) / Double(gamesPlayed) : 0 }
}
