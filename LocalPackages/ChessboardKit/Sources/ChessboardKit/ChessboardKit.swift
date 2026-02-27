//
// ChessboardKit is a SwiftUI library for rendering chessboards and pieces.
//
// See the GitHub repo for documentation:
// https://github.com/rohanrhu/ChessboardKit
//
// Copyright (C) 2025, Oğuzhan Eroğlu (https://meowingcat.io)
// Licensed under the MIT License.
// You may obtain a copy of the License at: https://opensource.org/licenses/MIT
// See the LICENSE file for more information.
//

import SwiftUI
import UIKit

import ChessKit

public let EMPTY_FEN = "8/8/8/8/8/8/8/8 w - - 0 1"
public let INITIAL_FEN = "rnbqkb1r/pppppppp/8/8/8/8/PPPPPPPP/RNBQKB1R w KQkq - 0 1"

public struct BoardSquare: Identifiable, Hashable {
    public var row: Int
    public var column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    public var id: String {
        "\(row),\(column)"
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(row)
        hasher.combine(column)
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.row == rhs.row && lhs.column == rhs.column
    }
    
    public static func != (lhs: Self, rhs: Self) -> Bool {
        lhs.row != rhs.row || lhs.column != rhs.column
    }
}

@Observable
public class ChessboardModel {
    public var fen: String {
        get { FenSerialization.default.serialize(position: game.position) }
        set { game = Game(position: FenSerialization.default.deserialize(fen: newValue)) }
    }
    
    public var size: CGFloat = 0

    public var colorScheme: ChessboardColorScheme = .light

    /// Piece style folder name (e.g. "uscf", "cburnett", "merida", "staunty", "california").
    public var pieceStyleFolder: String = "uscf"
    
    public var perspective: PieceColor
    public var turn: PieceColor { game.position.state.turn }
    public var validateMoves: Bool = false
    public var allowOpponentMove = false
    
    public var inWaiting = false
    
    public var selectedSquare: BoardSquare?
    public var hintedSquares: Set<BoardSquare> = []

    /// Squares to highlight with a filled color (e.g. last-move highlight).
    /// Rendered between the board background and pieces so pieces appear on top.
    public var highlightedSquares: Set<BoardSquare> = []
    public var highlightColor: Color = Color(red: 0.73, green: 0.79, blue: 0.22, opacity: 0.55)
    
    public var highlightLegalMoves: Bool = true
    public var legalMoveSquares: Set<BoardSquare> = []
    
    public var showPromotionPicker = false
    
    public var game: Game
    
    public var currentMove: Move? = nil
    public var prevMove: Move? = nil
    
    public var promotionPiece: Piece?
    public var promotionSourceSquare: String?
    public var promotionTargetSquare: String?
    public var promotionLan: String?
    
    public var shouldFlipBoard: Bool { perspective == .black }
    
    public var movingPiece: (piece: Piece, from: BoardSquare, to: BoardSquare)?

    /// Square where a capture just occurred — triggers a brief visual effect.
    public var captureSquare: BoardSquare?
    
    public init(fen: String = EMPTY_FEN,
                perspective: PieceColor = .white,
                colorScheme: ChessboardColorScheme = .light,
                allowOpponentMove: Bool = false,
                highlightLegalMoves: Bool = true)
    {
        self.game = Game(position: FenSerialization.default.deserialize(fen: fen))
        self.perspective = perspective
        self.colorScheme = colorScheme
        self.allowOpponentMove = allowOpponentMove
        self.highlightLegalMoves = highlightLegalMoves
    }
    
    public var onMove: (Move, Bool, String, String, String, PieceKind? ) -> Void = { _, _, _, _, _, _ in }
    
    public var dropTarget: (row: Int, column: Int)?
    
