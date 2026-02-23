import Testing
@testable import ChessCoach

@Suite(.serialized)
struct CurriculumServiceTests {
    @Test func phase1ForcesMainLine() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let service = CurriculumService(opening: italian, phase: .learningMainLine)

        // Should force every move in the main line
        let move0 = service.getMaiaOverride(atPly: 0)
        #expect(move0 == "e2e4")

        let move1 = service.getMaiaOverride(atPly: 1)
        #expect(move1 == "e7e5")

        let move4 = service.getMaiaOverride(atPly: 4)
        #expect(move4 == "f1c4")
    }

    @Test func phase2AllowsLateDeviations() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let service = CurriculumService(opening: italian, phase: .naturalDeviations)

        // Early moves should be forced
        #expect(service.getMaiaOverride(atPly: 0) != nil)
        #expect(service.getMaiaOverride(atPly: 4) != nil)

        // After ply 6, Maia plays freely
        #expect(service.getMaiaOverride(atPly: 6) == nil)
        #expect(service.getMaiaOverride(atPly: 8) == nil)
    }

    @Test func phase4NeverOverrides() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let service = CurriculumService(opening: italian, phase: .freePlay)

        for ply in 0..<10 {
            #expect(service.getMaiaOverride(atPly: ply) == nil)
        }
    }

    @Test func categorizesMainLineAsGood() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let service = CurriculumService(opening: italian, phase: .learningMainLine)

        let category = service.categorizeUserMove(atPly: 0, move: "e2e4", stockfishScore: 30)
        #expect(category == .goodMove)
    }

    @Test func categorizesDeviationAsMistake() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let service = CurriculumService(opening: italian, phase: .learningMainLine)

        // A bad deviation with significant score loss
        let category = service.categorizeUserMove(atPly: 0, move: "a2a3", stockfishScore: -200)
        #expect(category == .mistake)
    }

    @Test func freePlayOnlyUsesScore() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let service = CurriculumService(opening: italian, phase: .freePlay)

        let good = service.categorizeUserMove(atPly: 0, move: "d2d4", stockfishScore: 10)
        #expect(good == .goodMove)

        let mistake = service.categorizeUserMove(atPly: 0, move: "a2a3", stockfishScore: -150)
        #expect(mistake == .mistake)
    }
}
