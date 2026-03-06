import SwiftUI
import ChessKit

/// Overlays: game over (trainer), session complete (session), chat panel.
extension GamePlayView {

    @ViewBuilder
    var overlays: some View {
        // Trainer game over
        if viewModel.mode.isTrainer && viewModel.isGameOver, let result = viewModel.gameResult {
            trainerGameOverOverlay(result: result)
        }

        // Practice complete
        if viewModel.mode.sessionMode == .practice && viewModel.sessionComplete {
            practiceCompleteOverlay
        }

        // Session complete (guided/unguided)
        if viewModel.mode.isSession && viewModel.mode.sessionMode != .practice && viewModel.sessionComplete {
            sessionCompleteOverlay
        }

        // Puzzle complete
        if viewModel.isPuzzleComplete {
            puzzleCompleteOverlay
        }

        // Onboarding revelation
        if viewModel.onboardingComplete {
            onboardingRevelationOverlay
        }
    }

    // MARK: - Puzzle Complete

    private var puzzleCompleteOverlay: some View {
        let result = viewModel.puzzleSessionResult
        let pct = result.total > 0 ? Int(result.accuracy * 100) : 0

        return ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: AppSpacing.md) {
                SessionSummaryCard(
                    stats: [
                        .init(label: "Correct", value: "\(result.solved)/\(result.total)"),
                        .init(label: "Accuracy", value: "\(pct)%"),
                        .init(label: "Best Streak", value: "\(result.bestStreak)"),
                    ],
                    icon: "puzzlepiece.fill",
                    iconColor: .orange,
                    title: "Puzzles Complete!"
                )

                VStack(spacing: AppSpacing.md) {
                    Button("Play Again") {
                        viewModel.isPuzzleComplete = false
                        Task { await viewModel.loadPuzzles() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, AppSpacing.md)
            }
            .padding(AppSpacing.xl)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.lg))
        }
    }

    // MARK: - Practice Complete

    private var practiceCompleteOverlay: some View {
        let accuracy = viewModel.stats.accuracy
        let accuracyPct = Int(accuracy * 100)
        let tier: AchievementTier? = accuracy >= 0.90 ? .gold : accuracy >= 0.70 ? .silver : accuracy >= 0.50 ? .bronze : nil

        return ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.top, AppSpacing.topBarSafeArea)
                .padding(.trailing, AppSpacing.screenPadding)
                Spacer()
            }
            .zIndex(1)

            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    Spacer(minLength: 60)

                    Image(systemName: "target")
                        .font(.system(size: 44))
                        .foregroundStyle(AppColor.practice)

                    Text("Practice Complete!")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppColor.primaryText)

                    VStack(spacing: AppSpacing.xs) {
                        Text("\(accuracyPct)%")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColor.primaryText)
                        Text("accuracy")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.secondaryText)

                        if let tier {
                            AchievementBadge(
                                tier: tier,
                                label: tier == .gold ? "Excellent" : tier == .silver ? "Good" : "Passing"
                            )
                            .padding(.top, AppSpacing.xxs)
                        }
                    }

                    if !viewModel.linesEncountered.isEmpty, let opening = viewModel.mode.opening {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("Paths Encountered")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppColor.secondaryText)

                            ForEach(viewModel.linesEncountered, id: \.self) { lineID in
                                let lineName = opening.lines?.first(where: { $0.id == lineID })?.name ?? lineID
                                let lineAcc = viewModel.lineAccuracies[lineID]
                                let pct = lineAcc.map { $0.total > 0 ? Int(Double($0.correct) / Double($0.total) * 100) : 0 } ?? 0

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
                        .cardBackground()
                    }

                    Button(action: { dismiss() }) {
                        Text("Done")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .buttonBackground(AppColor.success)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: AppSpacing.xl)
                }
                .padding(AppSpacing.xxxl)
            }
        }
    }

    // MARK: - Trainer Game Over

    private func trainerGameOverOverlay(result: TrainerGameResult) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            VStack(spacing: AppSpacing.xxl) {
                Spacer()

                Image(systemName: resultIcon(result.outcome))
                    .font(.system(size: 64))
                    .foregroundStyle(resultColor(result.outcome))
                    .transition(.scale(scale: 0).combined(with: .opacity))

                Text(outcomeText(result.outcome))
                    .font(.title.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)

                // Bot reaction
                if let reaction = botReactionForResult(result.outcome) {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.botPersonality.icon)
                            .font(.caption)
                            .foregroundStyle(trainerAccentColor)
                            .accessibilityHidden(true)
                        Text(reaction)
                            .font(.subheadline)
                            .foregroundStyle(AppColor.secondaryText)
                            .italic()
                    }
                }

                // Game info card
                VStack(spacing: AppSpacing.sm) {
                    HStack {
                        Text("vs \(result.botName)")
                            .foregroundStyle(AppColor.primaryText)
                        Spacer()
                        Text("\(result.botELO)")
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    .font(.subheadline)

                    HStack {
                        Text("Mode")
                            .foregroundStyle(AppColor.secondaryText)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.trainerEngineMode.icon)
                                .font(.caption2)
                            Text(viewModel.trainerEngineMode.displayName)
                        }
                        .foregroundStyle(AppColor.primaryText)
                    }
                    .font(.subheadline)

                    HStack {
                        Text("Moves")
                            .foregroundStyle(AppColor.secondaryText)
                        Spacer()
                        Text("\(result.moveCount / 2)")
                            .foregroundStyle(AppColor.primaryText)
                    }
                    .font(.subheadline)
                }
                .padding(AppSpacing.cardPadding)
                .cardBackground()
                .padding(.horizontal, AppSpacing.xxl)

                // Buttons
                VStack(spacing: AppSpacing.sm) {
                    Button {
                        // Rematch — reset and start new game
                        viewModel.isGameOver = false
                        viewModel.gameResult = nil
                        viewModel.feedEntries.removeAll()
                        Task { await viewModel.startGame() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Rematch")
                                .font(.body.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(trainerAccentColor, in: RoundedRectangle(cornerRadius: AppRadius.lg))
                    }
                    .buttonStyle(ScaleButtonStyle())

                    Button {
                        dismiss()
                    } label: {
                        Text("Back to Setup")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, AppSpacing.xxl)

                Spacer()
            }
        }
    }

    // MARK: - Session Complete

    private var sessionCompleteOverlay: some View {
        SessionCompleteView(
            result: viewModel.sessionResult,
            moveCount: viewModel.gameState.plyCount,
            openingName: viewModel.mode.opening?.name ?? "",
            lineName: viewModel.activeLine?.name,
            sessionMode: viewModel.mode.sessionMode ?? .guided,
            onTryAgain: { Task { await viewModel.restartSession() } },
            onDone: { dismiss() },
            onReviewNow: (viewModel.sessionResult?.dueReviewCount ?? 0) > 0 ? { showReview = true } : nil,
            onNextStage: nextStageAction,
            coachPersonality: viewModel.mode.opening.map { CoachPersonality.forOpening($0) }
        )
        .sheet(isPresented: $showReview) {
            NavigationStack {
                QuickReviewView(openingID: viewModel.mode.opening?.id ?? "")
            }
        }
    }

    private var nextStageAction: (() -> Void)? {
        switch viewModel.mode.sessionMode {
        case .guided:
            return { navigateToNextStage = true }
        default:
            return nil
        }
    }

    // MARK: - Chat Panel

    @ViewBuilder
    var chatPanelOverlay: some View {
        if showChatPanel {
            if viewModel.mode.isTrainer, let match = viewModel.currentOpening.best {
                CoachChatPanel(
                    opening: match.opening,
                    fen: viewModel.displayGameState.fen,
                    moveHistory: viewModel.gameState.moveHistory.map { "\($0.from)\($0.to)" },
                    currentPly: viewModel.gameState.plyCount,
                    coachPersonality: CoachPersonality.forOpening(match.opening),
                    isEngineMode: viewModel.trainerEngineMode != .humanLike,
                    isPresented: $showChatPanel,
                    chatState: coachChatState
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if let opening = viewModel.mode.opening {
                CoachChatPanel(
                    opening: opening,
                    fen: viewModel.displayGameState.fen,
                    moveHistory: viewModel.moveHistorySAN,
                    currentPly: viewModel.gameState.plyCount,
                    coachPersonality: viewModel.coachPersonality ?? .defaultPersonality,
                    isPresented: $showChatPanel,
                    chatState: coachChatState
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .padding(.top, 60)
                .padding(.bottom, 8)
                .padding(.trailing, 4)
            }
        }
    }

    // MARK: - Result Helpers

    private func resultIcon(_ outcome: TrainerGameResult.Outcome) -> String {
        switch outcome {
        case .win: return "crown.fill"
        case .loss: return "xmark.circle.fill"
        case .draw: return "equal.circle.fill"
        case .resigned: return "flag.fill"
        }
    }

    private func resultColor(_ outcome: TrainerGameResult.Outcome) -> Color {
        switch outcome {
        case .win: return AppColor.gold
        case .loss, .resigned: return AppColor.error
        case .draw: return AppColor.secondaryText
        }
    }

    private func outcomeText(_ outcome: TrainerGameResult.Outcome) -> String {
        switch outcome {
        case .win: return "You Won!"
        case .loss: return "You Lost"
        case .draw: return "Draw"
        case .resigned: return "Resigned"
        }
    }

    private func botReactionForResult(_ outcome: TrainerGameResult.Outcome) -> String? {
        let p = viewModel.botPersonality
        switch outcome {
        case .win: return p.randomReaction(from: p.onLoss)
        case .loss, .resigned: return p.randomReaction(from: p.onWin)
        case .draw: return "Good game — evenly matched."
        }
    }

    // MARK: - Onboarding Revelation

    private var onboardingRevelationOverlay: some View {
        let opening = viewModel.onboardingDetectedOpening
        let openingName = opening?.name ?? "an Opening"
        let matchDepth = viewModel.holisticDetection.whiteFramework.primary?.matchDepth ?? 0

        return ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    Spacer(minLength: 60)

                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundStyle(.yellow)
                        .symbolEffect(.pulse, options: .repeating.speed(0.5))

                    Text("You played the \(openingName)!")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppColor.primaryText)
                        .multilineTextAlignment(.center)

                    if let desc = opening?.description, !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(AppColor.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.md)
                    }

                    SessionSummaryCard(
                        stats: [
                            .init(label: "Your Level", value: "\(viewModel.userELO)"),
                            .init(label: "Moves Played", value: "\(viewModel.onboardingMoveCount)"),
                            .init(label: "Match Depth", value: "\(matchDepth) moves"),
                        ],
                        icon: "sparkles",
                        iconColor: .yellow,
                        title: "Your First Game"
                    )

                    Text("Every chess game starts with an opening — a set of proven moves that give you direction and purpose. You just played one naturally!")
                        .font(.callout)
                        .foregroundStyle(AppColor.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.md)

                    // Action buttons
                    VStack(spacing: AppSpacing.md) {
                        if let opening {
                            Button {
                                settings.pickedFreeOpeningID = opening.id
                                settings.hasPickedFreeOpening = true
                                dismiss()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "book.fill")
                                    Text("Learn \(opening.name)")
                                        .font(.body.weight(.semibold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppColor.guided, in: RoundedRectangle(cornerRadius: AppRadius.lg))
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }

                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.grid.2x2")
                                Text("Browse All Openings")
                                    .font(.body.weight(.medium))
                            }
                            .foregroundStyle(AppColor.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.lg))
                        }
                        .buttonStyle(ScaleButtonStyle())

                        Button {
                            dismiss()
                        } label: {
                            Text("Skip to Home")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppColor.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, AppSpacing.md)

                    Spacer(minLength: AppSpacing.xl)
                }
                .padding(AppSpacing.xxxl)
            }
        }
    }
}
