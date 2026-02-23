import SwiftUI
import ChessboardKit
import ChessKit

/// Chess.com-style board colors: warm cream + muted forest green
struct ChessComColorScheme: ChessboardColorScheme {
    var light: Color = Color(red: 0.93, green: 0.87, blue: 0.73)
    var dark: Color = Color(red: 0.46, green: 0.59, blue: 0.34)
    var label: Color = Color(red: 0.30, green: 0.30, blue: 0.25)
    var selected: Color = Color(red: 0.73, green: 0.79, blue: 0.22)
    var hinted: Color = Color(red: 0.80, green: 0.20, blue: 0.20)
    var legalMove: Color = Color(red: 0.20, green: 0.20, blue: 0.20, opacity: 0.35)
}

struct GameBoardView: View {
    var gameState: GameState
    var perspective: PieceColor
    var onMove: ((String, String) -> Void)?
    var allowInteraction: Bool = true

    @State private var boardModel: ChessboardModel

    init(gameState: GameState, perspective: PieceColor = .white, allowInteraction: Bool = true, onMove: ((String, String) -> Void)? = nil) {
        self.gameState = gameState
        self.perspective = perspective
        self.allowInteraction = allowInteraction
        self.onMove = onMove
        self._boardModel = State(initialValue: ChessboardModel(
            fen: gameState.fen,
            perspective: perspective,
            colorScheme: ChessComColorScheme()
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
