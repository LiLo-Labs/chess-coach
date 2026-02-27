import Foundation
import ChessKit

@Observable
final class GameState: @unchecked Sendable {
    private(set) var game: Game
    private(set) var moveHistory: [(from: String, to: String, promotion: PieceKind?)] = []

    var fen: String {
        FenSerialization.default.serialize(position: game.position)
    }

    var isWhiteTurn: Bool {
        game.position.state.turn == .white
    }

    var isCheck: Bool { game.isCheck }
    var isMate: Bool { game.isMate }
    var legalMoves: [Move] { game.legalMoves }
    var plyCount: Int { moveHistory.count }

    init(fen: String? = nil) {
        if let fen {
            let position = FenSerialization.default.deserialize(fen: fen)
            self.game = Game(position: position)
        } else {
            let position = FenSerialization.default.deserialize(
                fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
            )
            self.game = Game(position: position)
        }
    }

    @discardableResult
    func makeMove(from: String, to: String, promotion: PieceKind? = nil) -> Bool {
        let move = Move(
            from: Square(coordinate: from),
            to: Square(coordinate: to),
            promotion: promotion
        )
        let legal = game.legalMoves
        guard legal.contains(where: { $0.from == move.from && $0.to == move.to }) else {
            return false
        }
        game.make(move: move)
        moveHistory.append((from: from, to: to, promotion: promotion))
        return true
    }

    @discardableResult
    func makeMoveUCI(_ uci: String) -> Bool {
        let from = String(uci.prefix(2))
        let to = String(uci.dropFirst(2).prefix(2))
        var promotion: PieceKind? = nil
        if uci.count == 5 {
            let promoChar = uci.last!
            promotion = Piece(character: Character(promoChar.uppercased()))?.kind
        }
        return makeMove(from: from, to: to, promotion: promotion)
    }

    /// Undo the last move by replaying all moves except the last from the start position.
    @discardableResult
    func undoLastMove() -> Bool {
        guard !moveHistory.isEmpty else { return false }
        let movesToReplay = Array(moveHistory.dropLast())
        reset()
        for m in movesToReplay {
            makeMove(from: m.from, to: m.to, promotion: m.promotion)
        }
        return true
    }

    /// Restore the game to a specific point by replaying a move history from the start.
    func restoreFromHistory(_ history: [(from: String, to: String, promotion: PieceKind?)]) {
        reset()
        for m in history {
            makeMove(from: m.from, to: m.to, promotion: m.promotion)
        }
    }

    /// Convert a UCI move string (e.g. "e2e4") to SAN (e.g. "e4") in the current position.
    func sanForUCI(_ uci: String) -> String? {
        let from = String(uci.prefix(2))
        let to = String(uci.dropFirst(2).prefix(2))
        var promotion: PieceKind? = nil
        if uci.count == 5 {
            let promoChar = uci.last!
            promotion = Piece(character: Character(promoChar.uppercased()))?.kind
        }
        let move = Move(from: Square(coordinate: from), to: Square(coordinate: to), promotion: promotion)
        guard game.legalMoves.contains(where: { $0.from == move.from && $0.to == move.to }) else {
            return nil
        }
        return SanSerialization.default.san(for: move, in: game)
    }

    /// Convert a UCI move to SAN given a FEN position (static helper).
    static func sanForUCI(_ uci: String, inFEN fen: String) -> String {
        let state = GameState(fen: fen)
        return state.sanForUCI(uci) ?? uci
    }

    func reset(fen: String? = nil) {
        let fenStr = fen ?? "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        let position = FenSerialization.default.deserialize(fen: fenStr)
        self.game = Game(position: position)
        self.moveHistory = []
    }
}
