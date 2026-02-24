import Testing
@testable import ChessCoach

@Suite(.serialized)
struct CurriculumLineTests {
    private func makeItalianLine() -> OpeningLine {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        return OpeningLine(
            id: "italian/main",
            name: "Main Line",
            moves: italian.mainLine,
            branchPoint: 0,
            parentLineID: nil
        )
    }

    @Test func lineAwareForcesLineMoves() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let line = makeItalianLine()
        let service = CurriculumService(opening: italian, activeLine: line, phase: .learningMainLine)

        #expect(service.getMaiaOverride(atPly: 0) == "e2e4")
        #expect(service.getMaiaOverride(atPly: 1) == "e7e5")
    }

    @Test func lineAwareDetectsDeviation() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let line = makeItalianLine()
        let service = CurriculumService(opening: italian, activeLine: line, phase: .learningMainLine)

        #expect(service.isDeviation(atPly: 0, move: "d2d4"))
        #expect(!service.isDeviation(atPly: 0, move: "e2e4"))
    }

    @Test func discoveryModeNotInLearningPhase() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let service = CurriculumService(opening: italian, activeLine: nil, phase: .learningMainLine)

        #expect(!service.shouldDiscover(atPly: 4))
    }

    @Test func allBookMovesReturnsMainLine() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let service = CurriculumService(opening: italian, activeLine: nil, phase: .naturalDeviations)

        let moves = service.allBookMoves(atPly: 0)
        #expect(!moves.isEmpty)
        #expect(moves[0].uci == "e2e4")
    }

    @Test func shortLineAllowsFreePlayBeyondEnd() {
        let shortLine = OpeningLine(
            id: "test/short",
            name: "Short Line",
            moves: [
                OpeningMove(uci: "e2e4", san: "e4", explanation: ""),
                OpeningMove(uci: "e7e5", san: "e5", explanation: ""),
            ],
            branchPoint: 0,
            parentLineID: nil
        )
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let service = CurriculumService(opening: italian, activeLine: shortLine, phase: .learningMainLine)

        // Beyond the line length, should return nil (free play)
        #expect(service.getMaiaOverride(atPly: 2) == nil)
        // Should detect as deviation since ply 2 is beyond line
        #expect(service.isDeviation(atPly: 2, move: "g1f3"))
    }

    @Test func categorizeMainLineAsGoodInLineMode() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        let line = makeItalianLine()
        let service = CurriculumService(opening: italian, activeLine: line, phase: .learningMainLine)

        let category = service.categorizeUserMove(atPly: 0, move: "e2e4", stockfishScore: 20)
        #expect(category == .goodMove)
    }
}