    public func setFen(_ fen: String, lan: String? = nil) {
        prevMove = currentMove
        currentMove = lan == nil ? nil : Move(string: lan!)

        // Detect captures BEFORE updating position
        captureSquare = nil
        if let currentMove {
            let destIndex = currentMove.to.rank + currentMove.to.file * 8
            if game.position.board[destIndex] != nil {
                // Piece on destination = capture
                captureSquare = BoardSquare(row: currentMove.to.rank, column: currentMove.to.file)
            }
        }

        // Update FEN so the board reflects the new position,
        // then extract the moved piece from the NEW state for animation.
        self.fen = fen

        if let currentMove {
            // Look up the piece at its DESTINATION on the new board
            let pieces = game.position.board.enumeratedPieces()
            let squareAndPiece = pieces.first { $0.0 == currentMove.to }

            if let piece = squareAndPiece?.1
            {
                let from = BoardSquare(row: currentMove.from.rank, column: currentMove.from.file)
                let to = BoardSquare(row: currentMove.to.rank, column: currentMove.to.file)

                movingPiece = (piece: piece, from: from, to: to)
            }
        }
    }
    
    public func deselect() {
        selectedSquare = nil
        legalMoveSquares.removeAll()
    }
    
    public func updateLegalMoveHighlights(for square: BoardSquare) {
        guard highlightLegalMoves else {
            legalMoveSquares.removeAll()
            return
        }
        
        legalMoveSquares.removeAll()
        
        let index = square.row + square.column * 8
        guard game.position.board[index] != nil else { return }
        
        for move in game.legalMoves {
            if move.from.rank == square.row && move.from.file == square.column {
                let targetSquare = BoardSquare(row: move.to.rank, column: move.to.file)
                legalMoveSquares.insert(targetSquare)
            }
        }
    }
    
    public func clearLegalMoveHighlights() {
        legalMoveSquares.removeAll()
    }
    
    public func hint(_ square: BoardSquare) {
        hintedSquares.insert(square)
    }
    
    public func hint(_ square: String) {
        if square.count != 2 {
            return
        }
        
        let fileChar = square.first!
        let rankChar = square.last!
        
        let file = "abcdefgh".firstIndex(of: fileChar)?.utf16Offset(in: "abcdefgh")
        let rank = Int(String(rankChar))
        
        guard let file = file, let rank = rank else {
            return
        }
        
        let row = rank - 1
        let column = file
        
        hint(BoardSquare(row: row, column: column))
    }
    
    public func hint(row: Int, column: Int) {
        hint(BoardSquare(row: row, column: column))
    }
    
    public func hint(_ squares: [BoardSquare]) {
        for square in squares {
            hint(square)
        }
    }
    
    public func hint(_ squares: [String]) {
        for square in squares {
            hint(square)
        }
    }
    
    public func clearHint() {
        hintedSquares.removeAll()
    }

    // MARK: - Last-move tile highlights (filled squares, Chess.com style)

    public func highlight(_ square: BoardSquare) {
        highlightedSquares.insert(square)
    }

    public func highlight(_ square: String) {
        guard square.count == 2,
              let fileChar = square.first,
              let rankChar = square.last,
              let file = "abcdefgh".firstIndex(of: fileChar)?.utf16Offset(in: "abcdefgh"),
              let rank = Int(String(rankChar))
        else { return }
        highlightedSquares.insert(BoardSquare(row: rank - 1, column: file))
    }

    public func highlight(_ squares: [String]) {
        for square in squares {
            highlight(square)
        }
    }

    public func clearHighlights() {
        highlightedSquares.removeAll()
    }
    
