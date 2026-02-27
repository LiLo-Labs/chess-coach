import SwiftUI

/// Draws semi-transparent circles on highlighted squares of the chessboard.
struct SquareHighlightOverlay: View {
    let squares: [String]
    let color: Color
    let boardSize: CGFloat
    let perspective: Bool   // true = white on bottom

    var body: some View {
        Canvas { context, size in
            let squareSize = size.width / 8
            let circleInset: CGFloat = squareSize * 0.1

            for square in squares {
                guard let center = squareCenter(square, in: size) else { continue }

                let rect = CGRect(
                    x: center.x - squareSize / 2 + circleInset,
                    y: center.y - squareSize / 2 + circleInset,
                    width: squareSize - circleInset * 2,
                    height: squareSize - circleInset * 2
                )
                let circle = Path(ellipseIn: rect)
                context.fill(circle, with: .color(color.opacity(0.35)))
                context.stroke(circle, with: .color(color.opacity(0.7)), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .frame(width: boardSize, height: boardSize)
    }

    /// Convert algebraic coordinate (e.g. "e4") to pixel center on board.
    private func squareCenter(_ coord: String, in size: CGSize) -> CGPoint? {
        guard coord.count == 2,
              let fileChar = coord.first,
              let rankChar = coord.last,
              let file = fileChar.asciiValue.map({ Int($0) - Int(Character("a").asciiValue!) }),
              let rank = Int(String(rankChar)).map({ $0 - 1 }),
              (0..<8).contains(file), (0..<8).contains(rank) else {
            return nil
        }

        let squareSize = size.width / 8
        if perspective {
            return CGPoint(x: (CGFloat(file) + 0.5) * squareSize, y: (CGFloat(7 - rank) + 0.5) * squareSize)
        } else {
            return CGPoint(x: (CGFloat(7 - file) + 0.5) * squareSize, y: (CGFloat(rank) + 0.5) * squareSize)
        }
    }
}
