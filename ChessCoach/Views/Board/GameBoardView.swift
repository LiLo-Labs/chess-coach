import SwiftUI
import ChessboardKit
import ChessKit

struct GameBoardView: View {
    var gameState: GameState
    var onMove: ((String, String) -> Void)?
    var allowInteraction: Bool = true

    @State private var boardModel: ChessboardModel

    init(gameState: GameState, allowInteraction: Bool = true, onMove: ((String, String) -> Void)? = nil) {
        self.gameState = gameState
        self.allowInteraction = allowInteraction
        self.onMove = onMove
        self._boardModel = State(initialValue: ChessboardModel(
            fen: gameState.fen,
            perspective: .white,
            colorScheme: .light
        ))
    }

    var body: some View {
        Chessboard(chessboardModel: boardModel)
            .onMove { move, isLegal, from, to, lan, promotionPiece in
                guard isLegal, allowInteraction else { return }
                if gameState.makeMove(from: from, to: to, promotion: promotionPiece) {
                    boardModel.game.make(move: move)
                    boardModel.setFen(
                        FenSerialization.default.serialize(position: boardModel.game.position),
                        lan: lan
                    )
                    onMove?(from, to)
                }
            }
            .onChange(of: gameState.fen) { _, newFen in
                boardModel.setFen(newFen)
            }
    }
}
