import Testing
@testable import ChessCoach

@Test func llmServiceBuildsPrompt() {
    let context = CoachingContext(
        fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        lastMove: "e2e4",
        scoreBefore: 0,
        scoreAfter: 30,
        openingName: "King's Pawn Opening",
        userELO: 600,
        phase: .learningMainLine,
        moveCategory: .okayMove
    )
    let prompt = LLMService.buildPrompt(for: context)
    #expect(prompt.contains("e2e4"))
    #expect(prompt.contains("beginner"))
}

@Test func llmServiceGoodMoveReturnsDirectly() {
    let context = CoachingContext(
        fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        lastMove: "e2e4",
        scoreBefore: 0,
        scoreAfter: 30,
        openingName: "King's Pawn Opening",
        userELO: 600,
        phase: .learningMainLine,
        moveCategory: .goodMove
    )
    let result = LLMService.buildPrompt(for: context)
    #expect(result.contains("Good move"))
}

@Test func llmServiceBeginnersGetSimpleLanguage() {
    let context = CoachingContext(
        fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        lastMove: "e2e4",
        scoreBefore: 0,
        scoreAfter: -100,
        openingName: "King's Pawn Opening",
        userELO: 500,
        phase: .learningMainLine,
        moveCategory: .mistake
    )
    let prompt = LLMService.buildPrompt(for: context)
    #expect(prompt.contains("complete beginner"))
}