    @MainActor
    public func hint(_ square: String, for seconds: Double) {
        withAnimation {
            hint(square)
        }
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            
            withAnimation {
                self.clearHint()
            }
        }
    }
    
    @MainActor
    public func hint(_ squares: [String], for seconds: Double) {
        withAnimation {
            hint(squares)
        }
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            
            withAnimation {
                self.clearHint()
            }
        }
    }
    
    @MainActor
    public func hint(_ squares: [BoardSquare], for seconds: Double) {
        withAnimation {
            hint(squares)
        }
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            
            withAnimation {
                self.clearHint()
            }
        }
    }
    
    @MainActor
    public func hint(_ square: BoardSquare, for seconds: Double) {
        withAnimation {
            hint(square)
        }
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            
            withAnimation {
                self.clearHint()
            }
        }
    }
    
    public func presentPromotionPicker(piece: Piece, sourceSquare: String, targetSquare: String, lan: String) {
        promotionPiece = piece
        promotionSourceSquare = sourceSquare
        promotionTargetSquare = targetSquare
        promotionLan = lan
        
        withAnimation(.bouncy) {
            showPromotionPicker = true
        }
    }
    
    public func absentePromotionPicker() {
        promotionPiece = nil
        promotionSourceSquare = nil
        promotionTargetSquare = nil
        promotionLan = nil
        
        withAnimation(.bouncy) {
            showPromotionPicker = false
        }
    }
    
    public func togglePromotionPicker() {
        withAnimation(.bouncy) {
            showPromotionPicker.toggle()
        }
    }
    
    public func isPromotable(piece: Piece, lan: String) -> Bool {
        guard piece.kind == .pawn else { return false }
        guard lan.count >= 4 else { return false }
        
        let toSquare = lan.suffix(2)
        let rowChar = toSquare.last!
        
        guard let row = Int(String(rowChar)) else { return false }
        
        return row == (piece.color == .white ? 8 : 1)
    }
    
    public func beginWaiting() {
        withAnimation(.bouncy) {
            inWaiting = true
        }
    }
    
    public func endWaiting() {
        withAnimation(.bouncy) {
            inWaiting = false
        }
    }

    /// Load a piece image from the ChessboardKit bundle.
    /// - Parameters:
    ///   - name: Image name, e.g. "wK", "bQ"
    ///   - folder: Piece style folder, e.g. "uscf", "cburnett"
    public static func pieceImage(named name: String, folder: String = "uscf") -> UIImage? {
        if let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: folder),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        return nil
    }
}

private struct MovingPieceView: View {
    var animation: Namespace.ID
    
    @Environment(ChessboardModel.self) var chessboardModel
    
    @State var position: CGPoint = .zero
    
    var body: some View {
        Group {
            if let movingPiece = chessboardModel.movingPiece {
                ChessPieceView(animation: animation,
                               piece: movingPiece.piece,
                               square: BoardSquare(row: movingPiece.from.row, column: movingPiece.from.column),
                               isMovingPiece: true)
                .position(position)
                .onAppear {
                    position = CGPoint(x: chessboardModel.size / 16 + chessboardModel.size / 8 * CGFloat(chessboardModel.shouldFlipBoard ? 7 - movingPiece.from.column : movingPiece.from.column),
                                       y: chessboardModel.size / 16 + chessboardModel.size / 8 * CGFloat(chessboardModel.shouldFlipBoard ? movingPiece.from.row : 7 - movingPiece.from.row))
                    
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        position = CGPoint(x: chessboardModel.size / 16 + chessboardModel.size / 8 * CGFloat(chessboardModel.shouldFlipBoard ? 7 - movingPiece.to.column : movingPiece.to.column),
                                           y: chessboardModel.size / 16 + chessboardModel.size / 8 * CGFloat(chessboardModel.shouldFlipBoard ? movingPiece.to.row : 7 - movingPiece.to.row))
                    } completion: {
                        chessboardModel.movingPiece = nil
                    }
                }
            }
        }
    }
}

/// Burst ring effect shown on the square where a capture occurred.
private struct CaptureEffectView: View {
    @Environment(ChessboardModel.self) var chessboardModel

    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0.8

