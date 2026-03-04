import Testing
@testable import ChessCoach

@Suite
struct OffBookCoachingServiceTests {
    let service = OffBookCoachingService()
    let db = OpeningDatabase()

    // MARK: - guidanceIncludesPlanSummary

    @Test func guidanceIncludesPlanSummary() {
        let italian = db.opening(named: "Italian Game")!
        // FEN after 1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 — then player deviates at ply 6
        let fen = "r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"
        let guidance = service.generateGuidance(
            fen: fen,
            opening: italian,
            deviationPly: 6,
            moveHistory: ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5"]
        )

        #expect(!guidance.summary.isEmpty)
        #expect(guidance.summary.contains("Italian Game"))
        #expect(guidance.summary.contains("4")) // move number = (6/2)+1 = 4
        #expect(!guidance.planReminder.isEmpty)
        // The plan reminder should be the opening's plan summary
        #expect(guidance.planReminder == italian.plan!.summary)
    }

    // MARK: - guidanceForOpponentDeviation

    @Test func guidanceForOpponentDeviation() {
        let italian = db.opening(named: "Italian Game")!
        let fen = "r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"
        let guidance = service.generateGuidance(
            fen: fen,
            opening: italian,
            deviationPly: 5,
            moveHistory: ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bb4"],
            opponentDeviation: (played: "Bb4", expected: "Bc5")
        )

        #expect(guidance.summary.contains("opponent"))
        #expect(guidance.summary.contains("Bb4"))
        #expect(guidance.summary.contains("Bc5"))
    }

    // MARK: - relevantGoalsFiltersByCheckCondition

    @Test func relevantGoalsFiltersByCheckCondition() {
        // Create a synthetic opening with checkCondition on a goal
        let goalMet = StrategicGoal(
            description: "Put bishop on a2-g8 diagonal",
            priority: 1,
            measurable: true,
            checkCondition: "bishop_on_diagonal_a2g8"
        )
        let goalUnmet = StrategicGoal(
            description: "Castle kingside",
            priority: 2,
            measurable: true,
            checkCondition: "castled_kingside"
        )
        let plan = OpeningPlan(
            summary: "Test plan",
            strategicGoals: [goalMet, goalUnmet],
            pawnStructureTarget: "e4/d3",
            keySquares: ["f7"],
            pieceTargets: [],
            typicalPlans: [],
            commonMistakes: [],
            historicalNote: nil,
            planLessons: nil,
            theoryLessons: nil,
            planQuizzes: nil,
            theoryQuizzes: nil
        )

        var opening = Opening(
            id: "test",
            name: "Test Opening",
            description: "A test",
            color: .white,
            difficulty: 1,
            tags: nil,
            mainLine: []
        )
        opening.plan = plan

        // FEN with white bishop on c4 (a2-g8 diagonal) and castling rights still present
        let fen = "r1bqk1nr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"

        let guidance = service.generateGuidance(
            fen: fen,
            opening: opening,
            deviationPly: 6,
            moveHistory: []
        )

        // The bishop IS on diagonal a2g8 (c4), so that goal should be FILTERED OUT (met)
        // Castling rights are still present (KQkq), so castled_kingside is NOT met — goal stays
        let goalDescriptions = guidance.relevantGoals.map(\.description)
        #expect(!goalDescriptions.contains("Put bishop on a2-g8 diagonal"))
        #expect(goalDescriptions.contains("Castle kingside"))
    }

    // MARK: - FEN Parser unit tests

    @Test func isPieceOnSquareFindsWhiteBishopOnC4() {
        let board = "r1bqk1nr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R"
        #expect(FENParser.isPieceOnSquare(piece: "B", square: "c4", board: board))
        #expect(!FENParser.isPieceOnSquare(piece: "B", square: "d4", board: board))
    }

    @Test func squaresOnDiagonalA2G8() {
        let squares = FENParser.squaresOnDiagonal("a2g8")
        #expect(squares == ["a2", "b3", "c4", "d5", "e6", "f7", "g8"])
    }

    @Test func isCastledDetectsRightsPresent() {
        let fen = "r1bqk1nr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"
        // Castling rights present → not yet castled
        #expect(!FENParser.isCastled(kingside: true, fen: fen, isWhite: true))
    }

    @Test func isCastledDetectsRightsGone() {
        // White has lost kingside castling rights (only Qq remain)
        let fen = "r1bqk1nr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w Qq - 4 4"
        #expect(FENParser.isCastled(kingside: true, fen: fen, isWhite: true))
    }

    @Test func genericGuidanceWhenNoPlan() {
        var opening = Opening(
            id: "test-no-plan",
            name: "Mystery Opening",
            description: "No plan",
            color: .white,
            difficulty: 1,
            tags: nil,
            mainLine: []
        )
        opening.plan = nil

        let guidance = service.generateGuidance(
            fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1",
            opening: opening,
            deviationPly: 2,
            moveHistory: ["e4"]
        )

        #expect(guidance.summary.contains("Mystery Opening"))
        #expect(!guidance.planReminder.isEmpty)
        #expect(guidance.relevantGoals.isEmpty)
    }
}
