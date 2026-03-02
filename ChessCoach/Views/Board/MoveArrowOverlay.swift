import SwiftUI

/// Draws a semi-transparent arrow from one square to another on the chessboard.
/// Uses a SwiftUI Shape with trim animation for a draw-in effect.
struct MoveArrowOverlay: View {
    let arrowFrom: String?  // algebraic e.g. "c1"
    let arrowTo: String?    // algebraic e.g. "f4"
    let boardSize: CGFloat
    let perspective: Bool   // true = white on bottom

    // Ghost piece animation (improvement 8)
    let ghostFrom: String?
    let ghostTo: String?
    let ghostOpacity: Double

    @State private var drawProgress: CGFloat = 0

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
        Group {
            if let from = arrowFrom, let to = arrowTo {
                ArrowShape(
                    from: from,
                    to: to,
                    boardSize: boardSize,
                    perspective: perspective
                )
                .trim(from: 0, to: drawProgress)
                .stroke(AppColor.arrowSuggestion, style: StrokeStyle(lineWidth: boardSize / 28, lineCap: .round))
                .onAppear {
                    drawProgress = 0
                    withAnimation(.easeOut(duration: 0.3)) {
                        drawProgress = 1
                    }
                }
                .onChange(of: from + to) {
                    drawProgress = 0
                    withAnimation(.easeOut(duration: 0.3)) {
                        drawProgress = 1
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .frame(width: boardSize, height: boardSize)
    }
}

/// A Shape that draws an arrow with shaft and arrowhead between two chess squares.
private struct ArrowShape: Shape {
    let from: String
    let to: String
    let boardSize: CGFloat
    let perspective: Bool

    func path(in rect: CGRect) -> Path {
        guard let fromPoint = squareCenter(from, in: rect.size),
              let toPoint = squareCenter(to, in: rect.size) else {
            return Path()
        }

        var path = Path()
        let angle = atan2(toPoint.y - fromPoint.y, toPoint.x - fromPoint.x)
        let headLength: CGFloat = rect.width / 10
        let headAngle: CGFloat = .pi / 5

        // Shorten shaft so it stops at the base of the arrowhead
        let shaftEnd = CGPoint(
            x: toPoint.x - headLength * 0.7 * cos(angle),
            y: toPoint.y - headLength * 0.7 * sin(angle)
        )

        // Arrow shaft
        path.move(to: fromPoint)
        path.addLine(to: shaftEnd)

        // Arrowhead (two strokes from tip to wings)
        path.move(to: toPoint)
        path.addLine(to: CGPoint(
            x: toPoint.x - headLength * cos(angle - headAngle),
            y: toPoint.y - headLength * sin(angle - headAngle)
        ))
        path.move(to: toPoint)
        path.addLine(to: CGPoint(
            x: toPoint.x - headLength * cos(angle + headAngle),
            y: toPoint.y - headLength * sin(angle + headAngle)
        ))

        return path
    }

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
            x = (CGFloat(file) + 0.5) * squareSize
            y = (CGFloat(7 - rank) + 0.5) * squareSize
        } else {
            x = (CGFloat(7 - file) + 0.5) * squareSize
            y = (CGFloat(rank) + 0.5) * squareSize
        }

        return CGPoint(x: x, y: y)
    }
}
