import SwiftUI
import ChessKit

/// Stage 4: Practice Opening mode.
/// Throws everything at the user — opponent mixes up responses across all learned lines.
struct PracticeOpeningView: View {
    let opening: Opening
    let isPro: Bool

    @State private var viewModel: PracticeSessionViewModel
    @Environment(\.dismiss) private var dismiss

    init(opening: Opening, isPro: Bool = true, stockfish: StockfishService? = nil) {
        self.opening = opening
        self.isPro = isPro
        self._viewModel = State(initialValue: PracticeSessionViewModel(opening: opening, isPro: isPro, stockfish: stockfish))
    }

    var body: some View {
        GeometryReader { geo in
            let evalWidth: CGFloat = 12
            let evalGap: CGFloat = AppSpacing.xxs
            let boardSize = max(1, geo.size.width - evalWidth - evalGap)

            VStack(spacing: 0) {
                topBar

                // Line detection status bar
                lineStatusBar

                opponentBar

                // Eval bar + Board
                HStack(spacing: AppSpacing.xxs) {
                    evalBar(height: boardSize)
                        .frame(width: evalWidth)

                    GameBoardView(
                        gameState: viewModel.gameState,
                        perspective: opening.color == .white ? PieceColor.white : PieceColor.black,
                        allowInteraction: viewModel.isUserTurn && !viewModel.isThinking && !viewModel.sessionComplete
                    ) { from, to in
                        Task { await viewModel.userMoved(from: from, to: to) }
                    }
                    .frame(width: boardSize, height: boardSize)
                }
                .frame(height: boardSize)

                userBar

                // Info area
                ScrollView {
                    VStack(spacing: AppSpacing.sm) {
                        // Transition message
                        if let message = viewModel.lineTransitionMessage {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.footnote)
                                    .foregroundStyle(.teal)
                                Text(message)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.teal)
                                Spacer()
                            }
                            .padding(AppSpacing.md)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.md))
                            .padding(.horizontal, AppSpacing.md)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Practice mode info
                        if viewModel.stats.totalUserMoves == 0 {
                            VStack(spacing: AppSpacing.xs) {
                                Image(systemName: "target")
                                    .font(.title2)
                                    .foregroundStyle(AppColor.practice)
                                HStack(spacing: 4) {
                                    Text("Practice Mode")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppColor.practice)
                                    HelpButton(topic: .practiceMode)
                                }
                                Text("No hints — your opponent will surprise you with different responses. Show what you know!")
                                    .font(.caption)
                                    .foregroundStyle(AppColor.secondaryText)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(AppSpacing.cardPadding)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.md))
                            .padding(.horizontal, AppSpacing.md)
                        }
                    }
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.xl)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.lineTransitionMessage)
                }
                .scrollIndicators(.hidden)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(AppColor.background)
        .preferredColorScheme(.dark)
        .conceptIntro(.whatIsPractice)
        .overlay {
            if viewModel.sessionComplete {
                practiceCompleteOverlay
            }
        }
        .task {
            await viewModel.startSession()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                viewModel.endSession()
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
            .accessibilityLabel("Back to opening detail")

            Spacer()

            VStack(spacing: AppSpacing.xxxs) {
                Text(opening.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.primaryText)
                Text("Practice")
                    .font(.caption2)
                    .foregroundStyle(AppColor.practice)
            }

            Spacer()

            // Mode indicator — replaced manual pill with ModeIndicator component
            ModeIndicator(mode: "Practice", color: AppColor.practice)

            if viewModel.stats.totalUserMoves > 0 {
                Text("\(Int(viewModel.stats.accuracy * 100))%")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(AppColor.secondaryText)
                    .padding(.leading, AppSpacing.xs)
            }
        }
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.top, AppSpacing.topBarSafeArea)
        .padding(.bottom, AppSpacing.sm)
    }

    // MARK: - Line Status Bar

    private var lineStatusBar: some View {
        HStack(spacing: AppSpacing.sm) {
            if let lineName = viewModel.currentLineName {
                Image(systemName: "book.fill")
                    .font(.caption2)
                    .foregroundStyle(AppColor.info)
                Text("You're in the \(lineName)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColor.info)
            } else if viewModel.moveCount > 0 {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption2)
                    .foregroundStyle(AppColor.secondaryText)
                Text("On your own — play freely")
                    .font(.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.vertical, AppSpacing.xxs)
        .background(AppColor.elevatedBackground)
    }

    // MARK: - Player Bars

    private var opponentBar: some View {
        HStack(spacing: AppSpacing.sm) {
            Circle()
                .fill(opening.color == .white ? Color(white: 0.3) : .white)
                .frame(width: 10, height: 10)
            Text(OpponentPersonality.forELO(viewModel.opponentELO).name)
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppColor.primaryText)
            Text("\(viewModel.opponentELO)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppColor.secondaryText)
            Spacer()
            if viewModel.isThinking {
                HStack(spacing: AppSpacing.xs) {
                    ProgressView().controlSize(.mini).tint(.secondary)
                    Text("thinking")
                        .font(.caption)
                        .foregroundStyle(AppColor.tertiaryText)
                }
            }
        }
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.vertical, 7)
        .background(AppColor.elevatedBackground)
    }

    private var userBar: some View {
        HStack(spacing: AppSpacing.sm) {
            Circle()
                .fill(opening.color == .white ? .white : Color(white: 0.3))
                .frame(width: 10, height: 10)
            Text("You")
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppColor.primaryText)
            Text("\(viewModel.userELO)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppColor.secondaryText)
            Spacer()
            if viewModel.isUserTurn && !viewModel.isThinking && !viewModel.sessionComplete {
                Text("YOUR MOVE")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.5)
                    .foregroundStyle(AppColor.success)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxxs)
                    .background(AppColor.success.opacity(0.15), in: Capsule())
            }
        }
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.vertical, 7)
        .background(AppColor.elevatedBackground)
    }

    // MARK: - Eval Bar

    private func evalBar(height: CGFloat) -> some View {
        let fraction = viewModel.evalFraction
        let whiteRatio = CGFloat((1.0 + fraction) / 2.0)

        return GeometryReader { _ in
            VStack(spacing: 0) {
                Color(white: 0.2)
                    .frame(height: height * (1 - whiteRatio))
                Color(white: 0.82)
                    .frame(height: height * whiteRatio)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
            .overlay(alignment: .center) {
                Text(viewModel.evalText)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(whiteRatio > 0.5 ? Color(white: 0.2) : Color(white: 0.8))
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.evalScore)
    }

    // MARK: - Complete Overlay

    private var practiceCompleteOverlay: some View {
        let accuracy = viewModel.stats.accuracy
        let accuracyPct = Int(accuracy * 100)
        let tier: AchievementTier? = accuracy >= 0.90 ? .gold : accuracy >= 0.70 ? .silver : accuracy >= 0.50 ? .bronze : nil

        return ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    Spacer(minLength: 60)

                    Image(systemName: "target")
                        .font(.system(size: 44))
                        .foregroundStyle(AppColor.practice)

                    Text("Practice Complete!")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppColor.primaryText)

                    // Accuracy with achievement badge
                    VStack(spacing: AppSpacing.xs) {
                        Text("\(accuracyPct)%")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColor.primaryText)
                        Text("accuracy")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.secondaryText)

                        // Achievement badge for accuracy tier
                        if let tier {
                            AchievementBadge(
                                tier: tier,
                                label: tier == .gold ? "Excellent" : tier == .silver ? "Good" : "Passing"
                            )
                            .padding(.top, AppSpacing.xxs)
                        }
                    }

                    // Lines encountered
                    if !viewModel.linesEncountered.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("Paths Encountered")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColor.secondaryText)

                            ForEach(viewModel.linesEncountered, id: \.self) { lineID in
                                let lineName = opening.lines?.first(where: { $0.id == lineID })?.name ?? lineID
                                let accuracy = viewModel.lineAccuracies[lineID]
                                let pct = accuracy.map { $0.total > 0 ? Int(Double($0.correct) / Double($0.total) * 100) : 0 } ?? 0

                                HStack {
                                    Text(lineName)
                                        .font(.subheadline)
                                        .foregroundStyle(AppColor.primaryText)
                                    Spacer()
                                    Text("\(pct)%")
                                        .font(.subheadline.monospacedDigit().weight(.medium))
                                        .foregroundStyle(pct >= 80 ? AppColor.success : pct >= 50 ? AppColor.warning : AppColor.error)
                                }
                            }
                        }
                        .padding(AppSpacing.cardPadding)
                        .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.md))
                    }

                    // Done button
                    Button(action: { dismiss() }) {
                        Text("Done")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(AppColor.success, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: AppSpacing.xl)
                }
                .padding(AppSpacing.xxxl)
            }
        }
    }
}
