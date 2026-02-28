import Testing
@testable import ChessCoach

@Suite(.serialized)
struct OpeningTests {
    @Test func databaseHasItalianGame() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")
        #expect(italian != nil)
        #expect(italian!.mainLine.count >= 6)
    }

    @Test func databaseHasLondonSystem() {
        let db = OpeningDatabase()
        let london = db.opening(named: "London System")
        #expect(london != nil)
        #expect(london!.color == .white)
    }

    @Test func openingDetectsDeviation() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        // Ply 1 should be e7e5 (Black's response)
        #expect(italian.isDeviation(atPly: 1, move: "d7d5"))
        #expect(!italian.isDeviation(atPly: 1, move: "e7e5"))
    }

    @Test func openingReturnsExpectedMove() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let firstMove = italian.expectedMove(atPly: 0)
        #expect(firstMove?.uci == "e2e4")
        #expect(firstMove?.san == "e4")
    }

    @Test func databaseHasOpenings() {
        let db = OpeningDatabase()
        #expect(db.openings.count >= 10, "Database should have at least 10 openings, got \(db.openings.count)")
    }

    @Test func canFilterByColor() {
        let db = OpeningDatabase()
        let whiteOpenings = db.openings(forColor: .white)
        let blackOpenings = db.openings(forColor: .black)
        #expect(!whiteOpenings.isEmpty)
        #expect(!blackOpenings.isEmpty)
        #expect(whiteOpenings.count + blackOpenings.count == db.openings.count)
    }
}
