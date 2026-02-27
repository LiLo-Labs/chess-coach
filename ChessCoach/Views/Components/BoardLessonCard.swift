import SwiftUI
import ChessKit

/// A reusable card that shows a chess board with overlays + lesson text.
/// Used in both PlanUnderstandingView (Layer 1) and TheoryDiscoveryView (Layer 3).
struct BoardLessonCard: View {
    let step: LessonStep
    let perspective: Bool  // true = white on bottom

    private var styleColor: Color {
        switch step.style {
        case .good:    return .green
        case .bad:     return .red
        case .neutral: return .blue
        case .theory:  return .indigo
        }
    }

    private var styleBadge: (text: String, icon: String) {
        switch step.style {
        case .good:    return ("Do This", "checkmark.circle.fill")
        case .bad:     return ("Don't Do This", "xmark.circle.fill")
        case .neutral: return ("Key Idea", "info.circle.fill")
        case .theory:  return ("Theory", "book.circle.fill")
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Board with overlays
            GeometryReader { geo in
                let boardSize = min(geo.size.width - 32, 280)
                ZStack {
                    boardView(size: boardSize)

                    if !step.highlights.isEmpty {
                        SquareHighlightOverlay(
                            squares: step.highlights,
                            color: styleColor,
                            boardSize: boardSize,
                            perspective: perspective
                        )
                    }

                    if !step.arrows.isEmpty {
                        MultiArrowOverlay(
                            arrows: step.arrows.map { ($0.from, $0.to) },
                            color: styleColor.opacity(0.7),
                            boardSize: boardSize,
                            perspective: perspective
                        )
                    }
                }
                .frame(width: boardSize, height: boardSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(styleColor.opacity(0.5), lineWidth: 2)
                )
                .frame(maxWidth: .infinity)
            }
            .frame(height: 280)

            // Style badge
            HStack(spacing: 6) {
                Image(systemName: styleBadge.icon)
                Text(styleBadge.text)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(styleColor)

            // Title
            Text(step.title)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            // Description
            Text(step.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    /// Creates a non-interactive board from the step's FEN.
    @ViewBuilder
    private func boardView(size: CGFloat) -> some View {
        let gameState = GameState(fen: step.fen)
        let pieceColor: PieceColor = perspective ? .white : .black
        GameBoardView(gameState: gameState, perspective: pieceColor, allowInteraction: false)
            .frame(width: size, height: size)
    }
}
