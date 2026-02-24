import Testing
import Foundation
@testable import ChessCoach

@Suite(.serialized)
struct SessionResultTests {
    @Test func sessionResultCanBeConstructed() {
        let result = SessionResult(
            accuracy: 0.85,
            isPersonalBest: true,
            phasePromotion: SessionResult.PhasePromotion(from: .learningMainLine, to: .naturalDeviations),
            linePhasePromotion: nil,
            newlyUnlockedLines: ["Evans Gambit"],
            dueReviewCount: 3,
            compositeScore: 62.5,
            nextPhaseThreshold: 70,
            gamesUntilMinimum: 2
        )
        #expect(result.accuracy == 0.85)
        #expect(result.isPersonalBest == true)
        #expect(result.phasePromotion?.from == .learningMainLine)
        #expect(result.phasePromotion?.to == .naturalDeviations)
        #expect(result.linePhasePromotion == nil)
        #expect(result.newlyUnlockedLines == ["Evans Gambit"])
        #expect(result.dueReviewCount == 3)
        #expect(result.compositeScore == 62.5)
        #expect(result.nextPhaseThreshold == 70)
        #expect(result.gamesUntilMinimum == 2)
    }

    @Test func sessionResultWithNoPromotion() {
        let result = SessionResult(
            accuracy: 0.6,
            isPersonalBest: false,
            phasePromotion: nil,
            linePhasePromotion: nil,
            newlyUnlockedLines: [],
            dueReviewCount: 0,
            compositeScore: 45.0,
            nextPhaseThreshold: 60,
            gamesUntilMinimum: 1
        )
        #expect(result.phasePromotion == nil)
        #expect(!result.isPersonalBest)
        #expect(result.newlyUnlockedLines.isEmpty)
    }

    @Test func sessionResultAtFreePlay() {
        let result = SessionResult(
            accuracy: 0.95,
            isPersonalBest: true,
            phasePromotion: nil,
            linePhasePromotion: nil,
            newlyUnlockedLines: [],
            dueReviewCount: 0,
            compositeScore: 80.0,
            nextPhaseThreshold: nil,
            gamesUntilMinimum: nil
        )
        #expect(result.nextPhaseThreshold == nil)
        #expect(result.gamesUntilMinimum == nil)
    }
}

@Suite(.serialized)
struct RecordGameReturnTests {
    @Test func recordGameReturnsNilWhenNoPromotion() {
        var progress = OpeningProgress(openingID: "test")
        let oldPhase = progress.recordGame(accuracy: 0.5, won: false)
        #expect(oldPhase == nil)
        #expect(progress.currentPhase == .learningMainLine)
    }

    @Test func recordGameReturnsPreviousPhaseOnPromotion() {
        var progress = OpeningProgress(openingID: "test")
        var promotionResults: [LearningPhase] = []
        for _ in 0..<5 {
            if let oldPhase = progress.recordGame(accuracy: 0.95, won: true) {
                promotionResults.append(oldPhase)
            }
        }
        // Should have promoted at least once
        #expect(!promotionResults.isEmpty)
        // First promotion should be from learningMainLine
        #expect(promotionResults.first == .learningMainLine)
    }

    @Test func bestAccuracyTracked() {
        var progress = OpeningProgress(openingID: "test")
        progress.recordGame(accuracy: 0.7, won: true)
        progress.recordGame(accuracy: 0.9, won: true)
        progress.recordGame(accuracy: 0.8, won: true)
        #expect(progress.bestAccuracy == 0.9)
    }

    @Test func lineRecordGameReturnsPreviousPhaseOnPromotion() {
        var lp = LineProgress(lineID: "test/main", openingID: "test")
        var promotionResults: [LearningPhase] = []
        for _ in 0..<5 {
            if let oldPhase = lp.recordGame(accuracy: 0.95, won: true) {
                promotionResults.append(oldPhase)
            }
        }
        #expect(!promotionResults.isEmpty)
        #expect(promotionResults.first == .learningMainLine)
    }

    @Test func lineBestAccuracyTracked() {
        var lp = LineProgress(lineID: "test/main", openingID: "test")
        lp.recordGame(accuracy: 0.6, won: false)
        lp.recordGame(accuracy: 0.85, won: true)
        lp.recordGame(accuracy: 0.75, won: true)
        #expect(lp.bestAccuracy == 0.85)
    }
}
