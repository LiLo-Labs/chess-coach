import SwiftUI
import ChessKit

/// Trainer setup screen: bot selection, color picker, engine mode toggle.
/// Navigates to GamePlayView(mode: .trainer(...)) on start.
struct TrainerSetupView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedBotELO: Int = 800
    @State private var playerColor: PieceColor = .white
    @State private var useRandomColor: Bool = false
    @State private var engineMode: TrainerEngineMode = .humanLike
    @State private var customDepth: Int = 12
    @State private var navigateToGame = false

    // Stats
    @State private var humanStats = TrainerModeView.loadStats(mode: .humanLike)
    @State private var engineStats = TrainerModeView.loadStats(mode: .engine)
    @State private var recentGames = TrainerModeView.loadRecentGames()

    private let botELOs = [500, 800, 1000, 1200, 1400, 1600]

    private var botPersonality: OpponentPersonality {
        switch engineMode {
        case .humanLike: OpponentPersonality.forELO(selectedBotELO)
        case .engine: OpponentPersonality.engineForELO(selectedBotELO)
        case .custom: OpponentPersonality.customEngine(depth: customDepth)
        }
    }

    private var currentStats: TrainerStats {
        engineMode == .humanLike ? humanStats : engineStats
    }

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

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xxl) {
                Spacer(minLength: AppSpacing.md)

                BotAvatarView(personality: botPersonality, size: .large)
                    .id("\(selectedBotELO)-\(engineMode.rawValue)")

                Text(botPersonality.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)

                Text(botPersonality.description)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)

                engineModePicker

                if currentStats.gamesPlayed > 0 {
                    statsBar(stats: currentStats, label: engineMode.displayName)
                }

                // Bot selection / custom depth
                if engineMode == .custom {
                    customDepthControls
                } else {
                    VStack(spacing: AppSpacing.sm) {
                        Text("Choose Opponent")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColor.secondaryText)

                        ForEach(Array(botELOs.enumerated()), id: \.element) { index, elo in
                            botCard(elo: elo)
                                .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                                .animation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.05), value: selectedBotELO)
                        }
                    }
                    .padding(.horizontal, AppSpacing.screenPadding)
                }

                // Color picker
                VStack(spacing: AppSpacing.sm) {
                    Text("Play as")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.secondaryText)

                    HStack(spacing: AppSpacing.md) {
                        colorButton(.white, label: "White")
                        colorButton(.black, label: "Black")
                        randomColorButton
                    }
                    .padding(.horizontal, AppSpacing.xxl)
                }

                // Start button
                Button {
                    var resolvedColor = playerColor
                    if useRandomColor {
                        resolvedColor = Bool.random() ? .white : .black
                    }
                    playerColor = resolvedColor
                    navigateToGame = true
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
        .background(AppColor.background)
        .preferredColorScheme(.dark)
        .navigationTitle("Trainer")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $navigateToGame) {
            GamePlayView(
                mode: .trainer(
                    personality: botPersonality,
                    engineMode: engineMode,
                    playerColor: playerColor,
                    botELO: selectedBotELO
                ),
                isPro: subscriptionService.isPro,
                tier: subscriptionService.currentTier
            )
            .environment(settings)
            .environment(subscriptionService)
        }
        .onAppear {
            humanStats = TrainerModeView.loadStats(mode: .humanLike)
            engineStats = TrainerModeView.loadStats(mode: .engine)
            recentGames = TrainerModeView.loadRecentGames()
        }
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

    // MARK: - Custom Depth Controls

    private var customDepthControls: some View {
        VStack(spacing: AppSpacing.md) {
            Text("Search Depth")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.secondaryText)

            Text("\(customDepth)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(AppColor.primaryText)
                .contentTransition(.numericText())

            HStack {
                Text("Shallow (fast)")
                    .font(.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
                Spacer()
                Text("Deep (strong)")
                    .font(.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
            }

            Slider(value: Binding(
                get: { Double(customDepth) },
                set: { customDepth = Int($0) }
            ), in: 1...20, step: 1)
            .tint(accentColor)

            Text(customDepthStrengthLabel)
                .font(.subheadline)
                .foregroundStyle(AppColor.secondaryText)
        }
        .padding(.horizontal, AppSpacing.xxl)
    }

    private var customDepthStrengthLabel: String {
        switch customDepth {
        case 1...3: return "Very weak — instant moves"
        case 4...6: return "Beginner strength"
        case 7...9: return "Casual club player"
        case 10...12: return "Strong club player"
        case 13...15: return "Expert level"
        case 16...18: return "Master strength"
        default: return "Maximum strength — slow"
        }
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

    // MARK: - Color Buttons

    private func colorButton(_ color: PieceColor, label: String) -> some View {
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
        .accessibilityLabel("\(label): \(stats.gamesPlayed) played, \(stats.wins) wins, \(stats.losses) losses")
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
}
