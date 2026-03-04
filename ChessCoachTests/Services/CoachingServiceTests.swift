import Testing
@testable import ChessCoach

@Suite(.serialized)
struct CoachingServiceTests {
    @Test func shouldCoachAlwaysDuringLearning() async {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let curriculum = CurriculumService(opening: italian, familiarity: 0.1)
        let llm = LLMService()
        let coaching = CoachingService(llmService: llm, curriculumService: curriculum, featureAccess: UnlockedAccess())

        let should = await coaching.shouldCoach(moveCategory: .goodMove)
        #expect(should)
    }

    @Test func shouldNotCoachGoodMoveWhenFamiliar() async {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let curriculum = CurriculumService(opening: italian, familiarity: 0.8)
        let llm = LLMService()
        let coaching = CoachingService(llmService: llm, curriculumService: curriculum, featureAccess: UnlockedAccess())

        let should = await coaching.shouldCoach(moveCategory: .goodMove)
        #expect(!should)
    }

    @Test func shouldCoachMistakeWhenFamiliar() async {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let curriculum = CurriculumService(opening: italian, familiarity: 0.8)
        let llm = LLMService()
        let coaching = CoachingService(llmService: llm, curriculumService: curriculum, featureAccess: UnlockedAccess())

        let should = await coaching.shouldCoach(moveCategory: .mistake)
        #expect(should)
    }
}
