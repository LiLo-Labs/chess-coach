import SwiftUI
import ChessKit

struct SessionView: View {
    @State private var viewModel: SessionViewModel
    @State private var userCoachingExpanded = true
    @State private var opponentCoachingExpanded = false
    @State private var showReview = false
    @State private var showProUpgrade = false
    @State private var tappedMoveCoaching: String?  // Improvement 13
    @State private var navigateToNextStage = false
    @Environment(\.dismiss) private var dismiss
    @Environment(SubscriptionService.self) private var subscriptionService

    init(opening: Opening, lineID: String? = nil, isPro: Bool = true, sessionMode: SessionMode = .guided) {
        self._viewModel = State(initialValue: SessionViewModel(opening: opening, lineID: lineID, isPro: isPro, sessionMode: sessionMode))
    }

    // Total plies in active line for progress bar (improvement 17)
    private var totalPlies: Int {
        viewModel.activeLine?.moves.count ?? viewModel.opening.mainLine.count
    }

    // Progress fraction for the thin bar
    private var moveProgress: Double {
        guard totalPlies > 0 else { return 0 }
        return Double(viewModel.moveCount) / Double(totalPlies)
    }

    // Phase color for progress bar tint
    private var phaseColor: Color {
        AppColor.phase(viewModel.currentPhase)
    }

    // Contextual undo label (improvement 20)
    private var undoLabel: String {
        if case let .userDeviated(expected, _) = viewModel.bookStatus {
            return "Undo — play \(expected.san)"
        }
        return "Undo"
    }

