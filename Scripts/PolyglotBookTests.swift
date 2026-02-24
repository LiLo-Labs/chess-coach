import Testing
import Foundation
@testable import ChessCoach

@Suite(.serialized)
struct PolyglotZobristTests {
    @Test func startingPositionHash() {
        // The polyglot hash for the starting position is a well-known value
        let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let hash = PolyglotZobrist.hash(fen: fen)
        // Known polyglot hash for starting position
        #expect(hash == 0x463b96181691fc9c)
    }

    @Test func hashChangesAfterMove() {
        let startFen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let afterE4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        let hash1 = PolyglotZobrist.hash(fen: startFen)
        let hash2 = PolyglotZobrist.hash(fen: afterE4)
        #expect(hash1 != hash2)
    }

    @Test func hashDeterministic() {
        let fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
        let hash1 = PolyglotZobrist.hash(fen: fen)
        let hash2 = PolyglotZobrist.hash(fen: fen)
        #expect(hash1 == hash2)
    }

    @Test func hashRandomArrayCorrectSize() {
        // 12 pieces × 64 squares + 4 castling + 8 en passant + 1 turn = 781
        #expect(PolyglotZobrist.randomArray.count == 781)
    }

    @Test func emptyFenReturnsZero() {
        let hash = PolyglotZobrist.hash(fen: "")
        #expect(hash == 0)
    }

    @Test func knownPositionAfterE4E5() {
        // After 1. e4 e5
        let fen = "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2"
        let hash = PolyglotZobrist.hash(fen: fen)
        // Hash should be non-zero and deterministic
        #expect(hash != 0)
    }

    @Test func castlingRightsAffectHash() {
        let withCastling = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let withoutCastling = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w - - 0 1"
        let hash1 = PolyglotZobrist.hash(fen: withCastling)
        let hash2 = PolyglotZobrist.hash(fen: withoutCastling)
        #expect(hash1 != hash2)
    }

    @Test func turnAffectsHash() {
        // Same board position, different turn
        let whiteTurn = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 1"
        let blackTurn = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
        let hash1 = PolyglotZobrist.hash(fen: whiteTurn)
        let hash2 = PolyglotZobrist.hash(fen: blackTurn)
        #expect(hash1 != hash2)
    }
}

@Suite(.serialized)
struct PolyglotBookTests {
    @Test func emptyBookReturnsNoMoves() {
        let book = PolyglotBook(data: Data())
        let moves = book.lookup(hash: 0x463b96181691fc9c)
        #expect(moves.isEmpty)
    }

    @Test func bookEntryParsingWorks() {
        // Construct a minimal valid book with one entry for starting position
        // Hash: 0x463b96181691fc9c, Move: e2e4 encoded, Weight: 100, Learn: 0
        var data = Data()

        // Hash (big-endian): 0x463b96181691fc9c
        let hash: UInt64 = 0x463b96181691fc9c
        withUnsafeBytes(of: hash.bigEndian) { data.append(contentsOf: $0) }

        // Move: e2e4 = from e2 (file=4,rank=1) to e4 (file=4,rank=3)
        // Polyglot encoding: (fromRow << 9) | (fromFile << 6) | (toRow << 3) | toFile
        let moveRaw: UInt16 = (1 << 9) | (4 << 6) | (3 << 3) | 4
        withUnsafeBytes(of: moveRaw.bigEndian) { data.append(contentsOf: $0) }

        // Weight: 100
        let weight: UInt16 = 100
        withUnsafeBytes(of: weight.bigEndian) { data.append(contentsOf: $0) }

        // Learn: 0
        let learn: UInt32 = 0
        withUnsafeBytes(of: learn.bigEndian) { data.append(contentsOf: $0) }

        let book = PolyglotBook(data: data)
        let moves = book.lookup(hash: hash)
        #expect(moves.count == 1)
        #expect(moves[0].move == "e2e4")
        #expect(moves[0].weight == 100)
    }

    @Test func moveEncodingDecodesCorrectly() {
        // Polyglot encoding: (fromRow << 9) | (fromFile << 6) | (toRow << 3) | toFile
        // e2e4: from e2 (file=4,row=1) to e4 (file=4,row=3)
        let e2e4 = PolyglotBook.PolyglotMove(raw: (1 << 9) | (4 << 6) | (3 << 3) | 4)
        #expect(e2e4.uci == "e2e4")

        // d2d4: from d2 (file=3,row=1) to d4 (file=3,row=3)
        let d2d4 = PolyglotBook.PolyglotMove(raw: (1 << 9) | (3 << 6) | (3 << 3) | 3)
        #expect(d2d4.uci == "d2d4")

        // g1f3: from g1 (file=6,row=0) to f3 (file=5,row=2)
        let g1f3 = PolyglotBook.PolyglotMove(raw: (0 << 9) | (6 << 6) | (2 << 3) | 5)
        #expect(g1f3.uci == "g1f3")
    }

    @Test func castlingMoveConversion() {
        // Polyglot encoding: (fromRow << 9) | (fromFile << 6) | (toRow << 3) | toFile
        // e1h1 should become e1g1 (kingside castling)
        // from e1 (file=4,row=0) to h1 (file=7,row=0)
        let raw: UInt16 = (0 << 9) | (4 << 6) | (0 << 3) | 7
        let move = PolyglotBook.PolyglotMove(raw: raw)
        #expect(move.uci == "e1g1")

        // e1a1 should become e1c1 (queenside castling)
        // from e1 (file=4,row=0) to a1 (file=0,row=0)
        let rawQS: UInt16 = (0 << 9) | (4 << 6) | (0 << 3) | 0
        let moveQS = PolyglotBook.PolyglotMove(raw: rawQS)
        #expect(moveQS.uci == "e1c1")
    }

    @Test func multipleEntriesForSameHash() {
        var data = Data()
        let hash: UInt64 = 0x463b96181691fc9c

        // Entry 1: e2e4, weight 200 — (fromRow << 9) | (fromFile << 6) | (toRow << 3) | toFile
        withUnsafeBytes(of: hash.bigEndian) { data.append(contentsOf: $0) }
        let move1: UInt16 = (1 << 9) | (4 << 6) | (3 << 3) | 4  // e2e4
        withUnsafeBytes(of: move1.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(200).bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(0).bigEndian) { data.append(contentsOf: $0) }

        // Entry 2: d2d4, weight 150
        withUnsafeBytes(of: hash.bigEndian) { data.append(contentsOf: $0) }
        let move2: UInt16 = (1 << 9) | (3 << 6) | (3 << 3) | 3  // d2d4
        withUnsafeBytes(of: move2.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(150).bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(0).bigEndian) { data.append(contentsOf: $0) }

        let book = PolyglotBook(data: data)
        let moves = book.lookup(hash: hash)
        #expect(moves.count == 2)
        // Should be sorted by weight descending
        #expect(moves[0].weight >= moves[1].weight)
    }

    @Test func lookupMissReturnsEmpty() {
        var data = Data()
        let hash: UInt64 = 0x463b96181691fc9c
        withUnsafeBytes(of: hash.bigEndian) { data.append(contentsOf: $0) }
        let move: UInt16 = (1 << 9) | (4 << 6) | (3 << 3) | 4
        withUnsafeBytes(of: move.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(100).bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(0).bigEndian) { data.append(contentsOf: $0) }

        let book = PolyglotBook(data: data)
        let moves = book.lookup(hash: 0xDEADBEEF)
        #expect(moves.isEmpty)
    }
}
