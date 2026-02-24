import Testing
import Foundation
@testable import ChessCoach

@Suite(.serialized)
struct SimpleBoardTests {
    @Test func initialFEN() {
        let board = SimpleBoard()
        let fen = board.toFEN()
        #expect(fen == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    }

    @Test func applyE2E4() {
        var board = SimpleBoard()
        board.applyUCIMove("e2e4")
        let fen = board.toFEN()
        #expect(fen.hasPrefix("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR"))
        #expect(fen.contains(" b "))  // Black to move
        #expect(fen.contains("e3"))   // En passant square
    }

    @Test func applyMultipleMoves() {
        var board = SimpleBoard()
        board.applyUCIMove("e2e4")
        board.applyUCIMove("e7e5")
        board.applyUCIMove("g1f3")
        board.applyUCIMove("b8c6")
        board.applyUCIMove("f1c4")  // Italian Game position
        let fen = board.toFEN()
        // Should have pieces in correct places
        #expect(fen.contains("B") || fen.contains("b"))  // bishops present
        #expect(!board.whiteToMove)  // Black to move
    }

    @Test func castlingKingside() {
        // Set up a position where kingside castling is legal
        var board = SimpleBoard(fen: "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4")
        board.applyUCIMove("e1g1")  // O-O
        let fen = board.toFEN()
        // After O-O: rank 1 should be RNBQ1RK1 (king on g1, rook on f1)
        #expect(fen.contains("RNBQ1RK1"))
        // Castling rights should be updated (no more K or Q for white)
        let parts = fen.split(separator: " ")
        let castling = parts.count > 2 ? String(parts[2]) : ""
        #expect(!castling.contains("K"))
        #expect(!castling.contains("Q"))
    }

    @Test func enPassantGeneration() {
        var board = SimpleBoard()
        board.applyUCIMove("e2e4")
        let fen = board.toFEN()
        #expect(fen.contains("e3"))  // En passant target

        board.applyUCIMove("d7d5")
        let fen2 = board.toFEN()
        #expect(fen2.contains("d6"))  // New en passant target
    }

    @Test func moveToSANPawn() {
        let board = SimpleBoard()
        let san = board.moveToSAN(uci: "e2e4")
        #expect(san == "e4")
    }

    @Test func moveToSANKnight() {
        let board = SimpleBoard()
        let san = board.moveToSAN(uci: "g1f3")
        #expect(san == "Nf3")
    }

    @Test func moveToSANCastling() {
        let board = SimpleBoard(fen: "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4")
        let san = board.moveToSAN(uci: "e1g1")
        #expect(san == "O-O")
    }

    @Test func moveToSANCapture() {
        // Position where Nf3 can capture on e5
        let board = SimpleBoard(fen: "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 2")
        let san = board.moveToSAN(uci: "f3e5")
        #expect(san == "Nxe5")
    }

    @Test func fullmoveIncrementsCorrectly() {
        var board = SimpleBoard()
        #expect(board.fullmove == 1)
        board.applyUCIMove("e2e4")
        #expect(board.fullmove == 1)  // Still move 1 (black hasn't moved)
        board.applyUCIMove("e7e5")
        #expect(board.fullmove == 2)  // Now move 2
    }
}

@Suite(.serialized)
struct OpeningNodeTests {
    @Test func allLinesFromSimpleTree() {
        let leaf1 = OpeningNode(
            id: "leaf1",
            move: OpeningMove(uci: "g8f6", san: "Nf6", explanation: "Develop knight"),
            children: [],
            isMainLine: true,
            weight: 100
        )
        let leaf2 = OpeningNode(
            id: "leaf2",
            move: OpeningMove(uci: "d7d5", san: "d5", explanation: "Central pawn"),
            children: [],
            isMainLine: false,
            weight: 50
        )
        let parent = OpeningNode(
            id: "parent",
            move: OpeningMove(uci: "e7e5", san: "e5", explanation: "Mirror"),
            children: [leaf1, leaf2],
            isMainLine: true,
            weight: 200
        )
        let root = OpeningNode(id: "root", children: [parent], weight: 0)

        let lines = root.allLines()
        #expect(lines.count == 2)  // Two paths: root->parent->leaf1, root->parent->leaf2
    }

    @Test func allLinesFromSinglePath() {
        let leaf = OpeningNode(
            id: "leaf",
            move: OpeningMove(uci: "g1f3", san: "Nf3", explanation: ""),
            children: [],
            isMainLine: true,
            weight: 100
        )
        let child = OpeningNode(
            id: "child",
            move: OpeningMove(uci: "e2e4", san: "e4", explanation: ""),
            children: [leaf],
            isMainLine: true,
            weight: 200
        )
        let root = OpeningNode(id: "root", children: [child], weight: 0)

        let lines = root.allLines()
        #expect(lines.count == 1)
        #expect(lines[0].moves.count == 2)
    }

    @Test func emptyTreeProducesOneLine() {
        let root = OpeningNode(id: "root", children: [], weight: 0)
        let lines = root.allLines()
        #expect(lines.count == 1)
        #expect(lines[0].moves.isEmpty)
    }
}

@Suite(.serialized)
struct OpeningTreeQueryTests {
    @Test func continuationsReturnsMainLineForLegacyOpening() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!

        // No tree => falls back to main line
        let continuations = italian.continuations(afterMoves: [])
        #expect(continuations.count == 1)
        #expect(continuations[0].uci == "e2e4")
    }

    @Test func continuationsReturnsEmptyAfterDeviation() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!

        // After an incorrect move, no continuations
        let continuations = italian.continuations(afterMoves: ["a2a3"])
        #expect(continuations.isEmpty)
    }

    @Test func matchingLinesForPartialSequence() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!

        // First two moves of Italian
        let lines = italian.matchingLines(forMoveSequence: ["e2e4", "e7e5"])
        #expect(!lines.isEmpty)
    }

    @Test func matchingLinesReturnsEmptyForWrongMoves() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!

        let lines = italian.matchingLines(forMoveSequence: ["d2d4", "d7d5"])
        #expect(lines.isEmpty)
    }

    @Test func isKnownContinuationMainLine() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!

        #expect(italian.isKnownContinuation(atPly: 0, move: "e2e4", afterMoves: []))
        #expect(!italian.isKnownContinuation(atPly: 0, move: "a2a3", afterMoves: []))
    }
}
