import SwiftUI

/// Draws a semi-transparent arrow from one square to another on the chessboard.
/// Uses Canvas for smooth rendering. Passes through all hit testing.
struct MoveArrowOverlay: View {
    let arrowFrom: String?  // algebraic e.g. "c1"
    let arrowTo: String?    // algebraic e.g. "f4"
    let boardSize: CGFloat
    let perspective: Bool   // true = white on bottom

    // Ghost piece animation (improvement 8)
    let ghostFrom: String?
    let ghostTo: String?
    let ghostOpacity: Double

    init(
        arrowFrom: String? = nil,
        arrowTo: String? = nil,
        boardSize: CGFloat,
        perspective: Bool = true,
        ghostFrom: String? = nil,
        ghostTo: String? = nil,
        ghostOpacity: Double = 0
    ) {
        self.arrowFrom = arrowFrom
        self.arrowTo = arrowTo
        self.boardSize = boardSize
        self.perspective = perspective
        self.ghostFrom = ghostFrom
        self.ghostTo = ghostTo
        self.ghostOpacity = ghostOpacity
    }

    var body: some View {
        Canvas { context, size in
            guard let from = arrowFrom, let to = arrowTo else { return }
            guard let fromPoint = squareCenter(from, in: size),
                  let toPoint = squareCenter(to, in: size) else { return }

            let arrowColor = AppColor.arrowSuggestion
            let lineWidth: CGFloat = size.width / 28
            let angle = atan2(toPoint.y - fromPoint.y, toPoint.x - fromPoint.x)
            let headLength: CGFloat = size.width / 10
            let headAngle: CGFloat = .pi / 5

            // Shorten shaft so it stops at the base of the arrowhead (no overlap)
            let shaftEnd = CGPoint(
                x: toPoint.x - headLength * 0.7 * cos(angle),
                y: toPoint.y - headLength * 0.7 * sin(angle)
            )

            // Draw arrow shaft
            var path = Path()
            path.move(to: fromPoint)
            path.addLine(to: shaftEnd)
            context.stroke(path, with: .color(arrowColor), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            // Draw arrowhead
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
            context.fill(headPath, with: .color(arrowColor))
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
        let x: CGFloat
        let y: CGFloat

        if perspective {
            // White on bottom: file left-to-right, rank bottom-to-top
            x = (CGFloat(file) + 0.5) * squareSize
            y = (CGFloat(7 - rank) + 0.5) * squareSize
        } else {
            // Black on bottom: file right-to-left, rank top-to-bottom
            x = (CGFloat(7 - file) + 0.5) * squareSize
            y = (CGFloat(rank) + 0.5) * squareSize
        }

        return CGPoint(x: x, y: y)
    }
}