    var body: some View {
        Group {
            if let square = chessboardModel.captureSquare {
                let squareSize = chessboardModel.size / 8
                let x = squareSize / 2 + squareSize * CGFloat(chessboardModel.shouldFlipBoard ? 7 - square.column : square.column)
                let y = squareSize / 2 + squareSize * CGFloat(chessboardModel.shouldFlipBoard ? square.row : 7 - square.row)

                Circle()
                    .stroke(Color.orange.opacity(opacity), lineWidth: 3)
                    .frame(width: squareSize * scale, height: squareSize * scale)
                    .position(x: x, y: y)
                    .onAppear {
                        scale = 0.3
                        opacity = 0.8
                        withAnimation(.easeOut(duration: 0.35)) {
                            scale = 1.4
                            opacity = 0.0
                        } completion: {
                            chessboardModel.captureSquare = nil
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }
}

public struct Chessboard: View {
    public var chessboardModel: ChessboardModel

    @Namespace private var animation

    public init(chessboardModel: ChessboardModel) {
        self.chessboardModel = chessboardModel
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundView
                squareHighlightsView
                labelsView
                squaresView
                piecesView
                legalMoveHighlightsView
                
                MovingPieceView(animation: animation)
                CaptureEffectView()

                if chessboardModel.showPromotionPicker {
                    promotionPickerView
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                
                if chessboardModel.inWaiting {
                    inWaitingView
                }
            }
            .environment(chessboardModel)
            .frame(width: chessboardSize(from: geometry.size),
                   height: chessboardSize(from: geometry.size))
            .onAppear {
                updateChessboardSize(geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                updateChessboardSize(newSize)
            }
            .task {
                updateChessboardSize(geometry.size)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func chessboardSize(from geometrySize: CGSize) -> CGFloat {
        return min(geometrySize.width, geometrySize.height)
    }

    private func updateChessboardSize(_ geometrySize: CGSize) {
        let newSize = chessboardSize(from: geometrySize)
        chessboardModel.size = newSize
    }
    
    var inWaitingView: some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
                .ignoresSafeArea()
        }
    }
    
    var promotionPickerView: some View {
        ZStack {
            Color.white.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                HStack(spacing: 20) {
                    ForEach(["q", "r", "b", "n"], id: \.self) { (piece: String) in
                        Button {
                            guard let sourceSquare = chessboardModel.promotionSourceSquare,
                                  let targetSquare = chessboardModel.promotionTargetSquare,
                                  let lan = chessboardModel.promotionLan
                            else {
                                chessboardModel.absentePromotionPicker()
                                return
                            }
                            
                            let promotedLan = lan + piece.uppercased()
                            let promotedMove = Move(string: promotedLan)
                            let isLegal = chessboardModel.game.legalMoves.contains(promotedMove)
                            
                            chessboardModel.onMove(promotedMove, isLegal, sourceSquare, targetSquare, promotedLan, PieceKind(rawValue: piece))
                            
                            chessboardModel.absentePromotionPicker()
                        } label: {
                            let imageName = "\(chessboardModel.perspective == PieceColor.white ? "w" : "b")\(String(describing: piece).uppercased())"

                            ZStack {
                                if let uiImage = ChessPieceView.loadPieceImage(named: imageName, folder: chessboardModel.pieceStyleFolder) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .frame(width: chessboardModel.size / 8,
                                                height: chessboardModel.size / 8)
                                        .contentShape(Rectangle())
                                } else {
                                    Text("\(piece)")
                                        .foregroundStyle(piece == "w" ? Color.white : Color.black)
                                        .font(.system(size: 18))
                                        .scaledToFit()
                                        .contentShape(Rectangle())
                                }
                            }
                            .padding(5)
                        }
                        .background(.white)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .shadow(radius: 5)
            .padding(.horizontal, 20)
        }
    }
    
    var backgroundView: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 8), spacing: 0) {
            ForEach(0..<64) { index in
                let row = index / 8
                let column = index % 8
                let isLightSquare = (row + column) % 2 == 0
                
                Rectangle()
                    .fill(isLightSquare ? chessboardModel.colorScheme.light : chessboardModel.colorScheme.dark)
                    .frame(width: chessboardModel.size / 8, height: chessboardModel.size / 8)
            }
        }
    }
    
    var squareHighlightsView: some View {
        ZStack {
            ForEach(Array(chessboardModel.highlightedSquares), id: \.id) { square in
                chessboardModel.highlightColor
                    .frame(width: chessboardModel.size / 8, height: chessboardModel.size / 8)
                    .position(
                        x: chessboardModel.size / 16 + chessboardModel.size / 8 * CGFloat(chessboardModel.shouldFlipBoard ? 7 - square.column : square.column),
                        y: chessboardModel.size / 16 + chessboardModel.size / 8 * CGFloat(chessboardModel.shouldFlipBoard ? square.row : 7 - square.row)
                    )
            }
        }
        .allowsHitTesting(false)
    }

    var labelsView: some View {
        ZStack {
            ForEach(0..<8) { row in
                rowLabelView(row: row)
            }
            
            ForEach(0..<8) { column in
                columnLabelView(column: column)
            }
        }
    }
    
    func rowLabelView(row: Int) -> some View {
        let displayRow = chessboardModel.shouldFlipBoard ? (7 - row) : row
        let labelSize = chessboardModel.size / 32
        let squareSize = chessboardModel.size / 8
        
        return Text("\(displayRow + 1)")
            .font(.system(size: labelSize))
            .foregroundColor(chessboardModel.colorScheme.label)
            .frame(width: labelSize, height: squareSize, alignment: .center)
            .position(
                x: labelSize / 2 + 2,
                y: chessboardModel.size - (CGFloat(row) * squareSize + squareSize - 10)
            )
    }
    
    func columnLabelView(column: Int) -> some View {
        let displayColumn = chessboardModel.shouldFlipBoard ? 7 - column : column
        let labelSize = chessboardModel.size / 32
        let squareSize = chessboardModel.size / 8
        
        return Text(["a", "b", "c", "d", "e", "f", "g", "h"][displayColumn])
            .font(.system(size: labelSize))
            .foregroundColor(chessboardModel.colorScheme.label)
            .frame(width: squareSize, height: labelSize, alignment: .center)
            .position(
                x: (CGFloat(column) * squareSize + squareSize) - 8,
                y: (chessboardModel.size - labelSize / 2) - 4
            )
    }
    
    var squaresView: some View {
        ZStack {
            ForEach(0..<64, id: \.self) { index in
                let row = index % 8
                let column = index / 8
                let piece = chessboardModel.game.position.board[index]
                
                ChessSquareView(piece: piece,
                                row: row,
                                column: column)
                .position(x: chessboardModel.size / 16 + chessboardModel.size / 8 * CGFloat(chessboardModel.shouldFlipBoard ? 7 - column : column),
                          y: chessboardModel.size / 16 + chessboardModel.size / 8 * CGFloat(chessboardModel.shouldFlipBoard ? row : 7 - row))
            }
        }
    }
    
    var piecesView: some View {
        ZStack {
            ForEach(0..<64, id: \.self) { index in
                let row = index % 8
                let column = index / 8
                let piece = chessboardModel.game.position.board[index]
                
                let isMoving = chessboardModel.movingPiece?.from == BoardSquare(row: row, column: column) ||
                               chessboardModel.movingPiece?.to == BoardSquare(row: row, column: column)
                
                ChessPieceView(animation: animation,
                               piece: piece,
                               square: BoardSquare(row: row, column: column))
                .opacity(isMoving ? 0.0 : 1.0)
                .animation(nil, value: isMoving)
                .position(x: chessboardModel.size / 16 + chessboardModel.size / 8 * CGFloat(chessboardModel.shouldFlipBoard ? 7 - column : column),
                          y: chessboardModel.size / 16 + chessboardModel.size / 8 * CGFloat(chessboardModel.shouldFlipBoard ? row : 7 - row))
            }
        }
    }
    
    var legalMoveHighlightsView: some View {
        ZStack {
            ForEach(Array(chessboardModel.legalMoveSquares), id: \.id) { square in
                Circle()
                    .fill(chessboardModel.colorScheme.legalMove)
                    .frame(width: chessboardModel.size / 24, height: chessboardModel.size / 24)
                    .position(x: chessboardModel.size / 16 + chessboardModel.size / 8 * CGFloat(chessboardModel.shouldFlipBoard ? 7 - square.column : square.column),
                              y: chessboardModel.size / 16 + chessboardModel.size / 8 * CGFloat(chessboardModel.shouldFlipBoard ? square.row : 7 - square.row))
            }
        }
        .allowsHitTesting(false)
    }
    
    public func onMove(_ callback: @escaping (Move, Bool, String, String, String, PieceKind?) -> Void) -> Chessboard {
        chessboardModel.onMove = callback
        return self
    }
}

private struct ChessSquareView: View {
    @Environment(ChessboardModel.self) var chessboardModel
    
    var piece: Piece?
    var row: Int
    var column: Int
    
    @State var offset: CGSize = .zero
    @State var isDragging: Bool = false
    
    var zIndex: Double { isDragging ? 1: 0 }
    
    var isSelected: Bool {
        if let selectedSquare = chessboardModel.selectedSquare {
            return selectedSquare.row == row && selectedSquare.column == column
        }
        return false
    }
    
    var isHinted: Bool {
        chessboardModel.hintedSquares.contains { $0.row == row && $0.column == column }
    }
    
    var x: CGFloat {
        chessboardModel.size / 16 + chessboardModel.size / 8 * CGFloat(chessboardModel.shouldFlipBoard ? 7 - column : column)
    }
    
    var y: CGFloat {
        chessboardModel.size / 16 + chessboardModel.size / 8 * CGFloat(chessboardModel.shouldFlipBoard ? row : 7 - row)
    }
    
    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
        }
        .font(.system(size: chessboardModel.size / 8 * 0.75))
        .frame(width: chessboardModel.size / 8, height: chessboardModel.size / 8)
        .modifier {
            if let dropTarget = chessboardModel.dropTarget,
               !isDragging &&
                dropTarget.row == row && dropTarget.column == column
            {
                $0.overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(chessboardModel.colorScheme.selected, lineWidth: 3.5)
                }
            } else if isSelected {
                $0.overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(chessboardModel.colorScheme.selected, lineWidth: 3.5)
                }
            } else if isHinted {
                $0.overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(chessboardModel.colorScheme.hinted, lineWidth: 3.5)
                }
            } else { $0 }
        }
    }
}

