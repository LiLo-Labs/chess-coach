import SwiftUI

/// Draws multiple semi-transparent arrows on the chessboard.
/// Reuses the same shaft+arrowhead drawing logic as MoveArrowOverlay.
struct MultiArrowOverlay: View {
    let arrows: [(from: String, to: String)]
    let color: Color
    let boardSize: CGFloat
    let perspective: Bool   // true = white on bottom

    var body: some View {
        Canvas { context, size in
            let lineWidth: CGFloat = size.width / 28
            let headLength: CGFloat = size.width / 10
            let headAngle: CGFloat = .pi / 5

            for arrow in arrows {
                guard let fromPoint = squareCenter(arrow.from, in: size),
                      let toPoint = squareCenter(arrow.to, in: size) else { continue }

                let angle = atan2(toPoint.y - fromPoint.y, toPoint.x - fromPoint.x)

                // Shorten shaft so it stops at the base of the arrowhead
                let shaftEnd = CGPoint(
                    x: toPoint.x - headLength * 0.7 * cos(angle),
                    y: toPoint.y - headLength * 0.7 * sin(angle)
                )

                // Shaft
                var path = Path()
                path.move(to: fromPoint)
                path.addLine(to: shaftEnd)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                // Arrowhead
                var headPath = Path()
                headPath.move(to: toPoint)
                headPath.addLine(to: CGPoint(
                    x: toPoint.x - headLength * cos(angle - headAngle),
                    y: toPoint.y - headLength * sin(angle - headAngle)
                ))
                headPath.addLine(to: CGPoint(
                    x: toPoint.x - headLength * cos(angle + headAngle),
                    y: toPoint.y - headLength * sin(angle + headAngle)
                ))
                headPath.closeSubpath()
                context.fill(headPath, with: .color(color))
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
