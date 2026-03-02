import SwiftUI
import ChessKit

/// Top bar, players bar, and status banners for GamePlayView.
extension GamePlayView {

    // MARK: - Top Bar

    var topBar: some View {
        HStack(spacing: 0) {
            Button {
                if viewModel.mode.isTrainer {
                    showLeaveConfirmation = true
                } else {
                    viewModel.endSession()
                    dismiss()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            Spacer()

            if viewModel.mode.isTrainer {
                Text("Trainer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            } else if let opening = viewModel.mode.opening {
                VStack(spacing: 1) {
                    Text(opening.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let line = viewModel.activeLine {
                        Text(line.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if viewModel.isPro && viewModel.mode.isSession {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showChatPanel.toggle()
                    }
                } label: {
                    Image(systemName: showChatPanel ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                        .font(.body)
                        .foregroundStyle(showChatPanel ? AppColor.practice : .secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showChatPanel ? "Close coach chat" : "Open coach chat")
            }

            Menu {
                Button { viewModel.undoMove() } label: {
                    Label("Undo Move", systemImage: "arrow.uturn.backward")
                }
                .disabled(!viewModel.canUndo)

                Button { viewModel.redoMove() } label: {
                    Label("Redo Move", systemImage: "arrow.uturn.forward")
                }
                .disabled(!viewModel.canRedo)

                Divider()

                if viewModel.mode.isTrainer {
                    Button(role: .destructive) {
                        viewModel.resignTrainer()
                    } label: {
                        Label("Resign", systemImage: "flag.fill")
                    }
                } else {
                    Button {
                        Task { await viewModel.restartSession() }
                    } label: {
                        Label("Restart", systemImage: "arrow.counterclockwise")
                    }
                }

                if AppConfig.isBeta {
                    Button { showFeedbackForm = true } label: {
                        Label("Report Bug", systemImage: "ladybug.fill")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More options")
        }
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.top, AppSpacing.topBarSafeArea)
        .padding(.bottom, 4)
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
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.mode.playerColor == .white ? Color(white: 0.3) : .white)
                    .frame(width: 8, height: 8)
                Text(OpponentPersonality.forELO(viewModel.opponentELO).name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(viewModel.opponentELO)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                if viewModel.isThinking {
                    ProgressView().controlSize(.mini).tint(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                if isUserTurnForSession && !viewModel.isThinking && !viewModel.sessionComplete {
                    Text("YOUR MOVE")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.3)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.15), in: Capsule())
                        .phaseAnimator([false, true]) { content, phase in
                            content.opacity(phase ? 1.0 : 0.6)
                        } animation: { _ in .easeInOut(duration: 0.8) }
                }
                Text("\(viewModel.userELO)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("You")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Circle()
                    .fill(viewModel.mode.playerColor == .white ? .white : Color(white: 0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(AppColor.elevatedBackground)
    }

    private var isUserTurnForSession: Bool {
        let pc = viewModel.mode.playerColor
        return (pc == .white && viewModel.gameState.isWhiteTurn) ||
               (pc == .black && !viewModel.gameState.isWhiteTurn)
    }

    // MARK: - Status Banners

    @ViewBuilder
    var statusBanners: some View {
        if viewModel.mode.isSession {
            if viewModel.isModelLoading {
                coachLoadingBar
            }
        }
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
        let phaseColor = AppColor.phase(viewModel.currentPhase)

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
