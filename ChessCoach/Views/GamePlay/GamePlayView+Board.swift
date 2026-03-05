import SwiftUI
import ChessKit

/// Board area + eval bar for GamePlayView.
extension GamePlayView {

    @ViewBuilder
    func boardArea(boardSize: CGFloat, evalWidth: CGFloat) -> some View {
        HStack(spacing: 4) {
            if viewModel.mode.isSession {
                evalBar(height: boardSize)
                    .frame(width: evalWidth)
            }

            ZStack {
                GameBoardView(
                    gameState: viewModel.displayGameState,
                    perspective: viewModel.mode.playerColor,
                    allowInteraction: isPlayerTurn && !viewModel.isThinking && !viewModel.isGameOver && !viewModel.sessionComplete && !viewModel.isReplaying
                ) { from, to in
                    viewModel.clearArrowAndHint()
                    if viewModel.mode.isPuzzle {
                        viewModel.puzzleUserMoved(from: from, to: to)
                    } else if viewModel.mode.isTrainer {
                        viewModel.trainerUserMoved(from: from, to: to)
                    } else if viewModel.mode.sessionMode == .practice {
                        Task { await viewModel.practiceUserMoved(from: from, to: to) }
                    } else {
                        Task { await viewModel.sessionUserMoved(from: from, to: to) }
                    }
                }

                if viewModel.mode.showsArrows {
                    MoveArrowOverlay(
                        arrowFrom: viewModel.arrowFrom,
                        arrowTo: viewModel.arrowTo,
                        boardSize: boardSize,
                        perspective: viewModel.mode.playerColor == .white
                    )
                }
            }
            .frame(width: boardSize, height: boardSize)
        }
        .frame(height: boardSize)
    }

    private var isPlayerTurn: Bool {
        let playerColor = viewModel.mode.playerColor
        return (playerColor == .white && viewModel.gameState.isWhiteTurn) ||
               (playerColor == .black && !viewModel.gameState.isWhiteTurn)
    }

    // MARK: - Eval Bar

    func evalBar(height: CGFloat) -> some View {
        let fraction = viewModel.evalFraction
        let whiteRatio = CGFloat((1.0 + fraction) / 2.0)

        let evalAccessibilityLabel: String = {
            let score = viewModel.evalScore
            if abs(score) >= 10000 {
                return score > 0 ? "Position evaluation: White is winning by checkmate" : "Position evaluation: Black is winning by checkmate"
            } else if score > 50 {
                return "Position evaluation: White advantage"
            } else if score < -50 {
                return "Position evaluation: Black advantage"
            } else {
                return "Position evaluation: Equal"
            }
        }()

        return GeometryReader { _ in
            VStack(spacing: 0) {
                Color(white: 0.2)
                    .frame(height: height * (1 - whiteRatio))
                Color(white: 0.82)
                    .frame(height: height * whiteRatio)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .center) {
                Text(viewModel.evalText)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(whiteRatio > 0.5 ? Color(white: 0.2) : Color(white: 0.8))
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.7, dampingFraction: 0.65), value: viewModel.evalScore)
        .accessibilityLabel(evalAccessibilityLabel)
        .accessibilityValue(viewModel.evalText)
    }

    // MARK: - Progress Bar (Session)

    @ViewBuilder
    var progressBar: some View {
        let totalPlies = viewModel.activeLine?.moves.count ?? viewModel.mode.opening?.mainLine.count ?? 0
        let moveProgress: Double = totalPlies > 0 ? Double(viewModel.gameState.plyCount) / Double(totalPlies) : 0
        let phaseColor = AppColor.familiarityColor(progress: viewModel.familiarityProgress)

        ProgressView(value: moveProgress)
            .tint(phaseColor)
            .scaleEffect(y: 0.5)
            .padding(.horizontal, 16)
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: viewModel.gameState.plyCount)
    }
}
