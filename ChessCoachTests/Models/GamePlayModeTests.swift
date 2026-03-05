import Testing
@testable import ChessCoach

@Suite(.serialized)
struct GamePlayModeTests {

    // MARK: - Helpers

    /// Minimal opening for testing. Uses the Italian Game's first 6 moves.
    private static func makeTestOpening(
        id: String = "test-opening",
        color: Opening.PlayerColor = .white
    ) -> Opening {
        Opening(
            id: id,
            name: "Test Opening",
            description: "A test opening",
            color: color,
            difficulty: 2,
            tags: nil,
            mainLine: [
                OpeningMove(uci: "e2e4", san: "e4", explanation: "King's pawn"),
                OpeningMove(uci: "e7e5", san: "e5", explanation: "Symmetrical"),
                OpeningMove(uci: "g1f3", san: "Nf3", explanation: "Knight out"),
                OpeningMove(uci: "b8c6", san: "Nc6", explanation: "Defend"),
                OpeningMove(uci: "f1c4", san: "Bc4", explanation: "Italian bishop"),
                OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Two knights"),
            ]
        )
    }

    // MARK: - .puzzle with no opening (standalone)

    @Test func puzzleIsPuzzle() {
        let mode = GamePlayMode.puzzle(opening: nil, source: .standalone)
        #expect(mode.isPuzzle == true)
    }

    @Test func puzzleIsNotTrainer() {
        let mode = GamePlayMode.puzzle(opening: nil, source: .standalone)
        #expect(mode.isTrainer == false)
    }

    @Test func puzzleIsNotSession() {
        let mode = GamePlayMode.puzzle(opening: nil, source: .standalone)
        #expect(mode.isSession == false)
    }

    @Test func puzzleOpeningNilWhenStandalone() {
        let mode = GamePlayMode.puzzle(opening: nil, source: .standalone)
        #expect(mode.opening == nil)
    }

    @Test func puzzlePlayerColorDefaultsToWhite() {
        let mode = GamePlayMode.puzzle(opening: nil, source: .standalone)
        #expect(mode.playerColor == .white)
    }

    @Test func puzzleSessionModeIsNil() {
        let mode = GamePlayMode.puzzle(opening: nil, source: .standalone)
        #expect(mode.sessionMode == nil)
    }

    @Test func puzzleShowsArrowsIsFalse() {
        let mode = GamePlayMode.puzzle(opening: nil, source: .standalone)
        #expect(mode.showsArrows == false)
    }

    // MARK: - .puzzle with opening

    @Test func puzzleReturnsOpeningWhenProvided() {
        let opening = Self.makeTestOpening()
        let mode = GamePlayMode.puzzle(opening: opening, source: .opening(opening))
        #expect(mode.opening?.id == "test-opening")
    }

    @Test func puzzlePlayerColorMatchesWhiteOpening() {
        let opening = Self.makeTestOpening(color: .white)
        let mode = GamePlayMode.puzzle(opening: opening, source: .opening(opening))
        #expect(mode.playerColor == .white)
    }

    @Test func puzzlePlayerColorMatchesBlackOpening() {
        let opening = Self.makeTestOpening(color: .black)
        let mode = GamePlayMode.puzzle(opening: opening, source: .opening(opening))
        #expect(mode.playerColor == .black)
    }

    @Test func puzzleLineIDIsAlwaysNil() {
        let opening = Self.makeTestOpening()
        let mode = GamePlayMode.puzzle(opening: opening, source: .opening(opening))
        #expect(mode.lineID == nil)
    }

    // MARK: - Contrast with other modes

    @Test func trainerIsNotPuzzle() {
        let mode = GamePlayMode.trainer(personality: OpponentPersonality.forELO(600), engineMode: .humanLike, playerColor: .white, botELO: 600)
        #expect(mode.isPuzzle == false)
        #expect(mode.isTrainer == true)
        #expect(mode.isSession == false)
    }

    @Test func guidedIsNotPuzzle() {
        let opening = Self.makeTestOpening()
        let mode = GamePlayMode.guided(opening: opening, lineID: nil)
        #expect(mode.isPuzzle == false)
        #expect(mode.isSession == true)
    }
}
