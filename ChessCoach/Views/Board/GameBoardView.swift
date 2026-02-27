import SwiftUI
import ChessboardKit
import ChessKit

/// Chess.com-style board colors: warm cream + muted forest green
struct ChessComColorScheme: ChessboardColorScheme {
    var light: Color = Color(red: 0.93, green: 0.87, blue: 0.73)
    var dark: Color = Color(red: 0.46, green: 0.59, blue: 0.34)
    var label: Color = Color(red: 0.30, green: 0.30, blue: 0.25)
    var selected: Color = Color(red: 0.73, green: 0.79, blue: 0.22)
    var hinted: Color = Color(red: 0.45, green: 0.65, blue: 0.30)
    var legalMove: Color = Color(red: 0.20, green: 0.20, blue: 0.20, opacity: 0.35)
}

struct GameBoardView: View {
    var gameState: GameState
    var perspective: PieceColor
    var onMove: ((String, String) -> Void)?
    var allowInteraction: Bool = true

    @Environment(AppSettings.self) private var settings
    @State private var boardModel: ChessboardModel
    @State private var lastSyncedFen: String = ""

    init(gameState: GameState, perspective: PieceColor = .white, allowInteraction: Bool = true, onMove: ((String, String) -> Void)? = nil) {
        self.gameState = gameState
        self.perspective = perspective
        self.allowInteraction = allowInteraction
        self.onMove = onMove
        let fen = gameState.fen
        self._boardModel = State(initialValue: ChessboardModel(
            fen: fen,
            perspective: perspective,
            colorScheme: ChessComColorScheme()
        ))
        self._lastSyncedFen = State(initialValue: fen)
    }

    var body: some View {
        Chessboard(chessboardModel: boardModel)
            .onMove { move, isLegal, from, to, lan, promotionPiece in
                guard allowInteraction else { return }
                // Try the move on our game state first (source of truth)
                if gameState.makeMove(from: from, to: to, promotion: promotionPiece) {
                    // Sync the board model to match
                    let newFen = gameState.fen
                    boardModel.setFen(newFen, lan: lan)
                    lastSyncedFen = newFen
                    updateHighlightedSquares(from: from, to: to)
                    onMove?(from, to)
                } else if isLegal {
                    // ChessboardKit thought it was legal but GameState rejected it.
                    // This means the two are out of sync — force re-sync.
                    let currentFen = gameState.fen
                    boardModel.setFen(currentFen)
                    lastSyncedFen = currentFen
                }
            }
            .onChange(of: gameState.fen) { _, _ in
                syncBoard()
            }
            .onChange(of: gameState.moveHistory.count) { _, _ in
                // Catches undo: moveHistory is a stored property so @Observable tracks it reliably.
                // gameState.fen is computed and may not trigger onChange on undo.
                syncBoard()
            }
            .onChange(of: settings.boardTheme) { _, newTheme in
                boardModel.colorScheme = newTheme.colorScheme
            }
            .onAppear {
                boardModel.colorScheme = settings.boardTheme.colorScheme
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Chess board")
            .accessibilityHint(allowInteraction ? "Tap a piece then a destination to move" : "Current position")
    }

    private func syncBoard() {
        let newFen = gameState.fen
        if newFen != lastSyncedFen {
            if let last = gameState.moveHistory.last {
                let lan = "\(last.from)\(last.to)"
                boardModel.setFen(newFen, lan: lan)
                lastSyncedFen = newFen
                updateHighlightedSquares(from: last.from, to: last.to)
            } else {
                boardModel.setFen(newFen)
                lastSyncedFen = newFen
                boardModel.clearHighlights()
                boardModel.clearHint()
            }
        }
    }

    private func updateHighlightedSquares(from: String, to: String) {
        boardModel.clearHint()
        // Use filled tile highlights (Chess.com style) instead of border strokes
        boardModel.clearHighlights()
        boardModel.highlight([from, to])
    }
}