private struct ChessPieceView: View {
    @Environment(ChessboardModel.self) var chessboardModel
    
    var animation: Namespace.ID
    
    var piece: Piece?
    var square: BoardSquare
    var isMovingPiece = false
    
    @State var offset: CGSize = .zero
    @State var isDragging = false
    
    var zIndex: Double { isDragging ? 1: 0 }
    
    var isSelected: Bool {
        if let selectedSquare = chessboardModel.selectedSquare {
            return selectedSquare.row == square.row && selectedSquare.column == square.column
        }
        return false
    }
    
    var isHinted: Bool {
        chessboardModel.hintedSquares.contains { $0.row == square.row && $0.column == square.column }
    }
    
    var x: CGFloat {
        chessboardModel.size / 16 + chessboardModel.size / 8 * CGFloat(chessboardModel.shouldFlipBoard ? 7 - square.column : square.column)
    }
    
    var y: CGFloat {
        chessboardModel.size / 16 + chessboardModel.size / 8 * CGFloat(chessboardModel.shouldFlipBoard ? square.row : 7 - square.row)
    }
    
    var isMoving: Bool {
        piece == chessboardModel.movingPiece?.piece && square == chessboardModel.movingPiece?.from
    }
    
    var body: some View {
        ZStack {
            if let piece {
                let imageName = "\(piece.color == PieceColor.white ? "w" : "b")\(String(describing: piece).uppercased())"

                if let image = Self.loadPieceImage(named: imageName, folder: chessboardModel.pieceStyleFolder) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(0.85)
                        .contentShape(Rectangle())
                } else {
                    Text("\(piece)")
                        .foregroundStyle(piece.color == PieceColor.white ? Color.white : Color.black)
                        .font(.system(size: 18))
                        .scaledToFit()
                        .scaleEffect(0.85)
                        .contentShape(Rectangle())
                }
            } else {
                Color.clear.contentShape(Rectangle())
            }
        }
        .zIndex(zIndex)
        .font(.system(size: chessboardModel.size / 8 * 0.75))
        .frame(width: chessboardModel.size / 8, height: chessboardModel.size / 8)
        .offset(offset)
        .onTapGesture(perform: onTapGesture)
        .gesture(dragGesture)
    }
    
    /// Load a piece image from the bundle for the given style folder.
    static func loadPieceImage(named imageName: String, folder: String = "uscf") -> UIImage? {
        // .copy() resources: folder is a directory in the bundle
        if let url = Bundle.module.url(forResource: imageName, withExtension: "png", subdirectory: folder),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        // Fallback: try without subdirectory (legacy .process() layout)
        if let url = Bundle.module.url(forResource: imageName, withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        // Fallback: asset catalog
        if let image = UIImage(named: imageName, in: .module, compatibleWith: nil) {
            return image
        }
        return nil
    }

    func onTapGesture() {
        if chessboardModel.movingPiece != nil {
            return
        }
        
        if let piece, piece.color != chessboardModel.turn && chessboardModel.selectedSquare == nil {
            return
        }
        
        if isSelected {
            chessboardModel.selectedSquare = nil
            chessboardModel.clearLegalMoveHighlights()
        } else if piece != nil && chessboardModel.selectedSquare == nil {
            chessboardModel.selectedSquare = isSelected ? nil: BoardSquare(row: square.row, column: square.column)
            if chessboardModel.selectedSquare != nil {
                chessboardModel.updateLegalMoveHighlights(for: BoardSquare(row: square.row, column: square.column))
            }
        } else if let selectedSquare = chessboardModel.selectedSquare {
            let sourceRow = selectedSquare.row
            let sourceColumn = selectedSquare.column
            
            let sourceSquare = "\(Character(UnicodeScalar(sourceColumn + 97)!))\(sourceRow + 1)"
            let targetSquare = "\(Character(UnicodeScalar(square.column + 97)!))\(square.row + 1)"
            
            let lan = "\(sourceSquare)\(targetSquare)"
            let move = Move(string: lan)
            let isLegal = chessboardModel.game.legalMoves.contains(move)
            
            chessboardModel.deselect()
            chessboardModel.clearLegalMoveHighlights()
            
            guard let selectedPiece = chessboardModel.game.position.board[selectedSquare.row + selectedSquare.column * 8]
            else { return }
            
            let isPromotable = chessboardModel.isPromotable(piece: selectedPiece, lan: lan)
            
            if !isPromotable {
                if !chessboardModel.validateMoves || isLegal {
                    chessboardModel.onMove(move, isLegal, sourceSquare, targetSquare, lan, nil)
                }
            } else if ((["q", "r", "b", "n"].map { lan + $0.uppercased() }).contains { promotedLan in
                return chessboardModel.game.legalMoves.contains(Move(string: promotedLan))
            }) {
                chessboardModel.presentPromotionPicker(piece: selectedPiece,
                                                       sourceSquare: sourceSquare,
                                                       targetSquare: targetSquare,
                                                       lan: lan)
            } else if !chessboardModel.validateMoves || isLegal {
                chessboardModel.onMove(move, isLegal, sourceSquare, targetSquare, lan, nil)
            }
        }
    }
    
    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if chessboardModel.movingPiece != nil {
                    return
                }
                
                if chessboardModel.selectedSquare != nil {
                    chessboardModel.deselect()
                }
                
                if let piece, piece.color != chessboardModel.turn,
                   !chessboardModel.allowOpponentMove && piece.color != chessboardModel.perspective
                {
                    chessboardModel.selectedSquare = nil
                    isDragging = false
                    chessboardModel.clearLegalMoveHighlights()
                    return
                }
                
                chessboardModel.selectedSquare = nil
                
                if !isDragging {
                    chessboardModel.updateLegalMoveHighlights(for: BoardSquare(row: square.row, column: square.column))
                }
                
                isDragging = true
                
                let squareSize = chessboardModel.size / 8
                let columnOffset = Int(round(value.translation.width / squareSize))
                let rowOffset = Int(round(value.translation.height / squareSize))
                
                let targetColumn = chessboardModel.shouldFlipBoard ? square.column - columnOffset : square.column + columnOffset
                let targetRow = chessboardModel.shouldFlipBoard ? square.row + rowOffset : square.row - rowOffset
                
                chessboardModel.dropTarget = (targetRow, targetColumn)
                offset = value.translation
            }
            .onEnded { value in
                chessboardModel.selectedSquare = nil
                chessboardModel.dropTarget = nil
                isDragging = false
                chessboardModel.clearLegalMoveHighlights()
                
                if let piece, piece.color != chessboardModel.turn,
                   !chessboardModel.allowOpponentMove && piece.color != chessboardModel.perspective {
                    withAnimation {
                        offset = .zero
                    }
                    return
                }
                
                let squareSize = chessboardModel.size / 8
                let columnOffset = Int(round(value.translation.width / squareSize))
                let rowOffset = Int(round(value.translation.height / squareSize))
                
                let targetColumn = chessboardModel.shouldFlipBoard ? square.column - columnOffset : square.column + columnOffset
                let targetRow = chessboardModel.shouldFlipBoard ? square.row + rowOffset : square.row - rowOffset
                
                let sourceSquare = "\(Character(UnicodeScalar(square.column + 97)!))\(square.row + 1)"
                let targetSquare = "\(Character(UnicodeScalar(targetColumn + 97)!))\(targetRow + 1)"
                
                let lan = "\(sourceSquare)\(targetSquare)"
                let move = Move(string: lan)
                let isLegal = chessboardModel.game.legalMoves.contains(move)
                
                withAnimation {
                    offset = .zero
                }
                
                guard let selectedPiece = chessboardModel.game.position.board[square.row + square.column * 8]
                else { return }
                
                let isPromotable = chessboardModel.isPromotable(piece: selectedPiece, lan: lan)
                
                if !isPromotable {
                    if !chessboardModel.validateMoves || isLegal {
                        chessboardModel.onMove(move, isLegal, sourceSquare, targetSquare, lan, nil)
                    }
                } else if ((["q", "r", "b", "n"].map { lan + $0.uppercased() }).contains { promotedLan in
                    return chessboardModel.game.legalMoves.contains(Move(string: promotedLan))
                }) {
                    chessboardModel.presentPromotionPicker(piece: selectedPiece,
                                                           sourceSquare: sourceSquare,
                                                           targetSquare: targetSquare,
                                                           lan: lan)
                } else if !chessboardModel.validateMoves || chessboardModel.game.legalMoves.contains(move) {
                    chessboardModel.onMove(move, isLegal, sourceSquare, targetSquare, lan, nil)
                }
            }
    }
}

public extension View {
    func modifier<ModifiedContent: View>(@ViewBuilder content: (_ content: Self) -> ModifiedContent) -> ModifiedContent {
        content(self)
    }
}
