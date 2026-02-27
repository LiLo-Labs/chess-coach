import SwiftUI
import ChessKit

/// Play full games against bots of varying skill levels.
/// Uses Maia for human-like move prediction, Stockfish as fallback.
struct TrainerModeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppServices.self) private var appServices

    @State private var phase: TrainerPhase = .setup
    @State private var selectedBotELO: Int = 800
    @State private var playerColor: PieceColor = .white
    @State private var gameState: GameState?
    @State private var botThinking = false
    @State private var gameResult: TrainerGameResult?
    @State private var stats = TrainerModeView.loadStats()
    @State private var recentGames = TrainerModeView.loadRecentGames()
    @State private var maiaService: MaiaService?

    enum TrainerPhase {
        case setup
        case playing
        case gameOver
    }

    private var botPersonality: OpponentPersonality {
        OpponentPersonality.forELO(selectedBotELO)
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
                Spacer(minLength: AppSpacing.lg)

                Image(systemName: "figure.fencing")
                    .font(.system(size: 48))
                    .foregroundStyle(.cyan)

                Text("Choose Your Opponent")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)

                // Stats summary
                if stats.gamesPlayed > 0 {
                    HStack(spacing: AppSpacing.lg) {
                        miniStat(label: "Played", value: "\(stats.gamesPlayed)")
                        miniStat(label: "Wins", value: "\(stats.wins)")
                        miniStat(label: "Win Rate", value: "\(Int(stats.winRate * 100))%")
                    }
                    .padding(.horizontal, AppSpacing.xxl)
                }

                // Bot selection
                VStack(spacing: AppSpacing.sm) {
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

                    Picker("Color", selection: $playerColor) {
                        Text("White").tag(PieceColor.white)
                        Text("Black").tag(PieceColor.black)
                        Text("Random").tag(PieceColor.white) // Will randomize on start
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, AppSpacing.xxl)
                }

                // Start button
                Button {
                    startGame()
                } label: {
                    HStack {
                        Text("Play vs \(botPersonality.name)")
                            .font(.body.weight(.semibold))
                        Image(systemName: "play.fill")
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.cyan, in: RoundedRectangle(cornerRadius: AppRadius.lg))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppSpacing.xxl)

                Spacer(minLength: AppSpacing.lg)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func botCard(elo: Int) -> some View {
        let personality = OpponentPersonality.forELO(elo)
        let isSelected = selectedBotELO == elo

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedBotELO = elo }
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "person.fill")
                    .font(.title3)
                    .foregroundStyle(.cyan)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(personality.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.primaryText)
                    Text("\(elo) ELO — \(personality.description)")
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .cyan : AppColor.tertiaryText)
            }
            .padding(AppSpacing.cardPadding)
            .background(
                isSelected ? Color.cyan.opacity(0.08) : AppColor.cardBackground,
                in: RoundedRectangle(cornerRadius: AppRadius.md)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(isSelected ? Color.cyan.opacity(0.4) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Playing

    private func playingView(gameState: GameState) -> some View {
        VStack(spacing: 0) {
            // Bot info bar
            HStack {
                Image(systemName: "person.fill")
                    .foregroundStyle(.cyan)
                Text(botPersonality.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.primaryText)
                Text("(\(selectedBotELO))")
                    .font(.caption)
                    .foregroundStyle(AppColor.tertiaryText)

                Spacer()

                if botThinking {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Thinking...")
                            .font(.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.vertical, AppSpacing.sm)

            // Board
            let isPlayerTurn = (playerColor == .white && gameState.isWhiteTurn) ||
                               (playerColor == .black && !gameState.isWhiteTurn)

            GameBoardView(
                gameState: gameState,
                perspective: playerColor,
                allowInteraction: isPlayerTurn && !botThinking,
                onMove: { _, _ in
                    checkGameEnd(gameState: gameState)
                    if !isGameOver(gameState) {
                        makeBotMove(gameState: gameState)
                    }
                }
            )
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, AppSpacing.sm)

            Spacer()

            // Move count + resign
            HStack {
                Text("Move \(gameState.plyCount / 2 + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppColor.secondaryText)

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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColor.error.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.bottom, AppSpacing.lg)
        }
        .onAppear {
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
                Image(systemName: result.outcome == .win ? "trophy.fill" : result.outcome == .draw ? "equal.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(result.outcome == .win ? AppColor.gold : result.outcome == .draw ? AppColor.info : AppColor.error)

                Text(outcomeText(result.outcome))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)

                VStack(spacing: AppSpacing.sm) {
                    Text("vs \(result.botName) (\(result.botELO))")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                    Text("\(result.moveCount) moves")
                        .font(.caption)
                        .foregroundStyle(AppColor.tertiaryText)
                }

                // Updated stats
                HStack(spacing: AppSpacing.lg) {
                    miniStat(label: "Played", value: "\(stats.gamesPlayed)")
                    miniStat(label: "Wins", value: "\(stats.wins)")
                    miniStat(label: "Win Rate", value: "\(Int(stats.winRate * 100))%")
                }
            }

            HStack(spacing: AppSpacing.md) {
                Button {
                    withAnimation { phase = .setup }
                } label: {
                    Text("New Game")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.cyan, in: RoundedRectangle(cornerRadius: AppRadius.lg))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppSpacing.xxl)

            Spacer()
        }
    }

    // MARK: - Helpers

    private func miniStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(AppColor.primaryText)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppColor.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func outcomeText(_ outcome: TrainerGameResult.Outcome) -> String {
        switch outcome {
        case .win: return "You Win!"
        case .loss: return "You Lost"
        case .draw: return "Draw"
        case .resigned: return "Resigned"
        }
    }

    // MARK: - Game Logic

    private func startGame() {
        let gs = GameState()
        gameState = gs
        gameResult = nil

        // Init Maia for human-like bot play
        if maiaService == nil {
            maiaService = try? MaiaService()
        }

        withAnimation { phase = .playing }
    }

    private func makeBotMove(gameState: GameState) {
        botThinking = true

        Task {
            let fen = gameState.fen
            let legalMoves = gameState.legalMoves.map { $0.description }

            guard !legalMoves.isEmpty else {
                botThinking = false
                checkGameEnd(gameState: gameState)
                return
            }

            // Try Maia first for human-like play
            var selectedMove: String?

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

            // Fallback to Stockfish
            if selectedMove == nil {
                let depth = AppConfig.engine.depthForELO(selectedBotELO)
                selectedMove = await appServices.stockfish.bestMove(fen: fen, depth: depth)
            }

            // Final fallback: random legal move
            if selectedMove == nil {
                selectedMove = legalMoves.randomElement()
            }

            if let move = selectedMove {
                let _ = gameState.makeMoveUCI(move)
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
            // The side that just moved delivered mate
            let lastMoverIsWhite = !gameState.isWhiteTurn
            let playerIsWhite = playerColor == .white
            outcome = lastMoverIsWhite == playerIsWhite ? .win : .loss
        } else {
            outcome = .draw // Stalemate or no legal moves
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
            outcome: outcome,
            moveCount: gameState.plyCount
        )
        gameResult = result

        // Update stats
        switch outcome {
        case .win: stats.wins += 1
        case .loss, .resigned: stats.losses += 1
        case .draw: stats.draws += 1
        }

        // Persist
        Self.saveStats(stats)
        var games = recentGames
        games.insert(result, at: 0)
        if games.count > 50 { games = Array(games.prefix(50)) }
        recentGames = games
        Self.saveRecentGames(games)

        withAnimation { phase = .gameOver }
    }

    // MARK: - Persistence

    private static let statsKey = "chess_coach_trainer_stats"
    private static let gamesKey = "chess_coach_trainer_games"

    static func loadStats() -> TrainerStats {
        guard let data = UserDefaults.standard.data(forKey: statsKey),
              let stats = try? JSONDecoder().decode(TrainerStats.self, from: data) else {
            return TrainerStats()
        }
        return stats
    }

    static func saveStats(_ stats: TrainerStats) {
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: statsKey)
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
