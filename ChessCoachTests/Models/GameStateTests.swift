import Testing
import ChessKit
@testable import ChessCoach

@Test func gameStateStartsFromInitialPosition() {
    let state = GameState()
    #expect(state.fen == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    #expect(state.moveHistory.isEmpty)
    #expect(state.isWhiteTurn)
}

@Test func gameStateMakesLegalMove() {
    let state = GameState()
    let moved = state.makeMove(from: "e2", to: "e4")
    #expect(moved)
    #expect(state.moveHistory.count == 1)
    #expect(!state.isWhiteTurn)
}

@Test func gameStateRejectsIllegalMove() {
    let state = GameState()
    let moved = state.makeMove(from: "e2", to: "e5")
    #expect(!moved)
    #expect(state.moveHistory.isEmpty)
}

@Test func gameStateMakesMoveUCI() {
    let state = GameState()
    let moved = state.makeMoveUCI("e2e4")
    #expect(moved)
    #expect(state.moveHistory.count == 1)
}

@Test func gameStateTracksMultipleMoves() {
    let state = GameState()
    #expect(state.makeMoveUCI("e2e4"))
    #expect(state.makeMoveUCI("e7e5"))
    #expect(state.makeMoveUCI("g1f3"))
    #expect(state.plyCount == 3)
    #expect(state.isWhiteTurn == false) // Black to move
}

@Test func gameStateResetsCorrectly() {
    let state = GameState()
    state.makeMoveUCI("e2e4")
    state.reset()
    #expect(state.fen == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    #expect(state.moveHistory.isEmpty)
}

@Test func gameStateFromCustomFEN() {
    let fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
    let state = GameState(fen: fen)
    #expect(!state.isWhiteTurn)
    #expect(state.fen == fen)
}
