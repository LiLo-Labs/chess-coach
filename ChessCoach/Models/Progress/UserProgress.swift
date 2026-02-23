import Foundation

struct OpeningProgress: Codable, Sendable {
    let openingID: String
    var gamesPlayed: Int = 0
    var gamesWon: Int = 0
    var currentPhase: LearningPhase = .learningMainLine
    var accuracyHistory: [Double] = []
    var lastPlayed: Date?

    var accuracy: Double {
        guard !accuracyHistory.isEmpty else { return 0 }
        return accuracyHistory.suffix(10).reduce(0, +) / Double(min(accuracyHistory.count, 10))
    }

    var winRate: Double {
        guard gamesPlayed > 0 else { return 0 }
        return Double(gamesWon) / Double(gamesPlayed)
    }

    /// Composite score for phase promotion (0-100)
    var compositeScore: Double {
        let accuracyScore = accuracy * 40
        let winRateScore = winRate * 30
        let gamesScore = min(Double(gamesPlayed) / 10.0, 1.0) * 30
        return accuracyScore + winRateScore + gamesScore
    }

    /// Check if ready to advance to next phase
    var shouldPromote: Bool {
        switch currentPhase {
        case .learningMainLine:
            return compositeScore >= 60 && gamesPlayed >= 3
        case .naturalDeviations:
            return compositeScore >= 70 && gamesPlayed >= 5
        case .widerVariations:
            return compositeScore >= 75 && gamesPlayed >= 8
        case .freePlay:
            return false // Already at max
        }
    }

    mutating func recordGame(accuracy: Double, won: Bool) {
        gamesPlayed += 1
        if won { gamesWon += 1 }
        accuracyHistory.append(accuracy)
        lastPlayed = Date()

        if shouldPromote {
            promotePhase()
        }
    }

    mutating func promotePhase() {
        switch currentPhase {
        case .learningMainLine:
            currentPhase = .naturalDeviations
        case .naturalDeviations:
            currentPhase = .widerVariations
        case .widerVariations:
            currentPhase = .freePlay
        case .freePlay:
            break
        }
    }
}
