import Foundation

struct OpeningProgress: Codable, Sendable {
    let openingID: String
    var gamesPlayed: Int = 0
    var gamesWon: Int = 0
    var currentPhase: LearningPhase = .learningMainLine
    var accuracyHistory: [Double] = []
    var lastPlayed: Date?
    var bestAccuracy: Double = 0

    // Per-line progress (v2 data model)
    var lineProgress: [String: LineProgress] = [:]

    // Training pipeline Stage 4 tracking
    var practiceSessionCount: Int = 0         // Stage 4 completion count
    var practiceAccuracy: Double = 0          // Stage 4 aggregate accuracy

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

    // MARK: - Per-line operations

    /// Record a game for a specific line.
    /// Returns a tuple of (aggregateOldPhase, lineOldPhase) — each is non-nil only if a promotion occurred.
    @discardableResult
    mutating func recordLineGame(lineID: String, accuracy: Double, won: Bool) -> (aggregateOldPhase: LearningPhase?, lineOldPhase: LearningPhase?) {
        // Update line-specific progress
        if lineProgress[lineID] == nil {
            lineProgress[lineID] = LineProgress(lineID: lineID, openingID: openingID)
        }
        let lineOldPhase = lineProgress[lineID]?.recordGame(accuracy: accuracy, won: won)

        // Also update aggregate
        let aggregateOldPhase = recordGame(accuracy: accuracy, won: won)
        return (aggregateOldPhase, lineOldPhase)
    }

    /// Get progress for a specific line, creating default if needed.
    func progress(forLine lineID: String) -> LineProgress {
        lineProgress[lineID] ?? LineProgress(lineID: lineID, openingID: openingID)
    }

    /// Number of lines that have reached at least naturalDeviations phase.
    var masteredLineCount: Int {
        lineProgress.values.filter { $0.currentPhase != .learningMainLine }.count
    }

    /// Number of lines that have been studied (Stage 1 completed).
    var studiedLineCount: Int {
        lineProgress.values.filter(\.hasStudied).count
    }

    /// Number of lines that have at least 1 guided completion (Stage 2).
    var guidedLineCount: Int {
        lineProgress.values.filter { $0.guidedCompletions > 0 }.count
    }

    /// Number of lines that have at least 1 unguided completion (Stage 3).
    var unguidedLineCount: Int {
        lineProgress.values.filter { $0.unguidedCompletions > 0 }.count
    }

    /// Whether Practice Opening mode is unlocked (2+ lines completed in unguided mode).
    var isPracticeUnlocked: Bool {
        unguidedLineCount >= 2
    }

    /// Total number of lines tracked.
    var totalLineCount: Int {
        lineProgress.count
    }

    /// Reset progress for a single line back to initial state.
    mutating func resetLineProgress(lineID: String) {
        lineProgress[lineID] = LineProgress(lineID: lineID, openingID: openingID)
    }

    /// Reset all progress for this opening.
    mutating func resetAllProgress() {
        lineProgress = [:]
        gamesPlayed = 0
        gamesWon = 0
        accuracyHistory = []
        currentPhase = .learningMainLine
        practiceSessionCount = 0
        practiceAccuracy = 0
        bestAccuracy = 0
    }

    /// Check if a line should be unlocked based on its parent's progress.
    func isLineUnlocked(_ lineID: String, parentLineID: String?) -> Bool {
        guard let parentID = parentLineID else { return true } // No parent = always unlocked
        let parentProg = progress(forLine: parentID)
        let criteria = UnlockCriteria.standard(parentLineID: parentID)
        return criteria.isMet(parentProgress: parentProg)
    }
}
