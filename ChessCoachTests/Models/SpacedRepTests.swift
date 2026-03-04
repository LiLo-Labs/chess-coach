import Testing
@testable import ChessCoach

@Test func positionMasteryStartsWithDefaults() {
    let pm = PositionMastery(openingID: "italian", fen: "startpos", ply: 4)
    #expect(pm.interval == 1)
    #expect(pm.easeFactor == 2.5)
    #expect(pm.repetitions == 0)
    #expect(pm.isDue)
    #expect(pm.totalAttempts == 0)
    #expect(pm.correctAttempts == 0)
    #expect(!pm.isMastered)
}

@Test func positionMasteryPerfectResponseIncreasesInterval() {
    var pm = PositionMastery(openingID: "italian", fen: "startpos", ply: 4)
    pm.review(quality: 5)
    #expect(pm.repetitions == 1)
    #expect(pm.interval == 1) // First review: 1 day

    pm.review(quality: 5)
    #expect(pm.repetitions == 2)
    #expect(pm.interval == 6) // Second review: 6 days

    pm.review(quality: 5)
    #expect(pm.repetitions == 3)
    #expect(pm.interval > 6) // Should increase
}

@Test func positionMasteryFailureResetsProgress() {
    var pm = PositionMastery(openingID: "italian", fen: "startpos", ply: 4)
    pm.review(quality: 5)
    pm.review(quality: 5)
    #expect(pm.repetitions == 2)

    pm.review(quality: 1) // Failed
    #expect(pm.repetitions == 0)
    #expect(pm.interval == 1)
}

@Test func positionMasteryEaseFactorNeverBelowMinimum() {
    var pm = PositionMastery(openingID: "italian", fen: "startpos", ply: 4)
    for _ in 0..<20 {
        pm.review(quality: 3)
    }
    #expect(pm.easeFactor >= 1.3)
}

@Test func positionMasteryRecordAttempt() {
    var pm = PositionMastery(openingID: "italian", fen: "startpos", ply: 4)
    pm.recordAttempt(correct: true)
    pm.recordAttempt(correct: true)
    pm.recordAttempt(correct: false)
    #expect(pm.totalAttempts == 3)
    #expect(pm.correctAttempts == 2)
    #expect(abs(pm.accuracy - 2.0/3.0) < 0.01)
}

@Test func positionMasteryIsMasteredRequiresBoth() {
    var pm = PositionMastery(openingID: "italian", fen: "startpos", ply: 4)
    // 3 reps but low accuracy
    pm.review(quality: 5)
    pm.review(quality: 5)
    pm.review(quality: 5)
    pm.totalAttempts = 10
    pm.correctAttempts = 5
    #expect(!pm.isMastered) // accuracy < 0.8

    pm.correctAttempts = 9
    #expect(pm.isMastered) // repetitions >= 3 && accuracy >= 0.8
}

@Test func positionKeyFormat() {
    let pm = PositionMastery(openingID: "italian", fen: "startpos", ply: 4, lineID: "italian/evans")
    #expect(pm.positionKey == "italian/italian/evans/4")

    let pm2 = PositionMastery(openingID: "italian", fen: "startpos", ply: 4)
    #expect(pm2.positionKey == "italian/main/4")
}
