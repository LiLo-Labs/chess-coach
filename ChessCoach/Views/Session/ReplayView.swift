import SwiftUI
import ChessKit

/// Post-session replay with slider and coaching history (improvement 5).
struct ReplayView: View {
    let opening: Opening
    let moveHistory: [(from: String, to: String)]
    let coachingHistory: [(ply: Int, text: String)]
    let activeMoves: [OpeningMove]

    @State private var currentPly: Double = 0
    @State private var replayState = GameState()
    @Environment(\.dismiss) private var dismiss

    private var plyInt: Int { Int(currentPly) }

    /// Full move number label for a given ply index (1-based, white/black notation).
    private func moveLabel(for plyIndex: Int) -> String {
        let moveNum = plyIndex / 2 + 1
        let isWhite = plyIndex % 2 == 0
        return isWhite ? "\(moveNum)." : "\(moveNum)..."
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppColor.secondaryText)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Game Review")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)

                Spacer()

                // Move number label showing full notation
                Text(plyInt > 0 ? moveLabel(for: plyInt - 1) : "Start")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(AppColor.secondaryText)
                    .frame(minWidth: 40, alignment: .trailing)
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.vertical, AppSpacing.md)

            // Board
            GameBoardView(
                gameState: replayState,
                perspective: opening.color == .white ? .white : .black,
                allowInteraction: false
            )
            .aspectRatio(1, contentMode: .fit)

            // Move slider section
            VStack(spacing: AppSpacing.sm) {
                // Dot annotation row showing quality per move
                if !moveHistory.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppSpacing.xxs) {
                            ForEach(0..<moveHistory.count, id: \.self) { i in
                                let isCorrect: Bool = {
                                    guard i < activeMoves.count else { return false }
                                    return activeMoves[i].uci == moveHistory[i].from + moveHistory[i].to
                                }()
                                let isUserMove = opening.color == .white ? i % 2 == 0 : i % 2 == 1
                                let isPast = i < plyInt

                                if isUserMove {
                                    // User moves get quality annotation icons
                                    Image(
                                        systemName: isCorrect
                                            ? "checkmark.circle.fill"
                                            : "exclamationmark.triangle.fill"
                                    )
                                    .font(.system(size: 8))
                                    .foregroundStyle(
                                        isCorrect
                                            ? (isPast ? AppColor.success : AppColor.success.opacity(0.4))
                                            : (isPast ? AppColor.warning : AppColor.warning.opacity(0.4))
                                    )
                                } else {
                                    // Opponent moves shown as simple dots
                                    Circle()
                                        .fill(isPast
                                              ? AppColor.tertiaryText
                                              : AppColor.tertiaryText.opacity(0.3))
                                        .frame(width: 5, height: 5)
                                }
                            }
                        }
                        .padding(.horizontal, AppSpacing.screenPadding)
                    }
                }

                // Slider with move number labels
                VStack(spacing: AppSpacing.xxs) {
                    Slider(value: $currentPly, in: 0...Double(max(1, moveHistory.count)), step: 1)
                        .tint(AppColor.guided)
                        .padding(.horizontal, AppSpacing.screenPadding)

                    HStack {
                        Text("Start")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(AppColor.tertiaryText)
                        Spacer()
                        Text("Move \(moveHistory.count / 2)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(AppColor.tertiaryText)
                    }
                    .padding(.horizontal, AppSpacing.screenPadding + AppSpacing.sm)
                }
            }
            .padding(.vertical, AppSpacing.sm)

            // Move annotation and coaching text at current ply
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    if plyInt > 0, plyInt - 1 < activeMoves.count {
                        let move = activeMoves[plyInt - 1]
                        let played = plyInt - 1 < moveHistory.count
                            ? moveHistory[plyInt - 1].from + moveHistory[plyInt - 1].to
                            : "?"
                        let isCorrect = move.uci == played

                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: isCorrect
                                  ? "checkmark.circle.fill"
                                  : "exclamationmark.circle.fill")
                                .foregroundStyle(isCorrect ? AppColor.success : AppColor.warning)
                            Text(isCorrect
                                 ? "Correct: \(move.san)"
                                 : "Played \(played), book is \(move.san)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppColor.primaryText)
                        }

                        if !move.explanation.isEmpty {
                            Text(move.explanation)
                                .font(.footnote)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                    }

                    // Coaching from the session
                    if let coaching = coachingHistory.first(where: { $0.ply == plyInt }) {
                        Text(coaching.text)
                            .font(.subheadline)
                            .foregroundStyle(AppColor.primaryText.opacity(0.8))
                            .padding(AppSpacing.sm + AppSpacing.xxs)
                            .background(
                                AppColor.guided.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: AppRadius.sm)
                            )
                    }
                }
                .padding(.horizontal, AppSpacing.screenPadding)
                .padding(.vertical, AppSpacing.sm)
            }

            Spacer()
        }
        .background(AppColor.background)
        .preferredColorScheme(.dark)
        .onChange(of: currentPly) { _, _ in
            syncReplayState()
        }
    }

    private func syncReplayState() {
        replayState.reset()
        for i in 0..<plyInt {
            guard i < moveHistory.count else { break }
            _ = replayState.makeMoveUCI(moveHistory[i].from + moveHistory[i].to)
        }
    }
}
