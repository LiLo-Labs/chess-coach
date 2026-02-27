import SwiftUI
import ChessKit

struct SessionView: View {
    @State private var viewModel: SessionViewModel
    @State private var showReview = false
    @State private var showProUpgrade = false
    @State private var navigateToNextStage = false
    @State private var showFeedbackForm = false
    @State private var showChatPanel = false
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionService.self) private var subscriptionService

    init(opening: Opening, lineID: String? = nil, isPro: Bool = true, sessionMode: SessionMode = .guided, stockfish: StockfishService? = nil, llmService: LLMService? = nil) {
        let access = StaticFeatureAccess(isPro: isPro)
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
            let boardSize = max(1, geo.size.width - evalWidth - evalGap)

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
                    isPro: viewModel.isPro,
                    isPresented: $showChatPanel
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Live status (banners, loading, actions)
                    liveStatus
                        .id("live")

                    // Feed entries (newest first) — tappable to replay board
                    ForEach(viewModel.feedEntries) { entry in
                        feedRow(entry)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .background(AppColor.background)
            .onChange(of: viewModel.feedEntries.count) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("live", anchor: .top)
                }
            }
        }
    }

    // MARK: - Live Status

    @ViewBuilder
    private var liveStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Variation switch
            if let variation = viewModel.suggestedVariation {
                variationBanner(variation: variation)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            // Deviation / off-book banners
            if case let .userDeviated(expected, _) = viewModel.bookStatus {
                deviationBanner(expected: expected)
                    .padding(.horizontal, 16)
            } else if case let .opponentDeviated(expected, playedSAN, _) = viewModel.bookStatus {
                opponentDeviationBanner(expected: expected, played: playedSAN)
                    .padding(.horizontal, 16)
            } else if case .offBook = viewModel.bookStatus {
                offBookBanner
                    .padding(.horizontal, 16)
            } else if viewModel.discoveryMode {
                discoveryBanner
                    .padding(.horizontal, 16)
            }

            // Action buttons
            actionButtons
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

            // Empty state
            if viewModel.feedEntries.isEmpty && !viewModel.isCoachingLoading {
                Text("Make your move on the board")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.bookStatus)
    }

    // MARK: - Feed Row

    private func feedRow(_ entry: CoachingFeedEntry) -> some View {
        let isNewest = entry.id == viewModel.feedEntries.first?.id
        let whiteSAN = entry.whiteSAN ?? "…"
        let blackSAN = entry.blackSAN

        // Human-friendly move descriptions
        let whiteFriendly = friendlyMoveName(whiteSAN)
        let blackFriendly = blackSAN.map { friendlyMoveName($0) }

        // Algebraic notation (secondary)
        let algebraic = blackSAN.map { "\(entry.moveNumber). \(whiteSAN) \($0)" }
            ?? "\(entry.moveNumber). \(whiteSAN)"

        return Button {
            // Tap to jump board to this position
            let targetPly = entry.blackPly ?? entry.whitePly
            viewModel.enterReplay(ply: targetPly + 1)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // Move header with friendly names
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // White's move
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                        Text(whiteFriendly)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(entry.isDeviation ? .orange : Color.white)
                    }

                    // Black's move (if present)
                    if let blackFriendly {
                        Text("·")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color(white: 0.35))
                                .frame(width: 8, height: 8)
                            Text(blackFriendly)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color(white: 0.65))
                        }
                    }

                    Spacer(minLength: 0)

                    // Tappable AI explanation sparkle per entry (pro only)
                    if viewModel.isPro {
                        if entry.isExplaining {
                            ProgressView().controlSize(.mini).tint(.purple)
                        } else if entry.explanation != nil {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(.purple)
                        } else {
                            Button {
                                Task { await viewModel.requestExplanationForEntry(entry) }
                            } label: {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Algebraic notation (secondary, smaller)
                Text(algebraic)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)

                // Coaching narrative
                if let coaching = entry.coaching {
                    Text(coaching)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                // Explanation (attached to the move, shown when ready)
                if let explanation = entry.explanation {
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(white: 0.13))
                    .opacity(isNewest ? 1.0 : 0.6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Move Name Helpers

    /// Convert SAN notation (e.g. "Nf3", "e4", "O-O") to human-friendly text (e.g. "Knight to f3", "Pawn to e4", "Castle kingside")
    private func friendlyMoveName(_ san: String) -> String {
        // Handle castling
        if san == "O-O" || san == "0-0" { return "Castle short" }
        if san == "O-O-O" || san == "0-0-0" { return "Castle long" }

        // Strip check/checkmate symbols and capture marker
        var cleaned = san.replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "#", with: "")

        // Handle promotion (e.g. "e8=Q")
        var promotion: String?
        if let eqIdx = cleaned.firstIndex(of: "=") {
            let promoChar = cleaned[cleaned.index(after: eqIdx)]
            promotion = pieceFullName(promoChar)
            cleaned = String(cleaned[cleaned.startIndex..<eqIdx])
        }

        let piece: String
        let destination: String

        if let first = cleaned.first, first.isUppercase {
            // Piece move (N, B, R, Q, K)
            piece = pieceFullName(first)
            // Destination is the last 2 characters
            let stripped = cleaned.replacingOccurrences(of: "x", with: "")
            destination = String(stripped.suffix(2))
        } else {
            // Pawn move
            piece = "Pawn"
            let stripped = cleaned.replacingOccurrences(of: "x", with: "")
            destination = String(stripped.suffix(2))
        }

        let captures = san.contains("x") ? " takes" : " to"
        let promoText = promotion.map { ", promotes to \($0)" } ?? ""

        return "\(piece)\(captures) \(destination)\(promoText)"
    }

    private func pieceFullName(_ char: Character) -> String {
        switch char {
        case "K": return "King"
        case "Q": return "Queen"
        case "R": return "Rook"
        case "B": return "Bishop"
        case "N": return "Knight"
        default: return "Pawn"
        }
    }

    // MARK: - Status Banners

    private func deviationBanner(expected: OpeningMove) -> some View {
        let isUnguided = viewModel.sessionMode == .unguided

        return VStack(alignment: .leading, spacing: 4) {
            Text(isUnguided
                 ? "Recommended move was \(expected.san)"
                 : "The plan plays \(expected.san) here")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

            if !expected.explanation.isEmpty {
                Text(expected.explanation)
                    .font(.caption2)
                    .foregroundStyle(.primary.opacity(0.6))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func opponentDeviationBanner(expected: OpeningMove, played: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Opponent played \(played) instead of \(expected.san)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.mint)

            if let bestMove = viewModel.bestResponseDescription {
                Text("Try \(bestMove)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.mint.opacity(0.8))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var offBookBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("On your own — play your plan")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.cyan)

            if let bestMove = viewModel.bestResponseDescription {
                Text("Suggested: \(bestMove)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.cyan.opacity(0.8))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var discoveryBanner: some View {
        VStack(alignment: .leading, spacing: 2) {
            let count = viewModel.branchPointOptions?.count ?? 2
            Text("\(count) good options here — can you find one?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.mint)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
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

    private func variationBanner(variation: OpeningLine) -> some View {
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
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.evalScore)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 0) {
            Button {
                viewModel.endSession()
                dismiss()
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

            VStack(spacing: 1) {
                Text(viewModel.opening.name)
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

            Spacer()

            // Chat panel toggle (AI tiers only)
            if viewModel.isPro {
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

                Button {
                    Task { await viewModel.restartSession() }
                } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
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
            Text("Coach coming online...")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Players Bar

    private var opponentPersonality: OpponentPersonality {
        OpponentPersonality.forELO(viewModel.opponentELO)
    }

    private var playersBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.opening.color == .white ? Color(white: 0.3) : .white)
                    .frame(width: 8, height: 8)
                Text(opponentPersonality.name)
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
                if viewModel.isUserTurn && !viewModel.isThinking && !viewModel.sessionComplete {
                    Text("YOUR MOVE")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.3)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.15), in: Capsule())
                }
                Text("\(viewModel.userELO)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("You")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Circle()
                    .fill(viewModel.opening.color == .white ? .white : Color(white: 0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(AppColor.elevatedBackground)
    }

    // MARK: - Replay Bar

    @ViewBuilder
    private var replayBar: some View {
        if viewModel.moveCount > 0 {
            HStack(spacing: 4) {
                Button { viewModel.enterReplay(ply: 0) } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.body)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(viewModel.isReplaying && viewModel.replayPly == 0)

                Button {
                    let current = viewModel.replayPly ?? viewModel.moveCount
                    viewModel.enterReplay(ply: current - 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(viewModel.isReplaying && viewModel.replayPly == 0)

                Spacer()

                if viewModel.isReplaying {
                    Text("Move \(viewModel.replayPly ?? 0) of \(viewModel.moveCount)")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Ply \(viewModel.moveCount)")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    let current = viewModel.replayPly ?? viewModel.moveCount
                    viewModel.enterReplay(ply: current + 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!viewModel.isReplaying)

                Button { viewModel.exitReplay() } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.body)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!viewModel.isReplaying)

                if viewModel.isReplaying {
                    Button { viewModel.exitReplay() } label: {
                        Text("Resume")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.green.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(.white.opacity(0.6))
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.screenPadding)
        }
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
            onNextStage: nextStageAction
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
