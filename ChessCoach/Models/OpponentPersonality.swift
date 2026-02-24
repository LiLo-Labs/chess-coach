import Foundation

/// Opponent personality based on ELO bracket (improvement 12).
struct OpponentPersonality {
    let name: String
    let description: String

    static func forELO(_ elo: Int) -> OpponentPersonality {
        switch elo {
        case ..<900:
            return OpponentPersonality(name: "Rookie Riley", description: "Makes frequent blunders, misses tactics")
        case 900..<1100:
            return OpponentPersonality(name: "Beginner Bailey", description: "Knows basic openings, occasionally blunders")
        case 1100..<1300:
            return OpponentPersonality(name: "Club Player Casey", description: "Solid fundamentals, some tactical awareness")
        case 1300..<1500:
            return OpponentPersonality(name: "Intermediate Izzy", description: "Understands strategy, plans ahead")
        case 1500..<1700:
            return OpponentPersonality(name: "Tournament Tanya", description: "Strong positional play, sharp tactics")
        case 1700..<1900:
            return OpponentPersonality(name: "Expert Evan", description: "Deep calculation, knows theory well")
        default:
            return OpponentPersonality(name: "Master Morgan", description: "Near-perfect play, exploits every weakness")
        }
    }
}