    var body: some View {
        GeometryReader { geo in
            let evalWidth: CGFloat = 12
            let evalGap: CGFloat = 4
            let boardSize = max(1, geo.size.width - evalWidth - evalGap)

            VStack(spacing: 0) {
                topBar

                // Improvement 15: minimal engine indicator (only when there's an issue)
                if viewModel.maiaStatus.contains("failed") || viewModel.llmStatus == "…" || viewModel.stockfishStatus == "…" {
                    engineWarningBar
                }

                opponentBar

                // Eval bar + Board
                HStack(spacing: 4) {
                    evalBar(height: boardSize)
                        .frame(width: evalWidth)

                    ZStack {
                        GameBoardView(
                            gameState: viewModel.gameState,
                            perspective: viewModel.opening.color == .white ? PieceColor.white : PieceColor.black,
                            allowInteraction: viewModel.isUserTurn && !viewModel.isThinking && !viewModel.sessionComplete
                        ) { from, to in
                            viewModel.clearArrowAndHint()
                            Task { await viewModel.userMoved(from: from, to: to) }
                        }

                        // Improvement 1: Move arrow overlay
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

                // Improvement 17: Move progress bar (thin, phase-colored)
                ProgressView(value: moveProgress)
                    .tint(phaseColor)
                    .scaleEffect(y: 0.5)
                    .padding(.horizontal, 16)
                    .animation(.spring(response: 0.35, dampingFraction: 0.9), value: viewModel.moveCount)

                // Improvement 13: Tappable move history
                if !viewModel.coachingHistory.isEmpty {
                    moveHistoryBar
                }

                userBar

                // Info area with gesture shortcuts (improvement 22)
                ScrollView {
                    VStack(spacing: 8) {
                        if !viewModel.sessionComplete && (viewModel.bookStatus != .onBook || viewModel.discoveryMode) {
                            guideCard
                                .transition(.opacity)
                        }

                        // Variation switch suggestion
                        if let variation = viewModel.suggestedVariation {
                            variationSwitchCard(variation: variation)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // User coaching always expanded on top, opponent collapsed below
                        userCoachingCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        opponentCoachingCard
                            .transition(.opacity.combined(with: .move(edge: .top)))

                        if viewModel.isCoachingLoading && viewModel.userCoachingText == nil && viewModel.opponentCoachingText == nil {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small).tint(.secondary)
                                Text("Coach is thinking...")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 12)
                            .transition(.opacity)
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.userCoachingText)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.opponentCoachingText)
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.bookStatus)
                    .animation(.spring(response: 0.35, dampingFraction: 0.9), value: viewModel.sessionComplete)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
                // Improvement 22: Gesture shortcuts
                .gesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { value in
                            let horizontal = value.translation.width
                            let vertical = abs(value.translation.height)
                            // Only trigger if mostly horizontal
                            guard abs(horizontal) > vertical else { return }
                            if horizontal < -50, case .userDeviated = viewModel.bookStatus {
                                // Swipe left = undo
                                viewModel.retryLastMove()
                            } else if horizontal > 50, case .userDeviated = viewModel.bookStatus {
                                // Swipe right = continue after deviation
                                Task { await viewModel.continueAfterDeviation() }
                            }
                        }
                )
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
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.correctMoveTrigger)
        .task {
            await viewModel.startSession()
        }
        .sheet(isPresented: $showProUpgrade) {
            ProUpgradeView()
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
        .onChange(of: viewModel.opponentCoachingText) {
            // Re-collapse opponent card when new opponent coaching arrives
            opponentCoachingExpanded = false
        }
        .fullScreenCover(isPresented: $navigateToNextStage) {
            SessionView(
                opening: viewModel.opening,
                lineID: viewModel.activeLine?.id,
                isPro: viewModel.isPro,
                sessionMode: .unguided
            )
            .environment(subscriptionService)
        }
        // Improvement 27: Auto-save session on app backgrounding
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            viewModel.saveSessionToDisk()
        }
    }

    // MARK: - Eval Bar (slim, rounded)

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
        HStack {
            Button {
                viewModel.endSession()
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                    Text("Back")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to opening detail")

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.opening.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)

                if let line = viewModel.activeLine {
                    Text(line.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Session mode indicator pill
            ModeIndicator(
                mode: viewModel.sessionMode == .guided ? "Guided" : "Unguided",
                color: viewModel.sessionMode == .guided ? AppColor.guided : AppColor.unguided
            )

            if viewModel.stats.totalUserMoves > 0 {
                Text("\(Int(viewModel.stats.accuracy * 100))%")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
                    .accessibilityLabel("Your accuracy: \(Int(viewModel.stats.accuracy * 100))%")
            }

            FeedbackToolbarButton(screen: "Session")

            Button {
                Task { await viewModel.restartSession() }
            } label: {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.top, AppSpacing.topBarSafeArea)
        .padding(.bottom, AppSpacing.sm)
    }

    // MARK: - Engine Warning Bar (improvement 15: minimal, only on issues)

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

    // MARK: - Player Bars

    // Improvement 12: Opponent personality
    private var opponentPersonality: OpponentPersonality {
        OpponentPersonality.forELO(viewModel.opponentELO)
    }

    private var opponentBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.opening.color == .white ? Color(white: 0.3) : .white)
                .frame(width: 10, height: 10)
            Text(opponentPersonality.name)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
            Text("\(viewModel.opponentELO)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            if viewModel.isThinking {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini).tint(.secondary)
                    Text("thinking")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(AppColor.elevatedBackground)
    }

    private var userBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.opening.color == .white ? .white : Color(white: 0.3))
                .frame(width: 10, height: 10)
            Text("You")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
            Text("\(viewModel.userELO)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            if viewModel.isUserTurn && !viewModel.isThinking && !viewModel.sessionComplete {
                Text("YOUR MOVE")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.5)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.15), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(AppColor.elevatedBackground)
    }

    // MARK: - Move History Bar (improvement 13)

    private var moveHistoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(viewModel.coachingHistory, id: \.ply) { entry in
                    let ply = entry.ply
                    let moveNum = ply / 2 + 1
                    let isWhite = ply % 2 == 0
                    let label = isWhite ? "\(moveNum)." : ""
                    let san = activeMoves(atPly: ply)?.san ?? "?"

                    Button {
                        tappedMoveCoaching = entry.text
                    } label: {
                        Text("\(label)\(san)")
                            .font(.caption2.monospaced().weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 28)
        .popover(isPresented: Binding(
            get: { tappedMoveCoaching != nil },
            set: { if !$0 { tappedMoveCoaching = nil } }
        )) {
            if let text = tappedMoveCoaching {
                Text(text)
                    .font(.subheadline)
                    .padding(12)
                    .frame(maxWidth: 280)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    private func activeMoves(atPly ply: Int) -> OpeningMove? {
        let moves = viewModel.activeLine?.moves ?? viewModel.opening.mainLine
        guard ply < moves.count else { return nil }
        return moves[ply]
    }

    // MARK: - Guide Card

    private var guideCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Discovery mode: "Find a good move"
                if viewModel.discoveryMode {
                    Image(systemName: "magnifyingglass")
                        .font(.footnote)
                        .foregroundStyle(.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        let count = viewModel.branchPointOptions?.count ?? 2
                        Text("There are \(count) good options here. Can you find one?")
                            .font(.subheadline)
                            .foregroundStyle(.mint)
                        Text("Explore and discover!")
                            .font(.footnote)
                            .foregroundStyle(.mint.opacity(0.6))
                    }
                } else {
                    switch viewModel.bookStatus {
                    case .onBook:
                        EmptyView()

                    case let .userDeviated(expected, _):
                        let isUnguided = viewModel.sessionMode == .unguided
                        let tint: Color = isUnguided ? AppColor.unguided : .orange
                        Image(systemName: isUnguided ? "brain.head.profile" : "arrow.uturn.backward")
                            .font(.footnote)
                            .foregroundStyle(tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(isUnguided
                                 ? "The book move was \(expected.san)"
                                 : "The \(viewModel.opening.name) plays \(expected.san) here")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(tint)
                            if !expected.explanation.isEmpty {
                                Text(expected.explanation)
                                    .font(.footnote)
                                    .foregroundStyle(.primary.opacity(0.7))
                                    .lineLimit(3)
                            }
                            Text(isUnguided
                                 ? "Tap Undo to retry from memory, or keep going."
                                 : "Tap Undo to try the book move, or keep going to practice from here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                    case let .opponentDeviated(expected, played, _):
                        opponentDeviationCard(expected: expected, played: played)
                    }
                }

                Spacer(minLength: 0)
            }

            // Off-book action buttons
            if viewModel.bookStatus != .onBook {
                let tint: Color = {
                    if case .userDeviated = viewModel.bookStatus { return .orange }
                    return .yellow
                }()

                HStack(spacing: 8) {
                    if case .userDeviated = viewModel.bookStatus {
                        // Improvement 20: Contextual undo label
                        Button(action: { viewModel.retryLastMove() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.caption2)
                                Text(undoLabel)
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundStyle(tint)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(tint.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Undo last move")
                        .accessibilityHint("Double tap to undo your last move")

                        Button(action: { Task { await viewModel.continueAfterDeviation() } }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.forward")
                                    .font(.caption2)
                                Text("Continue")
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    } else if case .opponentDeviated = viewModel.bookStatus {
                        Button(action: { Task { await viewModel.restartSession() } }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.caption2)
                                Text("Retry")
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundStyle(tint)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(tint.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if viewModel.offBookExplanation == nil && !viewModel.isExplainingOffBook {
                        Button(action: { Task { await viewModel.requestOffBookExplanation() } }) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                Text("Explain")
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundStyle(tint)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(tint.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .padding(.top, 8)

                if viewModel.isExplainingOffBook {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini).tint(.purple)
                        Text("Analyzing deviation...")
                            .font(.caption)
                            .foregroundStyle(.purple)
                        Spacer()
                    }
                    .padding(.top, 8)
                }

                if let explanation = viewModel.offBookExplanation {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 5) {
                            Image(systemName: "brain.head.profile")
                                .font(.caption2)
                                .foregroundStyle(.purple)
                            Text("Move analysis")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.purple)
                        }
                        Text(explanation)
                            .font(.subheadline)
                            .foregroundStyle(.primary.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 8)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
    }

    // MARK: - Opponent Deviation Card (phase-aware)

    @ViewBuilder
    private func opponentDeviationCard(expected: OpeningMove, played: String) -> some View {
        let phase = viewModel.currentPhase
        let isTraining = phase == .naturalDeviations || phase == .widerVariations

        if isTraining {
            Image(systemName: "figure.boxing")
                .font(.footnote)
                .foregroundStyle(.mint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Time to adapt!")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.mint)
                Text("Your opponent played \(played) instead of the book move \(expected.san). This is part of your training — learn to handle surprises.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let bestMove = viewModel.bestResponseDescription {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle")
                            .font(.caption2)
                        Text("Try \(bestMove)")
                            .font(.footnote.weight(.medium))
                    }
                    .foregroundStyle(.mint)
                }
            }
        } else {
            Image(systemName: "lightbulb.fill")
                .font(.footnote)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text("Your opponent went off-book")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.yellow)
                Text("They played \(played) — the \(viewModel.opening.name) expects \(expected.san) here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let bestMove = viewModel.bestResponseDescription {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle")
                            .font(.caption2)
                        Text("Best response: \(bestMove)")
                            .font(.footnote.weight(.medium))
                    }
                    .foregroundStyle(.yellow)
                } else {
                    Text("Stick to your \(viewModel.opening.name) ideas — develop pieces, control the center.")
                        .font(.footnote)
                        .foregroundStyle(.primary.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Variation Switch Card

    private func variationSwitchCard(variation: OpeningLine) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.footnote)
                .foregroundStyle(.teal)

            VStack(alignment: .leading, spacing: 2) {
                Text("You played into the \(variation.name)!")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.teal)
                Text("Want to continue learning this line?")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.switchToLine(variation)
            } label: {
                Text("Switch")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.teal)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.teal.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
    }

    // MARK: - Coaching Card Wrappers

    @ViewBuilder
    private var userCoachingCard: some View {
        if let text = viewModel.userCoachingText {
            coachingCard(
                label: "Your Next Move",
                text: text,
                tint: Color(red: 1.0, green: 0.84, blue: 0.35),
                isExpanded: .constant(true),
                showExplain: viewModel.userExplainContext != nil,
                explanation: viewModel.userExplanation,
                isExplaining: viewModel.isExplainingUser,
                collapsible: false
            ) {
                Task { await viewModel.requestExplanation(forUserMove: true) }
            }
        }
    }

    // Improvement 16: Compact opponent coaching — single inline line, tappable to expand
    @ViewBuilder
    private var opponentCoachingCard: some View {
        if let text = viewModel.opponentCoachingText {
            coachingCard(
                label: "Opponent moved",
                text: text,
                tint: Color(red: 0.55, green: 0.65, blue: 0.8),
                isExpanded: $opponentCoachingExpanded,
                showExplain: viewModel.opponentExplainContext != nil,
                explanation: viewModel.opponentExplanation,
                isExplaining: viewModel.isExplainingOpponent,
                collapsible: true
            ) {
                Task { await viewModel.requestExplanation(forUserMove: false) }
            }
        }
    }

    // MARK: - Coaching Card (collapsible, rounded)

    private func coachingCard(
        label: String,
        text: String,
        tint: Color,
        isExpanded: Binding<Bool>,
        showExplain: Bool,
        explanation: String?,
        isExplaining: Bool,
        collapsible: Bool = true,
        onExplain: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            // Header row
            Button {
                if collapsible {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isExpanded.wrappedValue.toggle()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(tint).frame(width: 6, height: 6)
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)

                    if !isExpanded.wrappedValue {
                        Text(text)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer()

                    if collapsible {
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.35))
                            .rotationEffect(.degrees(isExpanded.wrappedValue ? -180 : 0))
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded.wrappedValue)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Body
            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 10) {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)

                    if showExplain && explanation == nil && !isExplaining {
                        Button(action: onExplain) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                Text("Explain why")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(tint)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(tint.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if isExplaining {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini).tint(.purple)
                            Text("Thinking deeper...")
                                .font(.caption)
                                .foregroundStyle(.purple)
                        }
                    }

                    if let explanation {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 5) {
                                Image(systemName: "brain.head.profile")
                                    .font(.caption2)
                                    .foregroundStyle(.purple)
                                Text("Deep explanation")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.purple)
                            }
                            Text(explanation)
                                .font(.subheadline)
                                .foregroundStyle(.primary.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12)
    }

    // MARK: - Complete Overlay

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

    /// Returns action for transitioning to next training stage, or nil if not applicable.
    private var nextStageAction: (() -> Void)? {
        switch viewModel.sessionMode {
        case .guided:
            // Guided → Unguided
            return { navigateToNextStage = true }
        case .unguided, .practice:
            // No automatic next stage — user returns to OpeningDetailView to start Practice
            return nil
        }
    }
}
