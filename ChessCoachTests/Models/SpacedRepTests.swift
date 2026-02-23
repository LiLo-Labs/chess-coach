import Testing
@testable import ChessCoach

@Test func reviewItemStartsWithDefaults() {
    let item = ReviewItem(openingID: "italian", fen: "startpos", ply: 4)
    #expect(item.interval == 1)
    #expect(item.easeFactor == 2.5)
    #expect(item.repetitions == 0)
    #expect(item.isDue)
}

@Test func reviewItemPerfectResponseIncreasesInterval() {
    var item = ReviewItem(openingID: "italian", fen: "startpos", ply: 4)
    item.review(quality: 5) // Perfect
    #expect(item.repetitions == 1)
    #expect(item.interval == 1) // First review: 1 day

    item.review(quality: 5) // Perfect again
    #expect(item.repetitions == 2)
    #expect(item.interval == 6) // Second review: 6 days

    item.review(quality: 5) // Perfect again
    #expect(item.repetitions == 3)
    #expect(item.interval > 6) // Should increase
}

@Test func reviewItemFailureResetsProgress() {
    var item = ReviewItem(openingID: "italian", fen: "startpos", ply: 4)
    item.review(quality: 5)
    item.review(quality: 5)
    #expect(item.repetitions == 2)

    item.review(quality: 1) // Failed
    #expect(item.repetitions == 0)
    #expect(item.interval == 1)
}

@Test func reviewItemEaseFactorNeverBelowMinimum() {
    var item = ReviewItem(openingID: "italian", fen: "startpos", ply: 4)
    // Repeatedly give low (but passing) scores
    for _ in 0..<20 {
        item.review(quality: 3)
    }
    #expect(item.easeFactor >= 1.3)
}

@Test func progressRecordsGame() {
    var progress = OpeningProgress(openingID: "italian")
    progress.recordGame(accuracy: 0.8, won: true)
    #expect(progress.gamesPlayed == 1)
    #expect(progress.gamesWon == 1)
    #expect(progress.accuracy == 0.8)
}

@Test func progressCompositeScore() {
    var progress = OpeningProgress(openingID: "italian")
    for i in 0..<5 {
        progress.recordGame(accuracy: 0.85, won: i % 2 == 0)
    }
    #expect(progress.compositeScore > 0)
    #expect(progress.compositeScore <= 100)
}

@Test func progressPromotesPhase() {
    var progress = OpeningProgress(openingID: "italian")
    // Play enough games with high accuracy to promote
    for _ in 0..<5 {
        progress.recordGame(accuracy: 0.9, won: true)
    }
    // Should have promoted from learningMainLine
    #expect(progress.currentPhase != .learningMainLine)
}
