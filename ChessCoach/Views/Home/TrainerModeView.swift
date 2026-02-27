import SwiftUI
import ChessKit

/// Play full games against bots of varying skill levels.
/// Dual engine mode: Human-Like (Maia) vs Engine (Stockfish).
struct TrainerModeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppServices.self) private var appServices

    @State private var phase: TrainerPhase = .setup
    @State private var selectedBotELO: Int = 800
    @State private var playerColor: PieceColor = .white
    @State private var engineMode: TrainerEngineMode = .humanLike
    @State private var gameState: GameState?
    @State private var botThinking = false
    @State private var gameResult: TrainerGameResult?
    @State private var maiaService: MaiaService?

    // Chat / atmosphere
    @State private var botMessage: String?
    @State private var showBotMessage = false
    @State private var moveFlashSquare: String?

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
        OpponentPersonality.forELO(selectedBotELO)
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
            case .playing:
                if let gs = gameState {
                    playingView(gameState: gs)
                }
            case .gameOver:
                gameOverView
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
                Image(systemName: botPersonality.icon)
                    .font(.system(size: 52))
                    .foregroundStyle(accentColor)
                    .symbolEffect(.bounce, value: selectedBotELO)

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

                    ForEach(botELOs, id: \.self) { elo in
                        botCard(elo: elo)
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
                .buttonStyle(.plain)
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
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.md + 3))
        .padding(.horizontal, AppSpacing.xxl)
    }

    // MARK: - Bot Card

    private func botCard(elo: Int) -> some View {
        let personality = OpponentPersonality.forELO(elo)
        let isSelected = selectedBotELO == elo

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedBotELO = elo }
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: personality.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? accentColor : AppColor.tertiaryText)
                    .frame(width: 32)

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
    }

    private func colorButton(_ color: PieceColor, label: String, icon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { playerColor = color }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(color == .white ? Color.white : Color(white: 0.2))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColor.primaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                playerColor == color ? accentColor.opacity(0.12) : AppColor.cardBackground,
                in: RoundedRectangle(cornerRadius: AppRadius.md)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(playerColor == color ? accentColor.opacity(0.4) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Playing

    private func playingView(gameState: GameState) -> some View {
        VStack(spacing: 0) {
            // Bot info bar with personality
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: botPersonality.icon)
                    .font(.title3)
                    .foregroundStyle(accentColor)

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
                            .font(.system(size: 9))
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

            // Bot chat bubble
            if showBotMessage, let message = botMessage {
                HStack {
                    Image(systemName: botPersonality.icon)
                        .font(.caption)
                        .foregroundStyle(accentColor)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(AppColor.primaryText)
                        .lineLimit(2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, AppSpacing.screenPadding)
                .padding(.bottom, AppSpacing.xs)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            // Thinking indicator
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

            // Board
            let isPlayerTurn = (playerColor == .white && gameState.isWhiteTurn) ||
                               (playerColor == .black && !gameState.isWhiteTurn)

            GameBoardView(
                gameState: gameState,
                perspective: playerColor,
                allowInteraction: isPlayerTurn && !botThinking,
                onMove: { _, _ in
                    // Play sound
                    SoundService.shared.play(.move)
                    SoundService.shared.hapticPiecePlaced()

                    checkGameEnd(gameState: gameState)
                    if !isGameOver(gameState) {
                        makeBotMove(gameState: gameState)
                    }
                }
            )
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, AppSpacing.sm)

            Spacer()

            // Bottom bar
            HStack {
                // Undo (if desired, could add later)
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
                    .padding(.vertical, 8)
                    .background(AppColor.error.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.bottom, AppSpacing.lg)
        }
        .onAppear {
            // Greeting
            showBotReaction(botPersonality.greeting)

            // If bot plays first (player is black), make bot move
            if playerColor == .black && gameState.isWhiteTurn {
                makeBotMove(gameState: gameState)
            }
        }
    }

    // MARK: - Game Over

    private var gameOverView: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            if let result = gameResult {
                // Result icon with animation
                Image(systemName: resultIcon(result.outcome))
                    .font(.system(size: 64))
                    .foregroundStyle(resultColor(result.outcome))
                    .symbolEffect(.bounce, value: result.id)

                Text(outcomeText(result.outcome))
                    .font(.title.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)

                // Bot reaction
                if let reaction = botReactionForResult(result.outcome) {
                    HStack(spacing: 6) {
                        Image(systemName: botPersonality.icon)
                            .font(.caption)
                            .foregroundStyle(accentColor)
                        Text(reaction)
                            .font(.subheadline)
                            .foregroundStyle(AppColor.secondaryText)
                            .italic()
                    }
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
                .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.md))
                .padding(.horizontal, AppSpacing.xxl)

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
                .buttonStyle(.plain)

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
        let gs = GameState()
        gameState = gs
        gameResult = nil
        botMessage = nil
        showBotMessage = false

        // Init Maia for human-like bot play
        if maiaService == nil && engineMode == .humanLike {
            maiaService = try? MaiaService()
        }

        withAnimation(.spring(response: 0.3)) { phase = .playing }
    }

    private func makeBotMove(gameState: GameState) {
        botThinking = true

        Task { @MainActor in
            let fen = gameState.fen
            let legalMoves = gameState.legalMoves.map { $0.description }

            guard !legalMoves.isEmpty else {
                botThinking = false
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
                // Maia for human-like play
                if let maia = maiaService {
                    if let predictions = try? await maia.predictMove(
                        fen: fen,
                        legalMoves: legalMoves,
                        eloSelf: selectedBotELO,
                        eloOppo: settings.userELO
                    ), let topMove = predictions.first {
                        selectedMove = topMove.move
                    }
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
            }

            // Final fallback: random legal move
            if selectedMove == nil {
                selectedMove = legalMoves.randomElement()
            }

            if let move = selectedMove {
                // Check if it's a capture before making the move
                let isCapture = gameState.isCapture(move)
                let isCheck = false // We'll detect after

                let _ = gameState.makeMoveUCI(move)

                // Play appropriate sound
                if gameState.isMate || gameState.isCheck {
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

            botThinking = false
            checkGameEnd(gameState: gameState)
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

        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { phase = .gameOver }
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

