import Testing
@testable import ChessCoach

@Test func shouldCoachAlwaysDuringLearning() {
    let db = OpeningDatabase()
    let italian = db.opening(named: "Italian Game")!
    let curriculum = CurriculumService(opening: italian, phase: .learningMainLine)
    let llm = LLMService()
    let coaching = CoachingService(llmService: llm, curriculumService: curriculum)

    Task {
        let should = await coaching.shouldCoach(moveCategory: .goodMove, phase: .learningMainLine)
        #expect(should)
    }
}

@Test func shouldNotCoachGoodMoveInFreePlay() {
    let db = OpeningDatabase()
    let italian = db.opening(named: "Italian Game")!
    let curriculum = CurriculumService(opening: italian, phase: .freePlay)
    let llm = LLMService()
    let coaching = CoachingService(llmService: llm, curriculumService: curriculum)

    Task {
        let should = await coaching.shouldCoach(moveCategory: .goodMove, phase: .freePlay)
        #expect(!should)
    }
}

@Test func shouldCoachMistakeInFreePlay() {
    let db = OpeningDatabase()
    let italian = db.opening(named: "Italian Game")!
    let curriculum = CurriculumService(opening: italian, phase: .freePlay)
    let llm = LLMService()
    let coaching = CoachingService(llmService: llm, curriculumService: curriculum)

    Task {
        let should = await coaching.shouldCoach(moveCategory: .mistake, phase: .freePlay)
        #expect(should)
    }
}
