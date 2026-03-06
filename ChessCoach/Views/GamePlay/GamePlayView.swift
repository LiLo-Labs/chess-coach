import SwiftUI
import ChessKit

/// Unified gameplay screen for all modes: trainer, guided, unguided, and practice.
struct GamePlayView: View {
    @State var viewModel: GamePlayViewModel
    @State var showChatPanel = false
    @State var coachChatState = CoachChatState()
    @State var showLeaveConfirmation = false
    @State var showProUpgrade = false
    @State var showFeedbackForm = false
    @State var navigateToNextStage = false
    @State var showReview = false
    @Environment(\.dismiss) var dismiss
    @Environment(AppSettings.self) var settings
    @Environment(SubscriptionService.self) var subscriptionService
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    init(mode: GamePlayMode, isPro: Bool = true, tier: SubscriptionTier? = nil, stockfish: StockfishService? = nil, llmService: LLMService? = nil) {
        let access = StaticFeatureAccess(tier: tier ?? (isPro ? .pro : .free))
        self._viewModel = State(initialValue: GamePlayViewModel(mode: mode, isPro: isPro, featureAccess: access, stockfish: stockfish, llmService: llmService))
    }

    var body: some View {
        GeometryReader { geo in
            let evalWidth: CGFloat = (viewModel.mode.isSession && !viewModel.mode.isOnboarding) ? 12 : 0
            let evalGap: CGFloat = (viewModel.mode.isSession && !viewModel.mode.isOnboarding) ? 4 : 0
            let boardSize = min(max(1, geo.size.width - evalWidth - evalGap - (viewModel.mode.isTrainer ? AppSpacing.sm * 2 : 0)), geo.size.height * 0.55)

            VStack(spacing: 0) {
                topBar

                if !viewModel.mode.isOnboarding {
                    statusBanners

                    practiceLineStatusBar
                }

                if viewModel.mode.isTrainer {
                    trainerPlayersBar
                } else if !viewModel.mode.isPuzzle && !viewModel.mode.isOnboarding {
                    sessionPlayersBar
                }

                boardArea(boardSize: boardSize, evalWidth: evalWidth)

                if viewModel.mode.isSession && !viewModel.mode.isOnboarding {
                    progressBar
                }

                if viewModel.mode.isTrainer {
                    trainerStatusSlot(boardSize: boardSize)
                } else if !viewModel.mode.isPuzzle && !viewModel.mode.isOnboarding, viewModel.showPersonalityQuip, let quip = viewModel.personalityQuip {
                    personalityQuipView(quip: quip)
                }

                if !viewModel.mode.isPuzzle && !viewModel.mode.isOnboarding {
                    replayBar
                }

                coachingFeed
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(AppColor.background)
        .preferredColorScheme(.dark)
        .overlay { overlays }
        .overlay(alignment: .trailing) { chatPanelOverlay }
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.mode.isSession ? viewModel.correctMoveTrigger : 0)
        .task { await viewModel.startGame() }
        .sheet(isPresented: $showProUpgrade) { ProUpgradeView() }
        .sheet(isPresented: $showFeedbackForm) { FeedbackFormView(screen: "GamePlay") }
        .onChange(of: viewModel.showProUpgrade) { _, show in
            if show {
                showProUpgrade = true
                viewModel.dismissProUpgrade()
            }
        }
        .onChange(of: subscriptionService.isPro) { _, newValue in
            viewModel.updateProStatus(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            viewModel.saveSessionToDisk()
        }
        .alert("Leave Game?", isPresented: $showLeaveConfirmation) {
            Button("Leave", role: .destructive) {
                viewModel.endSession()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.mode.isTrainer ? "The game will not count as a loss." : viewModel.mode.isPuzzle ? "Your puzzle progress will be lost." : "Your progress will be saved.")
        }
        .fullScreenCover(isPresented: $navigateToNextStage) {
            if let opening = viewModel.mode.opening {
                GamePlayView(
                    mode: .unguided(opening: opening, lineID: viewModel.activeLineID),
                    isPro: viewModel.isPro,
                    tier: subscriptionService.currentTier,
                    stockfish: viewModel.stockfish,
                    llmService: viewModel.llmService
                )
                .environment(subscriptionService)
            }
        }
    }
}
