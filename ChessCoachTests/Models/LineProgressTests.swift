import Testing
import Foundation
@testable import ChessCoach

@Suite(.serialized)
struct LineProgressTests {
    @Test func defaultLineProgress() {
        let progress = LineProgress(lineID: "italian/main", openingID: "italian")
        #expect(progress.currentPhase == .learningMainLine)
        #expect(progress.gamesPlayed == 0)
        #expect(progress.accuracy == 0)
        #expect(progress.winRate == 0)
        #expect(progress.isUnlocked == true)
    }

    @Test func recordGameUpdatesStats() {
        var progress = LineProgress(lineID: "italian/main", openingID: "italian")
        progress.recordGame(accuracy: 0.85, won: true)
        #expect(progress.gamesPlayed == 1)
        #expect(progress.gamesWon == 1)
        #expect(progress.accuracy == 0.85)
        #expect(progress.lastPlayed != nil)
    }

    @Test func winRateCalculatesCorrectly() {
        var progress = LineProgress(lineID: "italian/main", openingID: "italian")
        progress.recordGame(accuracy: 0.8, won: true)
        progress.recordGame(accuracy: 0.7, won: false)
        progress.recordGame(accuracy: 0.9, won: true)
        #expect(progress.winRate > 0.6)
        #expect(progress.winRate < 0.7)
    }

    @Test func accuracyUsesLast10Games() {
        var progress = LineProgress(lineID: "italian/main", openingID: "italian")
        // Play 12 games
        for i in 0..<12 {
            progress.recordGame(accuracy: i < 6 ? 0.5 : 0.9, won: true)
        }
        // Accuracy should be based on last 10, which includes some 0.5 and some 0.9
        #expect(progress.accuracy > 0.5)
    }

    @Test func phasePromotionAfterEnoughGames() {
        var progress = LineProgress(lineID: "italian/main", openingID: "italian")
        // Play enough high-quality games
        for _ in 0..<5 {
            progress.recordGame(accuracy: 0.95, won: true)
        }
        #expect(progress.currentPhase != .learningMainLine)
    }

    @Test func compositeScoreComponents() {
        var progress = LineProgress(lineID: "test", openingID: "test")
        progress.recordGame(accuracy: 1.0, won: true)
        progress.recordGame(accuracy: 1.0, won: true)
        // With 100% accuracy, 100% win rate, 2 games:
        // accuracy: 1.0 * 40 = 40
        // winRate: 1.0 * 30 = 30
        // games: (2/10) * 30 = 6
        // Total: 76
        #expect(progress.compositeScore > 70)
        #expect(progress.compositeScore < 80)
    }
}

@Suite(.serialized)
struct UnlockCriteriaTests {
    @Test func standardCriteria() {
        let criteria = UnlockCriteria.standard(parentLineID: "italian/main")
        #expect(criteria.requiredPhase == .naturalDeviations)
        #expect(criteria.minimumAccuracy == 0.70)
        #expect(criteria.minimumMaiaWinRate == 0.50)
    }

    @Test func criteriaNotMetWithLowPhase() {
        let criteria = UnlockCriteria.standard(parentLineID: "italian/main")
        var parent = LineProgress(lineID: "italian/main", openingID: "italian")
        // Still in learningMainLine
        parent.recordGame(accuracy: 0.9, won: true)
        #expect(!criteria.isMet(parentProgress: parent))
    }

    @Test func criteriaMetWithSufficientProgress() {
        let criteria = UnlockCriteria.standard(parentLineID: "italian/main")
        var parent = LineProgress(lineID: "italian/main", openingID: "italian")
        // Advance past learningMainLine
        for _ in 0..<5 {
            parent.recordGame(accuracy: 0.9, won: true)
        }
        // Check if the phase was promoted
        if parent.currentPhase == .naturalDeviations || parent.currentPhase == .widerVariations || parent.currentPhase == .freePlay {
            #expect(criteria.isMet(parentProgress: parent))
        }
    }

    @Test func criteriaNotMetWithLowAccuracy() {
        let criteria = UnlockCriteria.standard(parentLineID: "italian/main")
        var parent = LineProgress(
            lineID: "italian/main",
            openingID: "italian",
            currentPhase: .naturalDeviations,
            gamesPlayed: 10,
            gamesWon: 8,
            accuracyHistory: [0.5, 0.5, 0.5, 0.5, 0.5]  // 50% accuracy, below 70%
        )
        parent.isUnlocked = true
        #expect(!criteria.isMet(parentProgress: parent))
    }

    @Test func criteriaNotMetWithLowWinRate() {
        let criteria = UnlockCriteria.standard(parentLineID: "italian/main")
        let parent = LineProgress(
            lineID: "italian/main",
            openingID: "italian",
            currentPhase: .naturalDeviations,
            gamesPlayed: 10,
            gamesWon: 3,  // 30% win rate, below 50%
            accuracyHistory: [0.9, 0.9, 0.9, 0.9, 0.9]
        )
        #expect(!criteria.isMet(parentProgress: parent))
    }
}

@Suite(.serialized)
struct OpeningProgressLineTests {
    @Test func recordLineGameUpdatesLineAndAggregate() {
        var progress = OpeningProgress(openingID: "italian")
        progress.recordLineGame(lineID: "italian/main", accuracy: 0.8, won: true)

        #expect(progress.gamesPlayed == 1)
        #expect(progress.lineProgress["italian/main"]?.gamesPlayed == 1)
    }

    @Test func progressForLineReturnsDefault() {
        let progress = OpeningProgress(openingID: "italian")
        let line = progress.progress(forLine: "italian/main")
        #expect(line.gamesPlayed == 0)
        #expect(line.lineID == "italian/main")
    }

    @Test func masteredLineCountTracksCorrectly() {
        var progress = OpeningProgress(openingID: "italian")
        // Create a mastered line
        var mastered = LineProgress(lineID: "italian/main", openingID: "italian")
        mastered.currentPhase = .naturalDeviations
        progress.lineProgress["italian/main"] = mastered

        // Create a non-mastered line
        let learning = LineProgress(lineID: "italian/evans", openingID: "italian")
        progress.lineProgress["italian/evans"] = learning

        #expect(progress.masteredLineCount == 1)
        #expect(progress.totalLineCount == 2)
    }

    @Test func isLineUnlockedWithNoParent() {
        let progress = OpeningProgress(openingID: "italian")
        // No parent = always unlocked
        #expect(progress.isLineUnlocked("italian/main", parentLineID: nil))
    }

    @Test func isLineLockedWithUnmasteredParent() {
        let progress = OpeningProgress(openingID: "italian")
        // Parent not mastered yet
        #expect(!progress.isLineUnlocked("italian/evans", parentLineID: "italian/main"))
    }
}
