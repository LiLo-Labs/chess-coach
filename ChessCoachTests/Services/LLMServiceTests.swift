import Testing
@testable import ChessCoach

@Test func llmServiceBuildsPrompt() {
    let context = CoachingContext(
        fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        lastMove: "e2e4",
        scoreBefore: 0,
        scoreAfter: 30,
        openingName: "King's Pawn Opening",
        openingDescription: "A classical opening starting with 1. e4",
        expectedMoveExplanation: "Controls the center",
        expectedMoveSAN: "e4",
        userELO: 600,
        phase: .learningMainLine,
        moveCategory: .okayMove,
        moveHistory: "1. e4",
        isUserMove: true,
        studentColor: "white",
        plyNumber: 1,
        mainLineSoFar: "1. e4"
    )
    let prompt = LLMService.buildPrompt(for: context)
    #expect(prompt.contains("e2e4"))
    #expect(prompt.contains("Side to move"))
}

@Test func llmServiceGoodMoveReturnsDirectly() {
    let context = CoachingContext(
        fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        lastMove: "e2e4",
        scoreBefore: 0,
        scoreAfter: 30,
        openingName: "King's Pawn Opening",
        openingDescription: "A classical opening starting with 1. e4",
        expectedMoveExplanation: "Controls the center",
        expectedMoveSAN: "e4",
        userELO: 600,
        phase: .learningMainLine,
        moveCategory: .goodMove,
        moveHistory: "1. e4",
        isUserMove: true,
        studentColor: "white",
        plyNumber: 1,
        mainLineSoFar: "1. e4"
    )
    let result = LLMService.buildPrompt(for: context)
    #expect(result.contains("correct"))
}

@Test func llmServiceBeginnersGetSimpleLanguage() {
    let context = CoachingContext(
        fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
        lastMove: "e2e4",
        scoreBefore: 0,
        scoreAfter: -100,
        openingName: "King's Pawn Opening",
        openingDescription: "A classical opening starting with 1. e4",
        expectedMoveExplanation: nil,
        expectedMoveSAN: nil,
        userELO: 500,
        phase: .learningMainLine,
        moveCategory: .mistake,
        moveHistory: "1. e4",
        isUserMove: true,
        studentColor: "white",
        plyNumber: 1,
        mainLineSoFar: "1. e4"
    )
    let prompt = LLMService.buildPrompt(for: context)
    #expect(prompt.contains("e2e4"))
    #expect(prompt.contains("book move"))
}
