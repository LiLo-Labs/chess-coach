import Testing
@testable import ChessCoach

@Suite(.serialized)
struct CoachingServiceTests {
    @Test func shouldCoachAlwaysDuringLearning() async {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let curriculum = CurriculumService(opening: italian, phase: .learningMainLine)
        let llm = LLMService()
        let coaching = CoachingService(llmService: llm, curriculumService: curriculum, featureAccess: UnlockedAccess())

        let should = await coaching.shouldCoach(moveCategory: .goodMove, phase: .learningMainLine)
        #expect(should)
    }

    @Test func shouldNotCoachGoodMoveInFreePlay() async {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let curriculum = CurriculumService(opening: italian, phase: .freePlay)
        let llm = LLMService()
        let coaching = CoachingService(llmService: llm, curriculumService: curriculum, featureAccess: UnlockedAccess())

        let should = await coaching.shouldCoach(moveCategory: .goodMove, phase: .freePlay)
        #expect(!should)
    }

    @Test func shouldCoachMistakeInFreePlay() async {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let curriculum = CurriculumService(opening: italian, phase: .freePlay)
        let llm = LLMService()
        let coaching = CoachingService(llmService: llm, curriculumService: curriculum, featureAccess: UnlockedAccess())

        let should = await coaching.shouldCoach(moveCategory: .mistake, phase: .freePlay)
        #expect(should)
    }
}
