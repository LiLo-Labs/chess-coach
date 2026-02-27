import SwiftUI
import ChessKit

/// Inline quiz card with a chess board + multiple-choice question.
/// Used in Layer 1 and Layer 3 lesson flows.
struct QuizLessonCard: View {
    let quiz: LessonQuiz
    let perspective: Bool  // true = white on bottom
    let onAnswered: (Bool) -> Void  // called with true if correct

    @State private var selectedIndex: Int?
    @State private var revealed = false

    private var showOverlays: Bool { revealed }

    var body: some View {
        VStack(spacing: 12) {
            // Board
            GeometryReader { geo in
                let boardSize = min(geo.size.width - 32, 280)
                ZStack {
                    boardView(size: boardSize)

                    if showOverlays && !quiz.boardHighlightsOnReveal.isEmpty {
                        SquareHighlightOverlay(
                            squares: quiz.boardHighlightsOnReveal,
                            color: .blue,
                            boardSize: boardSize,
                            perspective: perspective
                        )
                    }

                    if showOverlays && !quiz.arrowsOnReveal.isEmpty {
                        MultiArrowOverlay(
                            arrows: quiz.arrowsOnReveal.map { ($0.from, $0.to) },
                            color: .blue.opacity(0.7),
                            boardSize: boardSize,
                            perspective: perspective
                        )
                    }
                }
                .frame(width: boardSize, height: boardSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.purple.opacity(0.5), lineWidth: 2)
                )
                .frame(maxWidth: .infinity)
            }
            .frame(height: 280)

            // Quiz badge
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
                Text("Quiz")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.purple)

            // Prompt
            Text(quiz.prompt)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            // Choices
            VStack(spacing: 8) {
                ForEach(Array(quiz.choices.enumerated()), id: \.offset) { index, choice in
                    choiceButton(index: index, choice: choice)
                }
            }
            .padding(.horizontal, 16)

            // Explanation (after reveal)
            if revealed {
                let wasCorrect = selectedIndex == quiz.correctIndex
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(wasCorrect ? .green : .red)
                        Text(wasCorrect ? "Correct!" : "Not quite")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(quiz.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func choiceButton(index: Int, choice: QuizChoice) -> some View {
        Button {
            guard !revealed else { return }
            selectedIndex = index
            withAnimation(.easeInOut(duration: 0.3)) {
                revealed = true
            }
            onAnswered(choice.isCorrect)
        } label: {
            HStack {
                Text(choice.text)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Spacer()

                if revealed {
                    if choice.isCorrect {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if index == selectedIndex {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(choiceBackground(index: index, isCorrect: choice.isCorrect))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(revealed)
    }

    private func choiceBackground(index: Int, isCorrect: Bool) -> some ShapeStyle {
        if revealed {
            if isCorrect {
                return AnyShapeStyle(.green.opacity(0.15))
            } else if index == selectedIndex {
                return AnyShapeStyle(.red.opacity(0.15))
            }
        }
        if index == selectedIndex && !revealed {
            return AnyShapeStyle(.blue.opacity(0.15))
        }
        return AnyShapeStyle(.secondary.opacity(0.1))
    }

    @ViewBuilder
    private func boardView(size: CGFloat) -> some View {
        let gameState = GameState(fen: quiz.fen)
        let pieceColor: PieceColor = perspective ? .white : .black
        GameBoardView(gameState: gameState, perspective: pieceColor, allowInteraction: false)
            .frame(width: size, height: size)
    }
}
