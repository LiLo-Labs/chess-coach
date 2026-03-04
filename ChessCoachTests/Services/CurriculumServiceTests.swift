import Testing
@testable import ChessCoach

@Suite(.serialized)
struct CurriculumServiceTests {
    @Test func lowFamiliarityForcesAllMoves() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let service = CurriculumService(opening: italian, familiarity: 0.1)

        // Should force every move in the main line
        let move0 = service.getMaiaOverride(atPly: 0)
        #expect(move0 == "e2e4")

        let move1 = service.getMaiaOverride(atPly: 1)
        #expect(move1 == "e7e5")

        let move4 = service.getMaiaOverride(atPly: 4)
        #expect(move4 == "f1c4")
    }

    @Test func midFamiliarityForcesFirst4Plies() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let service = CurriculumService(opening: italian, familiarity: 0.5)

        // Early moves should be forced
        #expect(service.getMaiaOverride(atPly: 0) != nil)
        #expect(service.getMaiaOverride(atPly: 3) != nil)

        // After ply 4, plays freely
        #expect(service.getMaiaOverride(atPly: 4) == nil)
        #expect(service.getMaiaOverride(atPly: 8) == nil)
    }

    @Test func highFamiliarityNeverOverrides() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let service = CurriculumService(opening: italian, familiarity: 0.8)

        for ply in 0..<10 {
            #expect(service.getMaiaOverride(atPly: ply) == nil)
        }
    }

    @Test func categorizesMainLineAsGood() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let service = CurriculumService(opening: italian, familiarity: 0.1)

        let category = service.categorizeUserMove(atPly: 0, move: "e2e4", stockfishScore: 30)
        #expect(category == .goodMove)
    }

    @Test func categorizesDeviationAsMistake() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let service = CurriculumService(opening: italian, familiarity: 0.1)

        let category = service.categorizeUserMove(atPly: 0, move: "a2a3", stockfishScore: -200)
        #expect(category == .mistake)
    }

    @Test func highFamiliarityOnlyUsesScore() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let service = CurriculumService(opening: italian, familiarity: 0.8)

        let good = service.categorizeUserMove(atPly: 0, move: "d2d4", stockfishScore: 10)
        #expect(good == .goodMove)

        let mistake = service.categorizeUserMove(atPly: 0, move: "a2a3", stockfishScore: -150)
        #expect(mistake == .mistake)
    }
}
