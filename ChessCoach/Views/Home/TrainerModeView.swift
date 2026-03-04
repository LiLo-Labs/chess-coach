import SwiftUI
import ChessKit

/// Play full games against bots of varying skill levels.
/// Dual engine mode: Human-Like (Maia) vs Engine (Stockfish).
struct TrainerModeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppServices.self) private var appServices
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: TrainerPhase = .setup
    @State private var selectedBotELO: Int = 800
    @State private var playerColor: PieceColor = .white
    @State private var useRandomColor: Bool = false
    @State private var engineMode: TrainerEngineMode = .humanLike
    @State private var gameState: GameState?
    @State private var botThinking = false
    @State private var gameResult: TrainerGameResult?
    @State private var maiaService: MaiaService?

    // Chat / atmosphere
    @State private var botMessage: String?
    @State private var showBotMessage = false
    @State private var moveFlashSquare: String?

    // Coaching integration
    @State private var currentOpening: OpeningDetection = .none
    @State private var holisticDetection: HolisticDetection = .none
    @State private var showCoachChat = false
    @State private var coachChatState = CoachChatState()
    @State private var coachingFeed: [TrainerCoachingEntry] = []
    @State private var isEvaluating = false
    @State private var lastEvalScore: Int = 0  // Stockfish eval before player's move
    @State private var showLeaveConfirmation = false
    @State private var showProUpgrade = false
    @State private var showIntersectingOpenings = false
    private let openingDetector = OpeningDetector()
    private let holisticDetector = HolisticDetector()

    // Accessibility move input
    @State private var voiceOverMoveText = ""

    // Replay state
    @State private var replayPly: Int?
    @State private var replayGameState: GameState?
    private var isReplaying: Bool { replayPly != nil }
    private var displayGameState: GameState? { replayGameState ?? gameState }

    // Separate stats per engine mode
    @State private var humanStats = Self.loadStats(mode: .humanLike)
    @State private var engineStats = Self.loadStats(mode: .engine)
    @State private var recentGames = Self.loadRecentGames()

    enum TrainerPhase {
        case setup
        case playing
        case gameOver
    }

    private var botPersonality: OpponentPersonality {
        switch engineMode {
        case .humanLike: OpponentPersonality.forELO(selectedBotELO)
        case .engine: OpponentPersonality.engineForELO(selectedBotELO)
        case .custom: OpponentPersonality.customEngine(depth: 12)
        }
    }

    private var currentStats: TrainerStats {
        engineMode == .humanLike ? humanStats : engineStats
    }

    private let botELOs = [500, 800, 1000, 1200, 1400, 1600]

    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            switch phase {
            case .setup:
                setupView
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            case .playing:
                if let gs = gameState {
                    playingView(gameState: gs)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            case .gameOver:
                gameOverView
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Trainer")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Setup

    private var setupView: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xxl) {
                Spacer(minLength: AppSpacing.md)

                // Bot avatar
                BotAvatarView(personality: botPersonality, size: .large)
                    .id("\(selectedBotELO)-\(engineMode.rawValue)") // force re-render on ELO or mode change

                Text(botPersonality.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)

                Text(botPersonality.description)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)

                // Engine mode toggle
                engineModePicker

                // Stats for current mode
                if currentStats.gamesPlayed > 0 {
                    statsBar(stats: currentStats, label: engineMode.displayName)
                }

                // Bot selection
                VStack(spacing: AppSpacing.sm) {
                    Text("Choose Opponent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.secondaryText)

                    ForEach(Array(botELOs.enumerated()), id: \.element) { index, elo in
                        botCard(elo: elo)
                            .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                            .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.05), value: phase)
                    }
                }
                .padding(.horizontal, AppSpacing.screenPadding)

                // Color picker
                VStack(spacing: AppSpacing.sm) {
                    Text("Play as")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.secondaryText)

                    HStack(spacing: AppSpacing.md) {
                        colorButton(.white, label: "White", icon: "circle.fill")
                        colorButton(.black, label: "Black", icon: "circle.fill")
                        randomColorButton
                    }
                    .padding(.horizontal, AppSpacing.xxl)
                }

                // Start button
                Button {
                    startGame()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: engineMode.icon)
                        Text("Play vs \(botPersonality.name)")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accentColor, in: RoundedRectangle(cornerRadius: AppRadius.lg))
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, AppSpacing.xxl)

                Spacer(minLength: AppSpacing.lg)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Engine Mode Picker

    private var engineModePicker: some View {
        HStack(spacing: 0) {
            ForEach(TrainerEngineMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { engineMode = mode }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.icon)
                            .font(.body)
                        Text(mode.displayName)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(engineMode == mode ? .white : AppColor.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        engineMode == mode ? accentColor : Color.clear,
                        in: RoundedRectangle(cornerRadius: AppRadius.md)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .cardBackground(cornerRadius: AppRadius.md + 3)
        .padding(.horizontal, AppSpacing.xxl)
    }

    // MARK: - Bot Card

    private func botCard(elo: Int) -> some View {
        let personality = engineMode == .engine
            ? OpponentPersonality.engineForELO(elo)
            : OpponentPersonality.forELO(elo)
        let isSelected = selectedBotELO == elo

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedBotELO = elo }
        } label: {
            HStack(spacing: AppSpacing.md) {
                BotAvatarView(personality: personality, size: .small)
                    .opacity(isSelected ? 1.0 : 0.6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(personality.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.primaryText)
                    Text("\(elo) — \(personality.description)")
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(AppSpacing.cardPadding)
            .background(
                isSelected ? accentColor.opacity(0.08) : AppColor.cardBackground,
                in: RoundedRectangle(cornerRadius: AppRadius.md)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(isSelected ? accentColor.opacity(0.4) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(personality.name), \(elo) rating\(isSelected ? ", selected" : "")")
    }

    private func colorButton(_ color: PieceColor, label: String, icon: String) -> some View {
        let isSelected = !useRandomColor && playerColor == color
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                playerColor = color
                useRandomColor = false
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color == .white ? Color.white : Color(white: 0.2))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
                    .accessibilityHidden(true)
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColor.primaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isSelected ? accentColor.opacity(0.12) : AppColor.cardBackground,
                in: RoundedRectangle(cornerRadius: AppRadius.md)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(isSelected ? accentColor.opacity(0.4) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play as \(label)\(isSelected ? ", selected" : "")")
    }

    private var randomColorButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                useRandomColor = true
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "dice.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColor.secondaryText)
                Text("Random")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColor.primaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                useRandomColor ? accentColor.opacity(0.12) : AppColor.cardBackground,
                in: RoundedRectangle(cornerRadius: AppRadius.md)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(useRandomColor ? accentColor.opacity(0.4) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play as random color\(useRandomColor ? ", selected" : "")")
    }

    // MARK: - Playing

    private func playingView(gameState: GameState) -> some View {
        GeometryReader { geo in
            let boardSize = min(max(1, geo.size.width - (AppSpacing.sm * 2)), geo.size.height * 0.55)

            VStack(spacing: 0) {
                // Bot info bar with personality
                HStack(spacing: AppSpacing.sm) {
                    BotAvatarView(personality: botPersonality, size: .small)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(botPersonality.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppColor.primaryText)
                            Text("(\(selectedBotELO))")
                                .font(.caption2)
                                .foregroundStyle(AppColor.tertiaryText)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: engineMode.icon)
                                .font(.caption2)
                            Text(engineMode.displayName)
                                .font(.caption2)
                        }
                        .foregroundStyle(AppColor.tertiaryText)
                    }

                    Spacer()

                    // Move counter
                    Text("Move \(gameState.plyCount / 2 + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppColor.secondaryText)
                }
                .padding(.horizontal, AppSpacing.screenPadding)
                .padding(.vertical, AppSpacing.sm)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Playing \(botPersonality.name), rated \(selectedBotELO), \(engineMode.displayName) mode. Move \(gameState.plyCount / 2 + 1).")

                // Opening bar / chat bubble / thinking — overlaid in fixed-height slot
                ZStack(alignment: .bottom) {
                    Color.clear.frame(height: 44)

                    if !botThinking && !showBotMessage {
                        if settings.holisticOpeningHints, holisticDetection.whiteFramework.primary != nil || holisticDetection.blackFramework.primary != nil {
                            // Dual-perspective opening bar
                            holisticOpeningBar
                        } else if let match = currentOpening.best {
                            // Classic single-line opening bar
                            classicOpeningBar(match: match)
                        }
                    }

                    if showBotMessage, let message = botMessage {
                        HStack {
                            Image(systemName: botPersonality.icon)
                                .font(.caption)
                                .foregroundStyle(accentColor)
                                .accessibilityHidden(true)
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(AppColor.primaryText)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, AppSpacing.screenPadding)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(botPersonality.name) says: \(message)")
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }

                    if botThinking {
                        HStack(spacing: 6) {
                            ThinkingDotsView()
                            Text(botPersonality.randomReaction(from: botPersonality.thinkingPhrases))
                                .font(.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                        .padding(.vertical, 4)
                        .transition(.opacity)
                    }
                }
                .clipped()
                .accessibilityElement(children: .contain)

                // Board
                let isPlayerTurn = (playerColor == .white && gameState.isWhiteTurn) ||
                                   (playerColor == .black && !gameState.isWhiteTurn)

                GameBoardView(
                    gameState: gameState,
                    perspective: playerColor,
                    allowInteraction: isPlayerTurn && !botThinking,
                    onMove: { from, to in
                        // Play sound
                        SoundService.shared.play(.move)
                        SoundService.shared.hapticPiecePlaced()

                        let moveUCI = "\(from)\(to)"
                        let preMoveDet = currentOpening
                        // GameBoardView already applied the move, so gameState.fen is post-move.
                        // Reconstruct pre-move FEN by replaying all moves except the last.
                        let preMoveFen: String = {
                            let preMoveHistory = Array(gameState.moveHistory.dropLast())
                            let temp = GameState()
                            for m in preMoveHistory {
                                temp.makeMove(from: m.from, to: m.to, promotion: m.promotion)
                            }
                            return temp.fen
                        }()
                        updateOpeningDetection(gameState: gameState)
                        evaluatePlayerMove(gameState: gameState, moveUCI: moveUCI, preMoveFen: preMoveFen, preMoveDetection: preMoveDet)
                        checkGameEnd(gameState: gameState)
                        if !isGameOver(gameState) {
                            makeBotMove(gameState: gameState)
                        }
                    }
                )
                .frame(width: boardSize, height: boardSize)
                .padding(.horizontal, AppSpacing.sm)

                // VoiceOver move input — only shown when VoiceOver is active
                if UIAccessibility.isVoiceOverRunning && isPlayerTurn && !botThinking {
                    HStack(spacing: 8) {
                        TextField("Type move (e.g. e4, Nf3)", text: $voiceOverMoveText)
                            .textFieldStyle(.plain)
                            .font(.subheadline)
                            .foregroundStyle(AppColor.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppColor.inputBackground, in: RoundedRectangle(cornerRadius: 8))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        Button {
                            submitVoiceOverMove(gameState: gameState)
                        } label: {
                            Text("Move")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .background(AppColor.guided, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(voiceOverMoveText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, AppSpacing.screenPadding)
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Enter move using algebraic notation")
                }

                // Coaching feed in remaining space
                VStack(spacing: 0) {
                    if !coachingFeed.isEmpty || isEvaluating {
                        TrainerCoachingFeedView(
                            entries: coachingFeed,
                            isLoading: isEvaluating,
                            onRequestExplanation: { entry in
                                if subscriptionService.isFeatureUnlocked(.deepExplanation) {
                                    requestExplanation(for: entry)
                                } else {
                                    showProUpgrade = true
                                }
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Spacer(minLength: 0)
                    }

                    // Bottom bar
                    HStack {
                        // Leave — subtle, no stats recorded
                        Button {
                            showLeaveConfirmation = true
                        } label: {
                            Text("Leave")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(AppColor.secondaryText)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)

                        // Coach chat toggle (if LLM available)
                        if appServices.llmService != nil, currentOpening.best != nil {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    showCoachChat.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "brain.head.profile")
                                        .font(.caption2)
                                    Text("Ask Coach")
                                        .font(.caption.weight(.medium))
                                }
                                .foregroundStyle(AppColor.practice)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 44)
                                .background(AppColor.practice.opacity(0.1), in: Capsule())
                            }
                            .buttonStyle(ScaleButtonStyle())
                        }

                        Spacer()

                        Button {
                            resign(gameState: gameState)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "flag.fill")
                                    .font(.caption2)
                                Text("Resign")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundStyle(AppColor.error)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(AppColor.error.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    .padding(.horizontal, AppSpacing.screenPadding)
                    .padding(.bottom, AppSpacing.lg)
                }
            }
        }
        .onAppear {
            // Greeting
            showBotReaction(botPersonality.greeting)

            // If bot plays first (player is black), make bot move
            if playerColor == .black && gameState.isWhiteTurn {
                makeBotMove(gameState: gameState)
            }
        }
        .overlay(alignment: .trailing) {
            if showCoachChat, let match = currentOpening.best {
                CoachChatPanel(
                    opening: match.opening,
                    fen: gameState.fen,
                    moveHistory: gameState.moveHistory.map { "\($0.from)\($0.to)" },
                    currentPly: gameState.plyCount,
                    coachPersonality: CoachPersonality.forOpening(match.opening),
                    isEngineMode: engineMode != .humanLike,
                    isPresented: $showCoachChat,
                    chatState: coachChatState
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .alert("Leave Game?", isPresented: $showLeaveConfirmation) {
            Button("Leave", role: .destructive) {
                withAnimation(.spring(response: 0.3)) { phase = .setup }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The game will not count as a loss.")
        }
        .sheet(isPresented: $showProUpgrade) {
            ProUpgradeView()
        }
    }

    // MARK: - Game Over

    private var gameOverView: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            if let result = gameResult {
                // Result icon with scale-in animation
                Image(systemName: resultIcon(result.outcome))
                    .font(.system(size: 64))
                    .foregroundStyle(resultColor(result.outcome))
                    .transition(.scale(scale: 0).combined(with: .opacity))
                    .accessibilityHidden(true)

                Text(outcomeText(result.outcome))
                    .font(.title.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)
                    .transition(.opacity)

                // Bot reaction
                if let reaction = botReactionForResult(result.outcome) {
                    HStack(spacing: 6) {
                        Image(systemName: botPersonality.icon)
                            .font(.caption)
                            .foregroundStyle(accentColor)
                            .accessibilityHidden(true)
                        Text(reaction)
                            .font(.subheadline)
                            .foregroundStyle(AppColor.secondaryText)
                            .italic()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(botPersonality.name) says: \(reaction)")
                }

                // Game info
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
                            Image(systemName: engineMode.icon)
                                .font(.caption2)
                                .accessibilityHidden(true)
                            Text(engineMode.displayName)
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Opponent: \(result.botName), rated \(result.botELO). Mode: \(engineMode.displayName). Moves: \(result.moveCount / 2).")

                // Stats for this mode
                statsBar(stats: currentStats, label: "\(engineMode.displayName) Record")
                    .padding(.horizontal, AppSpacing.xxl)
            }

            // Buttons
            VStack(spacing: AppSpacing.sm) {
                Button {
                    startGame()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Rematch")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(accentColor, in: RoundedRectangle(cornerRadius: AppRadius.lg))
                }
                .buttonStyle(ScaleButtonStyle())

                Button {
                    withAnimation(.spring(response: 0.3)) { phase = .setup }
                } label: {
                    Text("Change Opponent")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColor.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppSpacing.xxl)

            Spacer()
        }
    }

    // MARK: - Stats Bar

    private func statsBar(stats: TrainerStats, label: String) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppColor.tertiaryText)

            HStack(spacing: AppSpacing.lg) {
                miniStat(label: "Played", value: "\(stats.gamesPlayed)")
                miniStat(label: "Wins", value: "\(stats.wins)", color: AppColor.success)
                miniStat(label: "Losses", value: "\(stats.losses)", color: AppColor.error)
                miniStat(label: "Win Rate", value: "\(Int(stats.winRate * 100))%")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(stats.gamesPlayed) played, \(stats.wins) wins, \(stats.losses) losses, \(Int(stats.winRate * 100)) percent win rate")
    }

    // MARK: - Opening Bar

    /// Classic single-line opening bar (used when holistic mode is off).
    private func classicOpeningBar(match: OpeningMatch) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "book.fill")
                .font(.caption2)
                .foregroundStyle(.cyan)
                .accessibilityHidden(true)
            Text(match.variationName ?? match.opening.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColor.primaryText)
                .lineLimit(1)
            if !match.nextBookMoves.isEmpty {
                Text("In book")
                    .font(.caption2)
                    .foregroundStyle(AppColor.success)
            } else {
                Text("Out of book")
                    .font(.caption2)
                    .foregroundStyle(AppColor.warning)
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.vertical, 4)
        .background(Color.cyan.opacity(0.05))
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(match.variationName ?? match.opening.name), \(match.nextBookMoves.isEmpty ? "out of book" : "in book")")
    }

    /// Dual-perspective opening bar showing White and Black frameworks.
    @ViewBuilder
    private var holisticOpeningBar: some View {
        let hd = holisticDetection
        let whiteName = hd.whiteFramework.primary?.variationName ?? hd.whiteFramework.primary?.opening.name
        let blackName = hd.blackFramework.primary?.variationName ?? hd.blackFramework.primary?.opening.name
        let intersectCount = hd.intersectingOpenings.count

        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "book.fill")
                .font(.caption2)
                .foregroundStyle(.cyan)
                .accessibilityHidden(true)

            if let wName = whiteName {
                Text("W:")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(wName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
            }

            if whiteName != nil && blackName != nil {
                Text("|")
                    .font(.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
            }

            if let bName = blackName {
                Text("B:")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.gray)
                Text(bName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppColor.secondaryText)
                    .lineLimit(1)
            }

            if hd.isInBook {
                Text("In book")
                    .font(.caption2)
                    .foregroundStyle(AppColor.success)
            } else if whiteName != nil || blackName != nil {
                Text("Out of book")
                    .font(.caption2)
                    .foregroundStyle(AppColor.warning)
            }

            Spacer()

            if intersectCount > 1 {
                Button {
                    showIntersectingOpenings = true
                } label: {
                    Text("\(intersectCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.vertical, 4)
        .background(Color.cyan.opacity(0.05))
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(holisticOpeningAccessibilityLabel)
        .sheet(isPresented: $showIntersectingOpenings) {
            intersectingOpeningsSheet
        }
    }

    private var holisticOpeningAccessibilityLabel: String {
        let hd = holisticDetection
        var parts: [String] = []
        if let w = hd.whiteFramework.primary {
            parts.append("White: \(w.variationName ?? w.opening.name)")
        }
        if let b = hd.blackFramework.primary {
            parts.append("Black: \(b.variationName ?? b.opening.name)")
        }
        parts.append(hd.isInBook ? "in book" : "out of book")
        let count = hd.intersectingOpenings.count
        if count > 1 {
            parts.append("\(count) openings match")
        }
        return parts.joined(separator: ", ")
    }

    private var intersectingOpeningsSheet: some View {
        NavigationStack {
            List {
                let hd = holisticDetection
                if !hd.intersectingOpenings.isEmpty {
                    Section("Matching Openings") {
                        ForEach(Array(hd.intersectingOpenings.enumerated()), id: \.offset) { _, match in
                            HStack {
                                Text(match.opening.color == .white ? "W" : "B")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(match.opening.color == .white ? .white : .gray)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.variationName ?? match.opening.name)
                                        .font(.subheadline.weight(.medium))
                                    if !match.nextBookMoves.isEmpty {
                                        Text("\(match.nextBookMoves.count) continuation\(match.nextBookMoves.count == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(AppColor.secondaryText)
                                    }
                                }
                                Spacer()
                                Text("depth \(match.matchDepth)")
                                    .font(.caption2)
                                    .foregroundStyle(AppColor.tertiaryText)
                            }
                        }
                    }

                    if !hd.branchAlternatives.isEmpty {
                        Section("Branch Points") {
                            ForEach(Array(hd.branchAlternatives.enumerated()), id: \.offset) { _, branch in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Ply \(branch.ply)")
                                        .font(.caption.weight(.semibold))
                                    ForEach(Array(branch.alternatives.prefix(3).enumerated()), id: \.offset) { _, alt in
                                        Text(alt.opening.name)
                                            .font(.caption)
                                            .foregroundStyle(AppColor.secondaryText)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Opening Detection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showIntersectingOpenings = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private var accentColor: Color {
        switch botPersonality.accentColorName {
        case "green": return .green
        case "teal": return .teal
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "orange": return .orange
        default: return .cyan
        }
    }

    private func miniStat(label: String, value: String, color: Color = AppColor.primaryText) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppColor.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func resultIcon(_ outcome: TrainerGameResult.Outcome) -> String {
        switch outcome {
        case .win: return "trophy.fill"
        case .loss: return "xmark.circle.fill"
        case .draw: return "equal.circle.fill"
        case .resigned: return "flag.fill"
        }
    }

    private func resultColor(_ outcome: TrainerGameResult.Outcome) -> Color {
        switch outcome {
        case .win: return AppColor.gold
        case .loss: return AppColor.error
        case .draw: return AppColor.info
        case .resigned: return AppColor.error
        }
    }

    private func outcomeText(_ outcome: TrainerGameResult.Outcome) -> String {
        switch outcome {
        case .win: return "Victory!"
        case .loss: return "Defeated"
        case .draw: return "Draw"
        case .resigned: return "Resigned"
        }
    }

    private func botReactionForResult(_ outcome: TrainerGameResult.Outcome) -> String? {
        switch outcome {
        case .win: return botPersonality.randomReaction(from: botPersonality.onLoss)
        case .loss, .resigned: return botPersonality.randomReaction(from: botPersonality.onWin)
        case .draw: return "Good game — evenly matched."
        }
    }

    // MARK: - Bot Chat

    private func showBotReaction(_ message: String) {
        botMessage = message
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showBotMessage = true
        }
        // Auto-dismiss after a few seconds
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation(.easeOut(duration: 0.3)) {
                showBotMessage = false
            }
        }
    }

    // MARK: - Game Logic

    private func startGame() {
        // Resolve random color before starting
        if useRandomColor {
            playerColor = Bool.random() ? .white : .black
        }

        let gs = GameState()
        gameState = gs
        gameResult = nil
        botMessage = nil
        showBotMessage = false
        currentOpening = .none
        holisticDetection = .none
        showIntersectingOpenings = false
        showCoachChat = false
        coachChatState = CoachChatState()
        coachingFeed = []
        isEvaluating = false
        lastEvalScore = 0
        moveFlashSquare = nil
        botThinking = false
        replayPly = nil
        replayGameState = nil

        // Init Maia for human-like bot play
        if maiaService == nil && engineMode == .humanLike {
            maiaService = try? MaiaService()
        }

        withAnimation(.spring(response: 0.3)) { phase = .playing }
    }

    private func makeBotMove(gameState: GameState) {
        withAnimation(.easeInOut(duration: 0.2)) { botThinking = true }

        Task { @MainActor in
            let fen = gameState.fen
            let legalMoves = gameState.legalMoves.map { $0.description }

            guard !legalMoves.isEmpty else {
                withAnimation(.easeOut(duration: 0.2)) { botThinking = false }
                checkGameEnd(gameState: gameState)
                return
            }

            // Realistic thinking delay
            let delay = Double.random(in: botPersonality.thinkingDelayRange)
            try? await Task.sleep(for: .seconds(delay))

            // Select move based on engine mode
            var selectedMove: String?

            switch engineMode {
            case .humanLike:
                // Maia for human-like play — use sampleMove for probabilistic
                // selection so the bot doesn't play deterministically
                if let maia = maiaService {
                    let history = gameState.moveHistory.map {
                        "\($0.from)\($0.to)\($0.promotion?.rawValue ?? "")"
                    }
                    selectedMove = try? await maia.sampleMove(
                        fen: fen,
                        legalMoves: legalMoves,
                        eloSelf: selectedBotELO,
                        eloOppo: settings.userELO,
                        temperature: 1.0,
                        recentMoves: history
                    )
                }
                // Fallback to Stockfish if Maia unavailable
                if selectedMove == nil {
                    let depth = AppConfig.engine.depthForELO(selectedBotELO)
                    selectedMove = await appServices.stockfish.bestMove(fen: fen, depth: depth)
                }

            case .engine:
                // Pure Stockfish at capped depth
                let depth = AppConfig.engine.depthForELO(selectedBotELO)
                selectedMove = await appServices.stockfish.bestMove(fen: fen, depth: depth)

            case .custom:
                let depth = botPersonality.customDepth ?? 12
                selectedMove = await appServices.stockfish.bestMove(fen: fen, depth: depth)
            }

            // Final fallback: random legal move
            if selectedMove == nil {
                selectedMove = legalMoves.randomElement()
            }

            // Compute SAN before applying the move
            let botMoveSAN = selectedMove.flatMap { gameState.sanForUCI($0) } ?? selectedMove ?? "?"

            if let move = selectedMove {
                // Check if it's a capture before making the move
                let isCapture = gameState.isCapture(move)

                let _ = gameState.makeMoveUCI(move)

                let isCheck = gameState.isCheck

                // Play appropriate sound
                if gameState.isMate || isCheck {
                    SoundService.shared.play(.check)
                } else if isCapture {
                    SoundService.shared.play(.capture)
                    SoundService.shared.hapticPiecePlaced()
                } else {
                    SoundService.shared.play(.move)
                    SoundService.shared.hapticPiecePlaced()
                }

                // Occasional bot reaction
                if gameState.plyCount > 4 && Bool.random() && Bool.random() {
                    // ~25% chance of a chat message
                    if isCapture {
                        showBotReaction(botPersonality.randomReaction(from: botPersonality.onCapture))
                    } else if isCheck {
                        showBotReaction(botPersonality.randomReaction(from: botPersonality.onCheck))
                    }
                }
            }

            withAnimation(.easeOut(duration: 0.2)) { botThinking = false }
            if let move = selectedMove {
                // Announce bot move for VoiceOver
                let sanLabel = OpeningMove.friendlyName(from: botMoveSAN)
                AccessibilityNotification.Announcement("\(botPersonality.name) played \(sanLabel). Your turn.").post()

                addBotMoveEntry(gameState: gameState, moveUCI: move, moveSAN: botMoveSAN)
                // Quick eval to set baseline for next player move's cpLoss
                if let eval = await appServices.stockfish.evaluate(fen: gameState.fen, depth: 8) {
                    lastEvalScore = eval.score
                }
            }
            updateOpeningDetection(gameState: gameState)
            checkGameEnd(gameState: gameState)
        }
    }

    private func updateOpeningDetection(gameState: GameState) {
        let uciMoves = gameState.moveHistory.map { "\($0.from)\($0.to)\($0.promotion?.rawValue ?? "")" }
        currentOpening = openingDetector.detect(moves: uciMoves)
        if settings.holisticOpeningHints {
            holisticDetection = holisticDetector.detect(moves: uciMoves)
        }
    }

    // MARK: - Coaching Feed

    /// Evaluate the player's move asynchronously and add a coaching entry.
    /// Runs Stockfish eval in the background — doesn't block the game.
    private func evaluatePlayerMove(gameState: GameState, moveUCI: String, preMoveFen: String? = nil, preMoveDetection: OpeningDetection? = nil) {
        let ply = gameState.plyCount
        let fen = gameState.fen
        // Compute SAN from pre-move position if available
        let moveSAN: String
        if let pmFen = preMoveFen {
            moveSAN = GameState.sanForUCI(moveUCI, inFEN: pmFen)
        } else {
            moveSAN = moveUCI
        }
        let moveNumber = (ply + 1) / 2
        // Use pre-move detection for book move checking (nextBookMoves are continuations
        // from the position BEFORE the move, so they contain the move just played).
        // Check ALL matched openings — not just "best" — because at branch points
        // (e.g., after 1. d4 d5) multiple openings match equally and we don't yet
        // know which one the player is following until they make their next move.
        let preDetection = preMoveDetection ?? currentOpening
        let postDetection = currentOpening
        // When holistic mode is on, use all intersecting openings for broader book coverage
        let allPreBookMoves: [OpeningMove]
        if settings.holisticOpeningHints {
            // Deduplicate by UCI across holistic + classic matches
            var seen = Set<String>()
            allPreBookMoves = (holisticDetection.allNextBookMoves + preDetection.matches.flatMap(\.nextBookMoves))
                .filter { seen.insert($0.uci).inserted }
        } else {
            allPreBookMoves = preDetection.matches.flatMap(\.nextBookMoves)
        }
        let isBookMove = allPreBookMoves.contains(where: { $0.uci == moveUCI })
        let isInBook = isBookMove || (postDetection.best?.nextBookMoves.isEmpty == false)
        let openingName = (postDetection.best ?? preDetection.best)?.opening.name
        let scoreBefore = lastEvalScore
        let playerIsWhite = playerColor == .white

        Task { @MainActor in
            isEvaluating = true

            // Get post-move eval from Stockfish
            let eval = await appServices.stockfish.evaluate(fen: fen, depth: AppConfig.engine.evalDepth)
            let scoreAfter = eval?.score ?? 0

            // Compute soundness
            let cpLoss = SoundnessCalculator.centipawnLoss(
                scoreBefore: scoreBefore,
                scoreAfter: scoreAfter,
                playerIsWhite: playerIsWhite
            )
            let soundness = SoundnessCalculator.ceiling(centipawnLoss: cpLoss, userELO: settings.userELO)

            // Categorize the move
            let category: MoveCategory
            if isBookMove || isInBook {
                category = soundness >= 80 ? .goodMove : .okayMove
            } else if cpLoss < 30 {
                category = .goodMove
            } else if cpLoss < 100 {
                category = .okayMove
            } else {
                category = .mistake
            }

            let scoreCategory = ScoreCategory.from(score: soundness)

            // Build coaching text using personality witticisms
            let personality: CoachPersonality
            if let matchedOpening = (postDetection.best ?? preDetection.best)?.opening {
                personality = CoachPersonality.forOpening(matchedOpening)
            } else {
                personality = .defaultPersonality
            }
            let coaching: String
            switch category {
            case .goodMove:
                coaching = personality.witticism(for: .goodMove)
            case .okayMove:
                if !isBookMove, let bm = allPreBookMoves.first {
                    let quip = personality.witticism(for: .okayMove)
                    coaching = "\(quip) The book move is \(bm.san)."
                } else {
                    coaching = personality.witticism(for: .okayMove)
                }
            case .mistake:
                if !isBookMove, let bm = allPreBookMoves.first {
                    let quip = personality.witticism(for: .mistake)
                    coaching = "\(quip) The recommended move here is \(bm.san)."
                } else if let bestUCI = eval?.bestMove {
                    let san = GameState.sanForUCI(bestUCI, inFEN: fen)
                    let quip = personality.witticism(for: .mistake)
                    coaching = "\(quip) Better was \(san)."
                } else {
                    coaching = personality.witticism(for: .mistake)
                }
            default:
                coaching = personality.witticism(for: .goodMove)
            }

            let entry = TrainerCoachingEntry(
                ply: ply,
                moveNumber: moveNumber,
                moveSAN: moveSAN,
                isPlayerMove: true,
                coaching: coaching,
                category: category,
                soundness: soundness,
                scoreCategory: scoreCategory,
                openingName: openingName,
                isInBook: isInBook,
                fen: fen
            )

            withAnimation(.easeInOut(duration: 0.2)) {
                coachingFeed.append(entry)
                isEvaluating = false
            }

            // Announce evaluation result for VoiceOver
            let qualityLabel = entry.scoreCategory?.displayName ?? category.feedLabel
            AccessibilityNotification.Announcement("\(qualityLabel) move. \(coaching)").post()

            // Mirror coaching into chat history so coach chat has full context
            let moveLabel = OpeningMove.friendlyName(from: moveSAN)
            coachChatState.appendMessage(role: "coach", text: "[\(moveLabel)] \(coaching)")

            // Store eval for next move's cpLoss calculation
            lastEvalScore = scoreAfter
        }
    }

    /// Add a brief coaching entry for the bot's move (non-blocking, no eval needed).
    private func addBotMoveEntry(gameState: GameState, moveUCI: String, moveSAN: String? = nil) {
        let ply = gameState.plyCount
        let moveNumber = (ply + 1) / 2
        let detection = currentOpening
        let isInBook = detection.best?.nextBookMoves.isEmpty == false
        let openingName = detection.best?.opening.name
        let isDeviation = detection.best != nil && !isInBook

        let opponentColorName = playerColor == .white ? "Black" : "White"
        let coaching: String
        if isDeviation, let bestOpening = detection.best?.opening,
           let catalogue = bestOpening.opponentResponses {
            let movesSoFar = gameState.moveHistory.dropLast().map { "\($0.from)\($0.to)" }
            if let response = catalogue.matchResponse(moveUCI: moveUCI, afterMoves: Array(movesSoFar)) {
                coaching = "\(opponentColorName) played the \(response.name). \(response.planAdjustment)"
            } else if let name = openingName {
                coaching = "\(opponentColorName) went off the \(name) plan."
            } else {
                coaching = "\(opponentColorName)'s move."
            }
        } else if isDeviation, let name = openingName {
            coaching = "\(opponentColorName) went off the \(name) plan."
        } else if isInBook, let name = openingName {
            coaching = "Standard \(name) response by \(opponentColorName)."
        } else {
            coaching = "\(opponentColorName)'s move."
        }

        let entry = TrainerCoachingEntry(
            ply: ply,
            moveNumber: moveNumber,
            moveSAN: moveSAN ?? moveUCI,
            isPlayerMove: false,
            coaching: coaching,
            category: isDeviation ? .deviation : .opponentMove,
            soundness: nil,
            scoreCategory: nil,
            openingName: openingName,
            isInBook: isInBook,
            fen: gameState.fen
        )

        withAnimation(.easeInOut(duration: 0.2)) {
            coachingFeed.append(entry)
        }

        // Mirror coaching into chat history so coach chat has full context
        let botMoveLabel = OpeningMove.friendlyName(from: moveSAN ?? moveUCI)
        coachChatState.appendMessage(role: "coach", text: "[\(botMoveLabel)] \(coaching)")
    }

    // MARK: - Explain in Detail (LLM)

    /// Request an LLM-generated explanation for a coaching feed entry.
    private func requestExplanation(for entry: TrainerCoachingEntry) {
        guard subscriptionService.isFeatureUnlocked(.deepExplanation) else { return }
        guard !entry.isExplaining, entry.explanation == nil else { return }
        guard let fen = entry.fen else { return }

        entry.isExplaining = true

        let detection = currentOpening
        let openingName = detection.best?.opening.name ?? entry.openingName ?? "this opening"
        let playerIsWhite = playerColor == .white
        let studentColor = playerIsWhite ? "White" : "Black"
        let opponentColor = playerIsWhite ? "Black" : "White"
        let userELO = settings.userELO

        // Build move history string from game state
        let moveHistoryStr: String = {
            guard let gs = gameState else { return "" }
            return gs.moveHistory.enumerated().map { i, m in
                let uci = "\(m.from)\(m.to)\(m.promotion?.rawValue ?? "")"
                return i % 2 == 0 ? "\(i / 2 + 1). \(uci)" : uci
            }.joined(separator: " ")
        }()

        let boardState = LLMService.boardStateSummary(fen: fen, studentColor: studentColor)
        let occupied = LLMService.occupiedSquares(fen: fen)

        let moveDisplay = entry.moveSAN
        let coaching = entry.coaching

        let perspective = entry.isPlayerMove
            ? "The student (\(studentColor)) played \(moveDisplay). Explain why this move matters."
            : "The opponent (\(opponentColor)) played \(moveDisplay). Explain what it means for the student."

        let prompt = PromptCatalog.explanationPrompt(params: .init(
            openingName: openingName,
            studentColor: studentColor,
            opponentColor: opponentColor,
            userELO: userELO,
            perspective: perspective,
            moveHistoryStr: moveHistoryStr,
            boardState: boardState,
            occupiedSquares: occupied,
            moveDisplay: moveDisplay,
            moveUCI: "",
            moveFraming: "\(entry.moveNumber). \(moveDisplay)",
            coachingText: coaching,
            forUserMove: entry.isPlayerMove
        ))

        Task {
            do {
                let response = try await appServices.llmService.generate(prompt: prompt, maxTokens: AppConfig.tokens.explanation)
                let parsed = CoachingValidator.parse(response: response)
                let validated = CoachingValidator.validate(parsed: parsed, fen: fen) ?? parsed.text
                await MainActor.run {
                    entry.explanation = validated
                    entry.isExplaining = false
                }
            } catch {
                await MainActor.run {
                    entry.explanation = "Couldn't generate explanation right now."
                    entry.isExplaining = false
                }
            }
        }
    }

    private func isGameOver(_ gameState: GameState) -> Bool {
        gameState.isMate || gameState.legalMoves.isEmpty
    }

    private func checkGameEnd(gameState: GameState) {
        guard isGameOver(gameState) else { return }

        let outcome: TrainerGameResult.Outcome
        if gameState.isMate {
            let lastMoverIsWhite = !gameState.isWhiteTurn
            let playerIsWhite = playerColor == .white
            outcome = lastMoverIsWhite == playerIsWhite ? .win : .loss
        } else {
            outcome = .draw
        }

        endGame(outcome: outcome, gameState: gameState)
    }

    private func resign(gameState: GameState) {
        endGame(outcome: .resigned, gameState: gameState)
    }

    private func endGame(outcome: TrainerGameResult.Outcome, gameState: GameState) {
        let result = TrainerGameResult(
            playerColor: playerColor == .white ? "white" : "black",
            botELO: selectedBotELO,
            botName: botPersonality.name,
            engineMode: engineMode,
            outcome: outcome,
            moveCount: gameState.plyCount
        )
        gameResult = result

        // Play result sound
        switch outcome {
        case .win:
            SoundService.shared.play(.phaseUp)
            SoundService.shared.hapticLineComplete()
        case .loss, .resigned:
            SoundService.shared.hapticDeviation()
        case .draw:
            SoundService.shared.hapticPiecePlaced()
        }

        // Update stats for current engine mode
        switch outcome {
        case .win:
            if engineMode == .humanLike { humanStats.wins += 1 } else { engineStats.wins += 1 }
        case .loss, .resigned:
            if engineMode == .humanLike { humanStats.losses += 1 } else { engineStats.losses += 1 }
        case .draw:
            if engineMode == .humanLike { humanStats.draws += 1 } else { engineStats.draws += 1 }
        }

        // Persist
        Self.saveStats(humanStats, mode: .humanLike)
        Self.saveStats(engineStats, mode: .engine)
        var games = recentGames
        games.insert(result, at: 0)
        if games.count > 50 { games = Array(games.prefix(50)) }
        recentGames = games
        Self.saveRecentGames(games)

        // Record game in progress service (ELO estimation, opening accuracy)
        let uciMoves = gameState.moveHistory.map { "\($0.from)\($0.to)\($0.promotion?.rawValue ?? "")" }
        let detector = OpeningDetector()
        let detection = detector.detect(moves: uciMoves)
        let openingID = detection.best?.opening.id

        PlayerProgressService.shared.recordGame(
            opponentELO: selectedBotELO,
            outcome: outcome,
            engineMode: engineMode,
            openingID: openingID,
            moveCount: gameState.plyCount
        )

        // Announce game result for VoiceOver
        let resultText: String
        switch outcome {
        case .win: resultText = "Game over. You win!"
        case .loss: resultText = "Game over. \(botPersonality.name) wins."
        case .draw: resultText = "Game over. Draw."
        case .resigned: resultText = "Game over. You resigned."
        }
        AccessibilityNotification.Announcement(resultText).post()

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { phase = .gameOver }
    }

    // MARK: - VoiceOver Move Input

    /// Submit a move typed in algebraic notation (e.g. "e4", "Nf3", "O-O").
    private func submitVoiceOverMove(gameState: GameState) {
        let input = voiceOverMoveText.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }

        // Try to match input against legal moves by comparing SAN
        let legalMoves = gameState.legalMoves
        var matchedUCI: String?
        for move in legalMoves {
            let san = SanSerialization.default.san(for: move, in: gameState.game)
            // Compare case-insensitively, strip check/mate symbols
            let cleanSAN = san.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "#", with: "")
            let cleanInput = input.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "#", with: "")
            if cleanSAN.lowercased() == cleanInput.lowercased() {
                matchedUCI = "\(move.from.coordinate)\(move.to.coordinate)"
                if let promo = move.promotion {
                    matchedUCI! += promo.rawValue.lowercased()
                }
                break
            }
        }

        // Also try matching raw UCI input (e.g. "e2e4")
        if matchedUCI == nil && input.count >= 4 {
            let from = String(input.prefix(2)).lowercased()
            let to = String(input.dropFirst(2).prefix(2)).lowercased()
            if legalMoves.contains(where: { $0.from.coordinate == from && $0.to.coordinate == to }) {
                matchedUCI = "\(from)\(to)"
                if input.count == 5 {
                    matchedUCI! += String(input.last!).lowercased()
                }
            }
        }

        guard let uci = matchedUCI else {
            AccessibilityNotification.Announcement("Invalid move: \(input). Try again.").post()
            return
        }

        voiceOverMoveText = ""

        // Apply the move — same flow as board tap
        let preMoveDet = currentOpening
        let preMoveFen = gameState.fen
        if gameState.makeMoveUCI(uci) {
            SoundService.shared.play(.move)
            SoundService.shared.hapticPiecePlaced()
            updateOpeningDetection(gameState: gameState)
            evaluatePlayerMove(gameState: gameState, moveUCI: uci, preMoveFen: preMoveFen, preMoveDetection: preMoveDet)
            checkGameEnd(gameState: gameState)
            if !isGameOver(gameState) {
                makeBotMove(gameState: gameState)
            }
        } else {
            AccessibilityNotification.Announcement("Move could not be applied. Try again.").post()
        }
    }

    // MARK: - Replay

    private func enterReplay(ply: Int, gameState: GameState) {
        let maxPly = gameState.plyCount
        let clampedPly = max(0, min(ply, maxPly))
        if clampedPly == maxPly {
            exitReplay()
            return
        }
        replayPly = clampedPly
        let tempState = GameState()
        let history = gameState.moveHistory
        for i in 0..<clampedPly {
            guard i < history.count else { break }
            tempState.makeMove(from: history[i].from, to: history[i].to, promotion: history[i].promotion)
        }
        replayGameState = tempState
    }

    private func exitReplay() {
        replayPly = nil
        replayGameState = nil
    }

    // MARK: - Replay Bar

    private func trainerReplayBar(gameState: GameState) -> some View {
        HStack(spacing: 4) {
            Button { enterReplay(ply: 0, gameState: gameState) } label: {
                Image(systemName: "backward.end.fill")
                    .font(.body)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(isReplaying && replayPly == 0)

            Button {
                let current = replayPly ?? gameState.plyCount
                enterReplay(ply: current - 1, gameState: gameState)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(isReplaying && replayPly == 0)

            Spacer()

            if isReplaying {
                Text("Move \(replayPly ?? 0) of \(gameState.plyCount)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("Ply \(gameState.plyCount)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                let current = replayPly ?? gameState.plyCount
                enterReplay(ply: current + 1, gameState: gameState)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!isReplaying)

            Button { exitReplay() } label: {
                Image(systemName: "forward.end.fill")
                    .font(.body)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!isReplaying)

            if isReplaying {
                Button { exitReplay() } label: {
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

    // MARK: - Persistence (separate keys per engine mode)

    private static func statsKey(mode: TrainerEngineMode) -> String {
        "chess_coach_trainer_stats_\(mode.rawValue)"
    }
    private static let gamesKey = "chess_coach_trainer_games_v2"

    static func loadStats(mode: TrainerEngineMode) -> TrainerStats {
        guard let data = UserDefaults.standard.data(forKey: statsKey(mode: mode)),
              let stats = try? JSONDecoder().decode(TrainerStats.self, from: data) else {
            return TrainerStats()
        }
        return stats
    }

    static func saveStats(_ stats: TrainerStats, mode: TrainerEngineMode) {
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: statsKey(mode: mode))
        }
    }

    static func loadRecentGames() -> [TrainerGameResult] {
        guard let data = UserDefaults.standard.data(forKey: gamesKey),
              let games = try? JSONDecoder().decode([TrainerGameResult].self, from: data) else {
            return []
        }
        return games
    }

    static func saveRecentGames(_ games: [TrainerGameResult]) {
        if let data = try? JSONEncoder().encode(games) {
            UserDefaults.standard.set(data, forKey: gamesKey)
        }
    }
}

