import SwiftUI
import ChessKit

/// Stage 1: Read through the full line with explanations before playing a single move.
/// Auto-play moves at intervals, with manual Next/Back buttons for stepping through.
struct LineStudyView: View {
    let opening: Opening
    let line: OpeningLine
    let isPro: Bool
    let onStartPracticing: () -> Void

    @State private var currentPly: Int = 0
    @State private var isAutoPlaying: Bool = true
    @State private var autoPlayTask: Task<Void, Never>?
    @State private var gameState = GameState()
    @State private var showChat = false
    @State private var showProUpgrade = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    private var moves: [OpeningMove] { line.moves }
    private var isAtEnd: Bool { currentPly >= moves.count }
    private var isAtStart: Bool { currentPly == 0 }

    /// Arrow overlay data for the current move
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

    var body: some View {
        GeometryReader { geo in
            let evalWidth: CGFloat = 0
            let boardSize = max(1, geo.size.width - evalWidth)

            VStack(spacing: 0) {
                topBar

                // Board with arrow overlay
                ZStack {
                    GameBoardView(
                        gameState: gameState,
                        perspective: opening.color == .white ? PieceColor.white : PieceColor.black,
                        allowInteraction: false
                    ) { _, _ in }

                    MoveArrowOverlay(
                        arrowFrom: arrowFrom,
                        arrowTo: arrowTo,
                        boardSize: boardSize,
                        perspective: opening.color == .white
                    )
                }
                .frame(width: boardSize, height: boardSize)

                // Move info area
                moveInfoSection

                Spacer()

                // Controls
                controlBar

                // Start Practicing button
                Button(action: onStartPracticing) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "play.fill")
                            .font(.subheadline)
                        Text("Start Practicing")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(AppColor.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.success, in: RoundedRectangle(cornerRadius: AppRadius.lg))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start practicing this line")
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.xl)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(AppColor.background)
        .preferredColorScheme(.dark)
        .onAppear {
            startAutoPlay()
        }
        .onDisappear {
            stopAutoPlay()
        }
        .sheet(isPresented: $showChat) {
            if isPro {
                LineChatView(
                    opening: opening,
                    line: line,
                    fen: gameState.fen,
                    currentPly: currentPly,
                    moveHistory: gameState.moveHistory.map { $0.from + $0.to }
                )
            }
        }
        .sheet(isPresented: $showProUpgrade) {
            ProUpgradeView()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                stopAutoPlay()
                dismiss()
            } label: {
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                    Text("Back")
                        .font(.subheadline)
                }
                .foregroundStyle(AppColor.secondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous move")

            Spacer()

            VStack(spacing: AppSpacing.xxxs) {
                Text(opening.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.primaryText)
                Text(line.name)
                    .font(.caption2)
                    .foregroundStyle(AppColor.secondaryText)
            }

            Spacer()

            // Pro chat button with tooltip hint
            ZStack(alignment: .bottomTrailing) {
                Button {
                    if isPro {
                        pauseAutoPlay()
                        showChat = true
                    } else {
                        showProUpgrade = true
                    }
                } label: {
                    HStack(spacing: AppSpacing.xxs) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 14))
                        if !isPro {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(AppColor.gold)
                        }
                    }
                    .foregroundStyle(isPro ? AppColor.guided : AppColor.secondaryText)
                    .padding(AppSpacing.sm)
                    .background(AppColor.primaryText.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ask coach a question" + (isPro ? "" : ", requires Pro"))

                // Tooltip suggestion
                Text("Ask why this move?")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppColor.primaryText)
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.vertical, AppSpacing.xxxs)
                    .background(AppColor.guided.opacity(0.85), in: Capsule())
                    .offset(x: 0, y: AppSpacing.lg + AppSpacing.xxs)
                    .opacity(isPro && currentPly > 0 && !isAutoPlaying ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: isAutoPlaying)
            }
        }
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.top, AppSpacing.topBarSafeArea)
        .padding(.bottom, AppSpacing.sm)
    }

    // MARK: - Move Info

    private var moveInfoSection: some View {
        VStack(spacing: AppSpacing.md) {
            // Header row: move counter + mode badge
            HStack(spacing: AppSpacing.xxs) {
                Text("Move \(currentPly)/\(moves.count)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(AppColor.secondaryText)

                Spacer()

                ModeIndicator(mode: "Study", color: AppColor.study)
            }
            .padding(.horizontal, AppSpacing.xl)

            // Progress bar showing position in the line
            if moves.count > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppColor.cardBackground)
                            .frame(height: 3)

                        Capsule()
                            .fill(AppColor.study)
                            .frame(
                                width: geo.size.width * CGFloat(currentPly) / CGFloat(moves.count),
                                height: 3
                            )
                            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentPly)
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, AppSpacing.xl)
            }

            // Current move info card
            if currentPly > 0, currentPly <= moves.count {
                let move = moves[currentPly - 1]
                let moveNum = (currentPly - 1) / 2 + 1
                let isWhite = (currentPly - 1) % 2 == 0

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.sm) {
                        Text(isWhite ? "\(moveNum)." : "\(moveNum)...")
                            .font(.subheadline.monospacedDigit().weight(.medium))
                            .foregroundStyle(AppColor.secondaryText)
                        Text(move.san)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppColor.primaryText)
                        Circle()
                            .fill(isWhite ? AppColor.primaryText : AppColor.cardBackground)
                            .frame(width: 10, height: 10)
                        Spacer()
                    }

                    if !move.explanation.isEmpty {
                        Text(move.explanation)
                            .font(.subheadline)
                            .foregroundStyle(AppColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(AppSpacing.cardPadding)
                .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.md))
                .padding(.horizontal, AppSpacing.screenPadding)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentPly)
            } else if currentPly == 0 {
                VStack(spacing: AppSpacing.xs) {
                    Text("Starting Position")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColor.primaryText)
                    Text("Watch the line play through, or use the controls below to step through at your own pace.")
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(AppSpacing.cardPadding)
                .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.md))
                .padding(.horizontal, AppSpacing.screenPadding)
            } else {
                VStack(spacing: AppSpacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppColor.success)
                    Text("Line complete!")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColor.success)
                    Text("You've seen all \(moves.count) moves. Ready to practice?")
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                .padding(AppSpacing.cardPadding)
                .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.md))
                .padding(.horizontal, AppSpacing.screenPadding)
            }
        }
        .padding(.top, AppSpacing.md)
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        VStack(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xxl) {
                // Back button
                Button {
                    pauseAutoPlay()
                    goBack()
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 36))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isAtStart ? AppColor.primaryText.opacity(0.2) : AppColor.primaryText.opacity(0.7))
                }
                .buttonStyle(.plain)
                .disabled(isAtStart)
                .accessibilityLabel("Previous move")

                // Play/Pause button
                Button {
                    if isAutoPlaying {
                        pauseAutoPlay()
                    } else {
                        startAutoPlay()
                    }
                } label: {
                    Image(systemName: isAutoPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 48))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(AppColor.primaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isAutoPlaying ? "Pause auto-play" : "Resume auto-play")

                // Next button
                Button {
                    pauseAutoPlay()
                    goForward()
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 36))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isAtEnd ? AppColor.primaryText.opacity(0.2) : AppColor.primaryText.opacity(0.7))
                }
                .buttonStyle(.plain)
                .disabled(isAtEnd)
                .accessibilityLabel("Next move")
            }

            // Speed control row
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "hare.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColor.tertiaryText)

                speedButton(label: "1s", value: 1.0)
                speedButton(label: "2s", value: 2.0)
                speedButton(label: "3s", value: 3.0)
                speedButton(label: "5s", value: 5.0)

                Image(systemName: "tortoise.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColor.tertiaryText)
            }
        }
        .padding(.vertical, AppSpacing.screenPadding)
    }

    private func speedButton(label: String, value: Double) -> some View {
        let isSelected = abs(settings.autoPlaySpeed - value) < 0.1
        return Button {
            settings.autoPlaySpeed = value
            // Restart auto-play at new speed if playing
            if isAutoPlaying {
                pauseAutoPlay()
                startAutoPlay()
            }
        } label: {
            Text(label)
                .font(.caption2.weight(isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? AppColor.primaryText : AppColor.tertiaryText)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, AppSpacing.xxxs)
                .background(isSelected ? AppColor.study.opacity(0.25) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Auto-play speed \(label)")
    }

    // MARK: - Navigation

    private func goForward() {
        guard currentPly < moves.count else { return }
        let move = moves[currentPly]
        _ = gameState.makeMoveUCI(move.uci)
        currentPly += 1
    }

    private func goBack() {
        guard currentPly > 0 else { return }
        gameState.undoLastMove()
        currentPly -= 1
    }

    // MARK: - Auto-play

    private func startAutoPlay() {
        guard !isAtEnd else { return }
        isAutoPlaying = true
        autoPlayTask = Task {
            while !Task.isCancelled && currentPly < moves.count {
                try? await Task.sleep(for: .seconds(settings.autoPlaySpeed))
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
