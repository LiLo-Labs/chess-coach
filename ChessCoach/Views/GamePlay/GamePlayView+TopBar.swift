import SwiftUI
import ChessKit

/// Top bar, players bar, and status banners for GamePlayView.
extension GamePlayView {

    // MARK: - Top Bar

    var topBar: some View {
        GameTopBar(
            title: viewModel.mode.isOnboarding ? "Play a Game" : viewModel.mode.isTrainer ? "Trainer" : viewModel.mode.isPuzzle ? "Puzzles" : (viewModel.mode.opening?.name ?? ""),
            subtitle: viewModel.mode.isPuzzle ? "\(viewModel.currentPuzzleIndex + 1)/\(max(viewModel.puzzles.count, 1))" : viewModel.mode.isTrainer ? nil : viewModel.mode.isOnboarding ? nil : viewModel.activeLine?.name,
            showChatToggle: viewModel.isPro && viewModel.mode.isSession && !viewModel.mode.isOnboarding,
            isChatOpen: showChatPanel,
            showBetaOptions: AppConfig.isBeta,
            canUndo: viewModel.canUndo,
            canRedo: viewModel.canRedo,
            isTrainerMode: viewModel.mode.isTrainer,
            onBack: {
                if viewModel.mode.isTrainer {
                    showLeaveConfirmation = true
                } else {
                    viewModel.endSession()
                    dismiss()
                }
            },
            onChatToggle: { showChatPanel.toggle() },
            onUndo: { viewModel.undoMove() },
            onRedo: { viewModel.redoMove() },
            onRestart: { Task { await viewModel.restartSession() } },
            onResign: { viewModel.resignTrainer() },
            onReportBug: { showFeedbackForm = true }
        )
    }

    // MARK: - Players Bar (Trainer)

    var trainerPlayersBar: some View {
        HStack(spacing: AppSpacing.sm) {
            BotAvatarView(personality: viewModel.botPersonality, size: .small)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(viewModel.botPersonality.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.primaryText)
                    Text("(\(viewModel.selectedBotELO))")
                        .font(.caption2)
                        .foregroundStyle(AppColor.tertiaryText)
                }

                HStack(spacing: 4) {
                    Image(systemName: viewModel.trainerEngineMode.icon)
                        .font(.caption2)
                    Text(viewModel.trainerEngineMode.displayName)
                        .font(.caption2)
                }
                .foregroundStyle(AppColor.tertiaryText)
            }

            Spacer()

            Text("Move \(viewModel.gameState.plyCount / 2 + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(AppColor.secondaryText)
        }
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.vertical, AppSpacing.sm)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Playing \(viewModel.botPersonality.name), rated \(viewModel.selectedBotELO). Move \(viewModel.gameState.plyCount / 2 + 1).")
    }

    // MARK: - Players Bar (Session)

    var sessionPlayersBar: some View {
        PlayersBar(
            opponentName: OpponentPersonality.forELO(viewModel.opponentELO).name,
            opponentELO: viewModel.opponentELO,
            opponentDotColor: viewModel.mode.playerColor == .white ? Color(white: 0.3) : .white,
            userName: "You",
            userELO: viewModel.userELO,
            userDotColor: viewModel.mode.playerColor == .white ? .white : Color(white: 0.3),
            isThinking: viewModel.isThinking,
            showYourMove: isUserTurnForSession && !viewModel.isThinking && !viewModel.sessionComplete
        )
    }

    private var isUserTurnForSession: Bool {
        let pc = viewModel.mode.playerColor
        return (pc == .white && viewModel.gameState.isWhiteTurn) ||
               (pc == .black && !viewModel.gameState.isWhiteTurn)
    }

    // MARK: - Line Status Bar (Practice)

    @ViewBuilder
    var practiceLineStatusBar: some View {
        if viewModel.mode.sessionMode == .practice {
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
    }

    // MARK: - Status Banners

    @ViewBuilder
    var statusBanners: some View {
        if viewModel.mode.isSession {
            if viewModel.isModelLoading {
                coachLoadingBar
            }
        }

        OpeningIndicatorBanner(
            whiteOpening: viewModel.holisticDetection.whiteFramework.primary?.opening.name,
            blackOpening: viewModel.holisticDetection.blackFramework.primary?.opening.name,
            playerColor: viewModel.mode.playerColor
        )
    }

    private var coachLoadingBar: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
            Text("\(viewModel.coachPersonality?.displayName(engineMode: false) ?? "Coach") coming online...")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Trainer Status Slot

    @ViewBuilder
    func trainerStatusSlot(boardSize: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Color.clear.frame(height: 44)

            if viewModel.showBotMessage, let message = viewModel.botMessage {
                HStack {
                    Image(systemName: viewModel.botPersonality.icon)
                        .font(.caption)
                        .foregroundStyle(trainerAccentColor)
                        .accessibilityHidden(true)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(AppColor.primaryText)
                        .lineLimit(2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(trainerAccentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, AppSpacing.screenPadding)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            if viewModel.isThinking {
                HStack(spacing: 6) {
                    ThinkingDotsView()
                    Text(viewModel.botPersonality.randomReaction(from: viewModel.botPersonality.thinkingPhrases))
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                .padding(.vertical, 4)
                .transition(.opacity)
            }
        }
        .clipped()
    }

    // MARK: - Personality Quip (Session)

    @ViewBuilder
    func personalityQuipView(quip: String) -> some View {
        let phaseColor = AppColor.familiarityColor(progress: viewModel.familiarityProgress)

        HStack(spacing: 6) {
            Image(systemName: viewModel.coachPersonality?.displayIcon(engineMode: false) ?? "brain")
                .font(.caption)
                .foregroundStyle(phaseColor)
            Text(viewModel.coachPersonality?.displayName(engineMode: false) ?? "Coach")
                .font(.caption2.weight(.bold))
                .foregroundStyle(phaseColor)
            Text(quip)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(phaseColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        ))
    }

    var trainerAccentColor: Color {
        switch viewModel.trainerEngineMode {
        case .humanLike: return AppColor.guided
        case .engine: return AppColor.practice
        case .custom: return .cyan
        }
    }
}
