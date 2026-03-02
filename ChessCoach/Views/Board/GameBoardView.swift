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
    @State private var lastSyncedMoveCount: Int = 0

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
        self._lastSyncedMoveCount = State(initialValue: gameState.moveHistory.count)
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
                    lastSyncedMoveCount = gameState.moveHistory.count
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
                applyTextures(for: newTheme)
            }
            .onChange(of: settings.pieceStyle) { _, newStyle in
                boardModel.pieceStyleFolder = newStyle.assetFolder
            }
            .onAppear {
                boardModel.colorScheme = settings.boardTheme.colorScheme
                boardModel.pieceStyleFolder = settings.pieceStyle.assetFolder
                applyTextures(for: settings.boardTheme)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(boardAccessibilityLabel)
            .accessibilityHint(allowInteraction ? "Tap a piece then a destination to move. Use rotor actions for position details." : "Use rotor actions for position details.")
            .accessibilityAction(named: "Describe position") {
                let description = boardPositionDescription(fen: gameState.fen)
                AccessibilityNotification.Announcement(description).post()
            }
            .accessibilityAction(named: "Last move") {
                if let last = gameState.moveHistory.last {
                    let san = GameState.sanForUCI("\(last.from)\(last.to)", inFEN: gameState.fen) ?? "\(last.from)\(last.to)"
                    AccessibilityNotification.Announcement("Last move: \(san)").post()
                } else {
                    AccessibilityNotification.Announcement("No moves played yet.").post()
                }
            }
    }

    private var boardAccessibilityLabel: String {
        let turn = gameState.isWhiteTurn ? "White" : "Black"
        let moveCount = (gameState.plyCount / 2) + 1
        if gameState.isMate {
            return "Chess board. Checkmate."
        } else if boardModel.game.isCheck {
            return "Chess board. Move \(moveCount), \(turn) to move. Check."
        } else {
            return "Chess board. Move \(moveCount), \(turn) to move."
        }
    }

    /// Generate a spoken description of the board position from FEN.
    private func boardPositionDescription(fen: String) -> String {
        let parts = fen.split(separator: " ")
        guard let placement = parts.first else { return "Unable to read position." }

        var whitePieces: [String] = []
        var blackPieces: [String] = []

        let ranks = placement.split(separator: "/")
        let fileLetters = ["a", "b", "c", "d", "e", "f", "g", "h"]

        for (rankIdx, rank) in ranks.enumerated() {
            let rankNumber = 8 - rankIdx
            var fileIdx = 0
            for char in rank {
                if let skip = char.wholeNumberValue {
                    fileIdx += skip
                } else {
                    let square = "\(fileLetters[fileIdx])\(rankNumber)"
                    let name = pieceName(char)
                    if char.isUppercase {
                        whitePieces.append("\(name) on \(square)")
                    } else {
                        blackPieces.append("\(name) on \(square)")
                    }
                    fileIdx += 1
                }
            }
        }

        let turn = gameState.isWhiteTurn ? "White" : "Black"
        var desc = "\(turn) to move. "
        desc += "White: \(whitePieces.joined(separator: ", ")). "
        desc += "Black: \(blackPieces.joined(separator: ", "))."
        return desc
    }

    private func pieceName(_ char: Character) -> String {
        switch char.lowercased() {
        case "k": return "King"
        case "q": return "Queen"
        case "r": return "Rook"
        case "b": return "Bishop"
        case "n": return "Knight"
        case "p": return "Pawn"
        default: return "Piece"
        }
    }

    private func syncBoard() {
        let newFen = gameState.fen
        guard newFen != lastSyncedFen else { return }

        let newMoveCount = gameState.moveHistory.count
        let delta = newMoveCount - lastSyncedMoveCount

        if delta == 1, let last = gameState.moveHistory.last {
            // Single move forward — animate with LAN
            let lan = "\(last.from)\(last.to)"
            boardModel.setFen(newFen, lan: lan)
            updateHighlightedSquares(from: last.from, to: last.to)
        } else {
            // Multi-move change (undo, restore, reset) — snap, no animation
            boardModel.setFen(newFen)
            boardModel.clearHighlights()
            boardModel.clearHint()
            updateCheckSquare()
        }

        lastSyncedFen = newFen
        lastSyncedMoveCount = newMoveCount
    }

    private func updateHighlightedSquares(from: String, to: String) {
        boardModel.clearHint()
        // Use filled tile highlights (Chess.com style) instead of border strokes
        boardModel.clearHighlights()
        boardModel.highlight([from, to])
        updateCheckSquare()
    }

    private func applyTextures(for theme: BoardTheme) {
        if let textures = theme.textureImages {
            boardModel.lightSquareTexture = textures.light
            boardModel.darkSquareTexture = textures.dark
        } else {
            boardModel.lightSquareTexture = nil
            boardModel.darkSquareTexture = nil
        }
    }

    private func updateCheckSquare() {
        guard boardModel.game.isCheck else {
            boardModel.checkSquare = nil
            return
        }
        // Find the king of the side to move
        let isWhiteTurn = gameState.isWhiteTurn
        let board = boardModel.game.position.board
        for i in 0..<64 {
            if let piece = board[i],
               piece.kind == .king,
               (isWhiteTurn && piece.color == .white) || (!isWhiteTurn && piece.color == .black) {
                boardModel.checkSquare = BoardSquare(row: i % 8, column: i / 8)
                return
            }
        }
        boardModel.checkSquare = nil
    }
}
