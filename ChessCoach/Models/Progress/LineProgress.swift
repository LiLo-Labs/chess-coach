import Foundation

/// Tracks mastery progress for a single opening variation line.
struct LineProgress: Codable, Sendable {
    let lineID: String
    let openingID: String
    var currentPhase: LearningPhase = .learningMainLine
    var gamesPlayed: Int = 0
    var gamesWon: Int = 0
    var accuracyHistory: [Double] = []
    var lastPlayed: Date?
    var isUnlocked: Bool = true
    var bestAccuracy: Double = 0

    // Training pipeline stage tracking
    var hasStudied: Bool = false              // Stage 1 (LineStudyView) completed
    var guidedCompletions: Int = 0            // Stage 2 completion count
    var unguidedCompletions: Int = 0          // Stage 3 completion count
    var unguidedBestAccuracy: Double = 0      // Stage 3 best accuracy

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

    var shouldPromote: Bool {
        switch currentPhase {
        case .learningMainLine:
            return compositeScore >= 60 && gamesPlayed >= 3
        case .naturalDeviations:
            return compositeScore >= 70 && gamesPlayed >= 5
        case .widerVariations:
            return compositeScore >= 75 && gamesPlayed >= 8
        case .freePlay:
            return false
        }
    }

    /// Records a game and returns the old phase if a promotion occurred, nil otherwise.
    @discardableResult
    mutating func recordGame(accuracy: Double, won: Bool) -> LearningPhase? {
        let previousPhase = currentPhase
        bestAccuracy = max(bestAccuracy, accuracy)
        gamesPlayed += 1
        if won { gamesWon += 1 }
        accuracyHistory.append(accuracy)
        lastPlayed = Date()

        if shouldPromote {
            promotePhase()
        }
        return currentPhase != previousPhase ? previousPhase : nil
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

/// Criteria for unlocking a branch/variation line.
struct UnlockCriteria: Codable, Sendable {
    let requiredLineID: String      // parent line that must be mastered
    let requiredPhase: LearningPhase // minimum phase on parent line
    let minimumAccuracy: Double     // minimum accuracy on parent line (0-1)
    let minimumMaiaWinRate: Double  // minimum win rate vs Maia on parent line (0-1)

    /// Default unlock criteria: parent must reach naturalDeviations, 70% accuracy, 50% Maia win rate.
    static func standard(parentLineID: String) -> UnlockCriteria {
        UnlockCriteria(
            requiredLineID: parentLineID,
            requiredPhase: .naturalDeviations,
            minimumAccuracy: 0.70,
            minimumMaiaWinRate: 0.50
        )
    }

    /// Check if the criteria are met given parent line progress.
    func isMet(parentProgress: LineProgress) -> Bool {
        let phaseOrder: [LearningPhase] = [.learningMainLine, .naturalDeviations, .widerVariations, .freePlay]
        let requiredIdx = phaseOrder.firstIndex(of: requiredPhase) ?? 0
        let currentIdx = phaseOrder.firstIndex(of: parentProgress.currentPhase) ?? 0

        return currentIdx >= requiredIdx
            && parentProgress.accuracy >= minimumAccuracy
            && parentProgress.winRate >= minimumMaiaWinRate
    }
}
