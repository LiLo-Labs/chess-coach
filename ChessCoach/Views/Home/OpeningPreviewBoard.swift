import SwiftUI
import ChessKit

/// Compact animated board preview that auto-plays the opening's main line.
struct OpeningPreviewBoard: View {
    let opening: Opening

    @State private var gameState = GameState()
    @State private var currentPly: Int = 0
    @State private var isAutoPlaying = true
    @State private var autoPlayTask: Task<Void, Never>?
    @State private var isExpanded = true

    private var moves: [OpeningMove] { opening.mainLine }
    private var isAtEnd: Bool { currentPly >= moves.count }

    private var arrowFrom: String? {
        guard currentPly < moves.count else { return nil }
        let uci = moves[currentPly].uci
        guard uci.count >= 4 else { return nil }
        return String(uci.prefix(2))
    }

    private var arrowTo: String? {
        guard currentPly < moves.count else { return nil }
        let uci = moves[currentPly].uci
        guard uci.count >= 4 else { return nil }
        return String(uci.dropFirst(2).prefix(2))
    }

    /// Current move display text (stable layout — always reserves space)
    private var moveInfoText: (number: String, friendly: String, san: String, explanation: String) {
        guard currentPly > 0, currentPly <= moves.count else {
            return ("", "", "", "Starting position")
        }
        let move = moves[currentPly - 1]
        let moveNum = (currentPly - 1) / 2 + 1
        let isWhite = (currentPly - 1) % 2 == 0
        return (
            isWhite ? "\(moveNum)." : "\(moveNum)...",
            move.friendlyName,
            move.san,
            move.explanation
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Disclosure header
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                    if !isExpanded {
                        stopAutoPlay()
                    }
                }
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "eye")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.secondaryText)
                    Text("Preview")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.secondaryText)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColor.tertiaryText)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: AppSpacing.sm) {
                    // Board — fixed size, no GeometryReader shifting
                    let boardWidth = ((UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.width ?? 390) * 0.55

                    ZStack {
                        GameBoardView(
                            gameState: gameState,
                            perspective: opening.color == .white ? PieceColor.white : PieceColor.black,
                            allowInteraction: false
                        ) { _, _ in }

                        MoveArrowOverlay(
                            arrowFrom: arrowFrom,
                            arrowTo: arrowTo,
                            boardSize: boardWidth,
                            perspective: opening.color == .white
                        )
                    }
                    .frame(width: boardWidth, height: boardWidth)

                    // Move info — fixed height container so layout doesn't shift
                    VStack(spacing: AppSpacing.xxs) {
                        HStack(spacing: AppSpacing.xs) {
                            Text(moveInfoText.number)
                                .font(.caption.monospacedDigit().weight(.medium))
                                .foregroundStyle(AppColor.secondaryText)
                            Text(moveInfoText.friendly)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(AppColor.primaryText)
                            Text(moveInfoText.san)
                                .font(.caption2)
                                .foregroundStyle(AppColor.tertiaryText)
                        }
                        .opacity(currentPly > 0 ? 1 : 0)

                        Text(moveInfoText.explanation)
                            .font(.caption)
                            .foregroundStyle(AppColor.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(height: 32, alignment: .top)
                    }
                    .frame(height: 52)
                    .padding(.horizontal, AppSpacing.md)

                    // Play/pause + progress — fixed height
                    HStack(spacing: AppSpacing.md) {
                        Button {
                            if isAutoPlaying {
                                pauseAutoPlay()
                            } else {
                                if isAtEnd { restart() }
                                startAutoPlay()
                            }
                        } label: {
                            Image(systemName: isAutoPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 28))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(AppColor.primaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isAutoPlaying ? "Pause preview" : "Play preview")

                        ProgressView(value: Double(currentPly), total: Double(max(moves.count, 1)))
                            .tint(AppColor.study)

                        Text("\(currentPly)/\(moves.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(AppColor.tertiaryText)
                    }
                    .frame(height: 28)
                    .padding(.horizontal, AppSpacing.md)
                }
                .padding(.bottom, AppSpacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.md))
        .onAppear {
            startAutoPlay()
        }
        .onDisappear {
            stopAutoPlay()
        }
    }

    // MARK: - Playback

    private func goForward() {
        guard currentPly < moves.count else { return }
        let move = moves[currentPly]
        _ = gameState.makeMoveUCI(move.uci)
        currentPly += 1
    }

    private func restart() {
        gameState.reset()
        currentPly = 0
    }

    private func startAutoPlay() {
        guard !isAtEnd else { return }
        isAutoPlaying = true
        autoPlayTask = Task {
            while !Task.isCancelled && currentPly < moves.count {
                try? await Task.sleep(for: .seconds(2.0))
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    goForward()
                }
            }
            await MainActor.run {
                isAutoPlaying = false
            }
        }
    }

    private func pauseAutoPlay() {
        isAutoPlaying = false
        autoPlayTask?.cancel()
        autoPlayTask = nil
    }

    private func stopAutoPlay() {
        pauseAutoPlay()
    }
}
