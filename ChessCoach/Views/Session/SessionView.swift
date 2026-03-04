import SwiftUI
import ChessKit

struct SessionView: View {
    @State private var viewModel: SessionViewModel
    @State private var showReview = false
    @State private var showProUpgrade = false
    @State private var navigateToNextStage = false
    @State private var showFeedbackForm = false
    @State private var showChatPanel = false
    @State private var coachChatState = CoachChatState()
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionService.self) private var subscriptionService

    init(opening: Opening, lineID: String? = nil, isPro: Bool = true, tier: SubscriptionTier? = nil, sessionMode: SessionMode = .guided, stockfish: StockfishService? = nil, llmService: LLMService? = nil) {
        let access = StaticFeatureAccess(tier: tier ?? (isPro ? .pro : .free))
        self._viewModel = State(initialValue: SessionViewModel(opening: opening, lineID: lineID, isPro: isPro, sessionMode: sessionMode, featureAccess: access, stockfish: stockfish, llmService: llmService))
    }

    private var totalPlies: Int {
        viewModel.activeLine?.moves.count ?? viewModel.opening.mainLine.count
    }

    private var moveProgress: Double {
        guard totalPlies > 0 else { return 0 }
        return Double(viewModel.moveCount) / Double(totalPlies)
    }

    private var phaseColor: Color {
        AppColor.phase(viewModel.currentPhase)
    }

    var body: some View {
        GeometryReader { geo in
            let evalWidth: CGFloat = 12
            let evalGap: CGFloat = 4
            let boardSize = min(max(1, geo.size.width - evalWidth - evalGap), geo.size.height * 0.55)

            VStack(spacing: 0) {
                topBar

                if viewModel.maiaStatus.contains("failed") || viewModel.llmStatus == "…" || viewModel.stockfishStatus == "…" {
                    engineWarningBar
                } else if viewModel.llmStatus.contains("Loading") {
                    coachLoadingBar
                }

                playersBar

                // Board
                HStack(spacing: 4) {
                    evalBar(height: boardSize)
                        .frame(width: evalWidth)

                    ZStack {
                        GameBoardView(
                            gameState: viewModel.displayGameState,
                            perspective: viewModel.opening.color == .white ? PieceColor.white : PieceColor.black,
                            allowInteraction: viewModel.isUserTurn && !viewModel.isThinking && !viewModel.sessionComplete && !viewModel.isReplaying
                        ) { from, to in
                            viewModel.clearArrowAndHint()
                            Task { await viewModel.userMoved(from: from, to: to) }
                        }

                        MoveArrowOverlay(
                            arrowFrom: viewModel.arrowFrom,
                            arrowTo: viewModel.arrowTo,
                            boardSize: boardSize,
                            perspective: viewModel.opening.color == .white
                        )
                    }
                    .frame(width: boardSize, height: boardSize)
                }
                .frame(height: boardSize)

                ProgressView(value: moveProgress)
                    .tint(phaseColor)
                    .scaleEffect(y: 0.5)
                    .padding(.horizontal, 16)
                    .animation(.spring(response: 0.35, dampingFraction: 0.9), value: viewModel.moveCount)

                // Coach personality quip overlay
                if viewModel.showPersonalityQuip, let quip = viewModel.personalityQuip {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.coachPersonality.displayIcon(engineMode: false))
                            .font(.caption)
                            .foregroundStyle(phaseColor)
                        Text(viewModel.coachPersonality.displayName(engineMode: false))
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

                replayBar

                // Coaching area — fills remaining space
                coachingArea
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(AppColor.background)
        .preferredColorScheme(.dark)
        .overlay {
            if viewModel.sessionComplete {
                sessionCompleteOverlay
            }
        }
        .overlay(alignment: .trailing) {
            if showChatPanel {
                CoachChatPanel(
                    opening: viewModel.opening,
                    fen: viewModel.displayGameState.fen,
                    moveHistory: viewModel.moveHistorySAN,
                    currentPly: viewModel.moveCount,
                    coachPersonality: viewModel.coachPersonality,
                    isPresented: $showChatPanel,
                    chatState: coachChatState
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .padding(.top, 60)
                .padding(.bottom, 8)
                .padding(.trailing, 4)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.correctMoveTrigger)
        .task {
            await viewModel.startSession()
        }
        .sheet(isPresented: $showProUpgrade) {
            ProUpgradeView()
        }
        .sheet(isPresented: $showFeedbackForm) {
            FeedbackFormView(screen: "Session")
        }
        .onChange(of: viewModel.showProUpgrade) { _, show in
            if show {
                showProUpgrade = true
                viewModel.dismissProUpgrade()
            }
        }
        .onChange(of: subscriptionService.isPro) { _, newValue in
            viewModel.updateProStatus(newValue)
        }
        .fullScreenCover(isPresented: $navigateToNextStage) {
            SessionView(
                opening: viewModel.opening,
                lineID: viewModel.activeLine?.id,
                isPro: viewModel.isPro,
                tier: subscriptionService.currentTier,
                sessionMode: .unguided,
                stockfish: viewModel.stockfish,
                llmService: viewModel.llmService
            )
            .environment(subscriptionService)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            viewModel.saveSessionToDisk()
        }
    }

    // MARK: - Coaching Feed

    private var coachingArea: some View {
        CoachingFeedView(
            entries: sessionFeedEntries,
            isLoading: viewModel.isCoachingLoading,
            explainStyle: viewModel.isPro ? .iconOnly : .locked,
            header: sessionLiveStatus,
            scrollAnchor: "live",
            onTapEntry: { ply in
                viewModel.enterReplay(ply: ply + 1)
            },
            onRequestExplanation: { entry in
                if viewModel.isPro {
                    // Bridge back to CoachingFeedEntry for explanation
                    if let original = viewModel.feedEntries.first(where: { $0.whitePly == entry.ply || $0.blackPly == entry.ply }) {
                        Task { await viewModel.requestExplanationForEntry(original) }
                    }
                } else {
                    showProUpgrade = true
                }
            }
        )
        .background(AppColor.background)
    }

    /// Convert session's CoachingFeedEntry to unified FeedEntry.
    private var sessionFeedEntries: [FeedEntry] {
        viewModel.feedEntries.flatMap { entry -> [FeedEntry] in
            var result: [FeedEntry] = []
            if let whiteSAN = entry.whiteSAN {
                let fe = FeedEntry(
                    ply: entry.whitePly,
                    moveNumber: entry.moveNumber,
                    moveSAN: whiteSAN,
                    isPlayerMove: true,
                    coaching: entry.coaching ?? "",
                    isDeviation: entry.isDeviation,
                    expectedSAN: entry.expectedSAN,
                    expectedUCI: entry.expectedUCI,
                    playedUCI: entry.playedUCI
                )
                fe.fen = entry.fen
                fe.explanation = entry.explanation
                fe.isExplaining = entry.isExplaining
                result.append(fe)
            }
            if let blackSAN = entry.blackSAN, let blackPly = entry.blackPly {
                let fe = FeedEntry(
                    ply: blackPly,
                    moveNumber: entry.moveNumber,
                    moveSAN: blackSAN,
                    isPlayerMove: false,
                    coaching: ""
                )
                fe.fen = entry.fen
                result.append(fe)
            }
            return result
        }
    }

    // MARK: - Session Live Status

    @ViewBuilder
    private var sessionLiveStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let variation = viewModel.suggestedVariation {
                sessionVariationBanner(variation: variation)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            if case let .userDeviated(expected, _) = viewModel.bookStatus {
                DeviationBanner.UserDeviation(
                    expected: expected,
                    isUnguided: viewModel.sessionMode == .unguided
                )
                .padding(.horizontal, 16)
            } else if case let .opponentDeviated(expected, playedSAN, _) = viewModel.bookStatus {
                DeviationBanner.OpponentDeviation(
                    expected: expected,
                    playedSAN: playedSAN,
                    bestMoveDescription: viewModel.bestResponseDescription
                )
                .padding(.horizontal, 16)
            } else if case .offBook = viewModel.bookStatus {
                DeviationBanner.OffBook(bestMoveDescription: viewModel.bestResponseDescription)
                    .padding(.horizontal, 16)
            } else if viewModel.discoveryMode {
                DeviationBanner.Discovery(optionCount: viewModel.branchPointOptions?.count ?? 2)
                    .padding(.horizontal, 16)
            }

            sessionActionButtons
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.bookStatus)
    }

    // MARK: - Session Action Buttons

    @ViewBuilder
    private var sessionActionButtons: some View {
        HStack(spacing: 8) {
            if case .userDeviated = viewModel.bookStatus {
                Button(action: { viewModel.retryLastMove() }) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.orange)
                .controlSize(.small)

                Button(action: { Task { await viewModel.continueAfterDeviation() } }) {
                    Text("Continue")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.secondary)
                .controlSize(.small)
            }

            if case .opponentDeviated = viewModel.bookStatus {
                Button(action: { Task { await viewModel.restartSession() } }) {
                    Label("Retry", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.mint)
                .controlSize(.small)
            }

            if case .offBook = viewModel.bookStatus {
                Button(action: { Task { await viewModel.restartSession() } }) {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.cyan)
                .controlSize(.small)
            }

            Spacer()
        }
    }

    // MARK: - Variation Banner

    private func sessionVariationBanner(variation: OpeningLine) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption2)
                .foregroundStyle(.teal)
            Text("You played into the \(variation.name)")
                .font(.caption)
                .foregroundStyle(.teal)
            Spacer()
            Button {
                viewModel.switchToLine(variation)
            } label: {
                Text("Switch")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.teal)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.teal.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Eval Bar

    private func evalBar(height: CGFloat) -> some View {
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

    // MARK: - Top Bar

    private var topBar: some View {
        GameTopBar(
            title: viewModel.opening.name,
            subtitle: viewModel.activeLine?.name,
            showChatToggle: viewModel.isPro,
            isChatOpen: showChatPanel,
            showBetaOptions: AppConfig.isBeta,
            canUndo: viewModel.canUndo,
            canRedo: viewModel.canRedo,
            isTrainerMode: false,
            onBack: {
                viewModel.endSession()
                dismiss()
            },
            onToggleChat: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showChatPanel.toggle()
                }
            },
            onUndo: { viewModel.undoMove() },
            onRedo: { viewModel.redoMove() },
            onRestart: { Task { await viewModel.restartSession() } },
            onReportBug: { showFeedbackForm = true }
        )
    }

    // MARK: - Engine Warning / Loading Bars

    private var engineWarningBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
            Text("AI offline")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.yellow)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var coachLoadingBar: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
            Text("\(viewModel.coachPersonality.displayName(engineMode: false)) coming online...")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Players Bar

    private var playersBar: some View {
        PlayersBar(
            opponentName: OpponentPersonality.forELO(viewModel.opponentELO).name,
            opponentELO: viewModel.opponentELO,
            opponentDotColor: viewModel.opening.color == .white ? Color(white: 0.3) : .white,
            userName: "You",
            userELO: viewModel.userELO,
            userDotColor: viewModel.opening.color == .white ? .white : Color(white: 0.3),
            isThinking: viewModel.isThinking,
            showYourMove: viewModel.isUserTurn && !viewModel.isThinking && !viewModel.sessionComplete
        )
    }

    // MARK: - Replay Bar

    @ViewBuilder
    private var replayBar: some View {
        ReplayBar(
            totalPly: viewModel.moveCount,
            replayPly: viewModel.replayPly,
            isReplaying: viewModel.isReplaying,
            onGoToStart: { viewModel.enterReplay(ply: 0) },
            onStepBack: {
                let current = viewModel.replayPly ?? viewModel.moveCount
                viewModel.enterReplay(ply: current - 1)
            },
            onStepForward: {
                let current = viewModel.replayPly ?? viewModel.moveCount
                viewModel.enterReplay(ply: current + 1)
            },
            onGoToEnd: { viewModel.exitReplay() },
            onResume: { viewModel.exitReplay() }
        )
    }

    // MARK: - Session Complete Overlay

    private var sessionCompleteOverlay: some View {
        SessionCompleteView(
            result: viewModel.sessionResult,
            moveCount: viewModel.moveCount,
            openingName: viewModel.opening.name,
            lineName: viewModel.activeLine?.name,
            sessionMode: viewModel.sessionMode,
            onTryAgain: { Task { await viewModel.restartSession() } },
            onDone: { dismiss() },
            onReviewNow: (viewModel.sessionResult?.dueReviewCount ?? 0) > 0 ? { showReview = true } : nil,
            onNextStage: nextStageAction,
            coachPersonality: CoachPersonality.forOpening(viewModel.opening)
        )
        .sheet(isPresented: $showReview) {
            NavigationStack {
                QuickReviewView(openingID: viewModel.opening.id)
            }
        }
    }

    private var nextStageAction: (() -> Void)? {
        switch viewModel.sessionMode {
        case .guided:
            return { navigateToNextStage = true }
        case .unguided, .practice:
            return nil
        }
    }
}
