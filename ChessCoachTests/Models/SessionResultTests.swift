import Testing
import Foundation
@testable import ChessCoach

@Suite(.serialized)
struct SessionResultTests {
    @Test func sessionResultCanBeConstructed() {
        let result = SessionResult(
            accuracy: 0.85,
            isPersonalBest: true,
            dueReviewCount: 3,
            timeSpent: nil,
            movesPerMinute: nil,
            averagePES: nil,
            pesCategory: nil,
            moveScores: nil,
            familiarityMilestone: FamiliarityMilestone(
                previousProgress: 0.25,
                newProgress: 0.35,
                crossedThreshold: 0.3
            ),
            familiarityPercentage: 35
        )
        #expect(result.accuracy == 0.85)
        #expect(result.isPersonalBest == true)
        #expect(result.dueReviewCount == 3)
        #expect(result.familiarityMilestone?.crossedThreshold == 0.3)
        #expect(result.familiarityPercentage == 35)
    }

    @Test func sessionResultWithNoMilestone() {
        let result = SessionResult(
            accuracy: 0.6,
            isPersonalBest: false,
            dueReviewCount: 0,
            timeSpent: nil,
            movesPerMinute: nil,
            averagePES: nil,
            pesCategory: nil,
            moveScores: nil,
            familiarityPercentage: 20
        )
        #expect(result.familiarityMilestone == nil)
        #expect(!result.isPersonalBest)
        #expect(result.familiarityPercentage == 20)
    }
}

@Suite(.serialized)
struct FamiliarityMilestoneTests {
    @Test func detectCrossing30Percent() {
        let milestone = FamiliarityMilestone.detect(from: 0.25, to: 0.35)
        #expect(milestone != nil)
        #expect(milestone?.crossedThreshold == 0.3)
        #expect(milestone?.thresholdPercentage == 30)
        #expect(milestone?.tierReached == .practicing)
    }

    @Test func detectCrossing70Percent() {
        let milestone = FamiliarityMilestone.detect(from: 0.65, to: 0.75)
        #expect(milestone != nil)
        #expect(milestone?.crossedThreshold == 0.7)
        #expect(milestone?.tierReached == .familiar)
    }

    @Test func detectCrossing100Percent() {
        let milestone = FamiliarityMilestone.detect(from: 0.95, to: 1.0)
        #expect(milestone != nil)
        #expect(milestone?.crossedThreshold == 1.0)
    }

    @Test func noMilestoneWithinSameTier() {
        let milestone = FamiliarityMilestone.detect(from: 0.1, to: 0.2)
        #expect(milestone == nil)
    }

    @Test func noMilestoneWhenDecreasing() {
        let milestone = FamiliarityMilestone.detect(from: 0.8, to: 0.6)
        #expect(milestone == nil)
    }
}

@Suite(.serialized)
struct OpeningFamiliarityTests {
    @Test func emptyFamiliarityIsZero() {
        let fam = OpeningFamiliarity.empty(openingID: "test")
        #expect(fam.progress == 0)
        #expect(fam.percentage == 0)
        #expect(fam.tier == .learning)
        #expect(fam.suggestion == .learnMore)
    }

    @Test func progressCountsMasteredPositions() {
        var mastered = PositionMastery(openingID: "test", fen: "pos1", ply: 1)
        mastered.repetitions = 4
        mastered.totalAttempts = 10
        mastered.correctAttempts = 9

        let notMastered = PositionMastery(openingID: "test", fen: "pos2", ply: 3)

        let fam = OpeningFamiliarity(openingID: "test", positions: [mastered, notMastered])
        #expect(fam.progress == 0.5)
        #expect(fam.percentage == 50)
        #expect(fam.tier == .practicing)
    }

    @Test func tierThresholds() {
        #expect(FamiliarityTier.from(progress: 0.0) == .learning)
        #expect(FamiliarityTier.from(progress: 0.29) == .learning)
        #expect(FamiliarityTier.from(progress: 0.3) == .practicing)
        #expect(FamiliarityTier.from(progress: 0.69) == .practicing)
        #expect(FamiliarityTier.from(progress: 0.7) == .familiar)
        #expect(FamiliarityTier.from(progress: 1.0) == .familiar)
    }
}
