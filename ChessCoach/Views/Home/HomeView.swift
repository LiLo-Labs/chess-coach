import SwiftUI
import ChessKit

struct HomeView: View {
    private let database = OpeningDatabase.shared
    @State private var selectedOpening: Opening?
    @State private var resumeOpening: Opening?
    @State private var resumeLineID: String?
    @State private var showResumePrompt = false
    @State private var streak = PersistenceService.shared.loadStreak()
    @State private var dueReviewCount = 0
    @State private var allFamiliarity: [String: OpeningFamiliarity] = [:]
    @State private var showTokenStore = false
    @State private var showProgressDetail = false
    @State private var importedGames: [ImportedGame] = []
    @State private var selectedMode: HomeMode?
    @State private var appeared = false
    @State private var streakPulse = false
    @State private var tourStep: HomeTourStep? = nil
    @State private var tourAnchors: [HomeTourStep: CGRect] = [:]
    private let progressService = PlayerProgressService.shared
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(TokenService.self) private var tokenService
    @Environment(AppSettings.self) private var settings
    @Environment(AppServices.self) private var appServices

    // MARK: - Computed

    private var activeOpening: Opening? {
        if let id = settings.pickedFreeOpeningID,
           let opening = database.opening(byID: id) { return opening }
        return inProgressOpenings.first
    }

    private var inProgressOpenings: [Opening] {
        let allOpenings = database.openings(forColor: .white) + database.openings(forColor: .black)
        return allOpenings
            .filter { !(allFamiliarity[$0.id]?.positions.isEmpty ?? true) }
            .sorted { (allFamiliarity[$0.id]?.progress ?? 0) > (allFamiliarity[$1.id]?.progress ?? 0) }
    }

    private var totalGamesPlayed: Int {
        progressService.humanELO.gamesPlayed + progressService.engineELO.gamesPlayed
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Late night chess"
        }
    }

    private static let dailyTips: [(quote: String, author: String)] = [
        ("Every chess master was once a beginner.", "Irving Chernev"),
        ("When you see a good move, look for a better one.", "Emanuel Lasker"),
        ("Tactics flow from a superior position.", "Bobby Fischer"),
        ("The pawns are the soul of chess.", "François-André Philidor"),
        ("Chess is the gymnasium of the mind.", "Blaise Pascal"),
        ("In chess, as in life, forethought wins.", "Charles Buxton"),
        ("The threat is stronger than the execution.", "Aron Nimzowitsch"),
        ("Chess is a war over the board. The object is to crush the opponent's mind.", "Bobby Fischer"),
        ("You may learn much more from a game you lose than from a game you win.", "José Raúl Capablanca"),
        ("Chess demands total concentration.", "Bobby Fischer"),
        ("The beauty of a move lies not in its appearance but in the thought behind it.", "Aron Nimzowitsch"),
        ("Not all artists are chess players, but all chess players are artists.", "Marcel Duchamp"),
        ("Chess is the art of analysis.", "Mikhail Botvinnik"),
        ("A bad plan is better than none at all.", "Frank Marshall"),
        ("Patience is the most valuable trait of the endgame player.", "Pal Benko"),
    ]

    private var todayTip: (quote: String, author: String) {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return Self.dailyTips[day % Self.dailyTips.count]
    }

    private var recentGames: [TrainerGameResult] {
        let games = TrainerModeView.loadRecentGames()
        return Array(games.prefix(3))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // MARK: Zone 1 — Hero Card
                    zone1Hero
                        .anchoredForTour(.hero, in: $tourAnchors)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.0), value: appeared)

                    // MARK: Zone 2 — Quick Actions
                    zone2QuickActions
                        .anchoredForTour(.quickActions, in: $tourAnchors)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05), value: appeared)

                    // MARK: Zone 3 — Mode Cards
                    zone3Modes
                        .anchoredForTour(.modeCards, in: $tourAnchors)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: appeared)

                    // MARK: Zone 4 — Tip of the Day
                    zone4Tip
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.15), value: appeared)

                    // MARK: Zone 5 — Recent Games
                    if !recentGames.isEmpty {
                        zone5RecentGames
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: appeared)
                    }

                    // MARK: Zone 6 — Context Strip
                    zone6Context
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.25), value: appeared)
                }
                .padding(.horizontal, AppSpacing.screenPadding)
                .padding(.vertical, AppSpacing.md)
            }
            .background(AppColor.background)
            .navigationTitle("ChessCoach")
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    FeedbackToolbarButton(screen: "Home")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(item: $selectedMode) { mode in
                switch mode {
                case .puzzles:
                    PuzzleModeView()
                case .trainer:
                    TrainerSetupView()
                }
            }
            .onAppear {
                refreshData()
                checkForSavedSession()
                let _ = tokenService.claimDailyBonus()
                withAnimation {
                    appeared = true
                }
                if streak.currentStreak > 0 {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true).delay(0.5)) {
                        streakPulse = true
                    }
                }
                startTourIfNeeded()
            }
            .fullScreenCover(item: $selectedOpening) { opening in
                GamePlayView(mode: .guided(opening: opening, lineID: resumeLineID), isPro: subscriptionService.isPro, tier: subscriptionService.currentTier, stockfish: appServices.stockfish, llmService: appServices.llmService)
                    .environment(subscriptionService)
            }
            .sheet(isPresented: $showTokenStore) {
                TokenStoreView()
            }
            .sheet(isPresented: $showProgressDetail) {
                ProgressDetailView()
            }
            .overlay {
                if let step = tourStep {
                    TourOverlay(
                        step: step,
                        anchors: tourAnchors,
                        onAdvance: { advanceTour() },
                        onDismiss: { dismissTour() }
                    )
                    .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Tour

    private func startTourIfNeeded() {
        guard !settings.hasSeenHomeTour else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeInOut(duration: 0.3)) {
                tourStep = .hero
            }
        }
    }

    private func advanceTour() {
        withAnimation(.easeInOut(duration: 0.25)) {
            switch tourStep {
            case .hero: tourStep = .quickActions
            case .quickActions: tourStep = .modeCards
            case .modeCards: dismissTour()
            case nil: break
            }
        }
    }

    private func dismissTour() {
        withAnimation(.easeInOut(duration: 0.25)) {
            tourStep = nil
        }
        settings.hasSeenHomeTour = true
    }

    // MARK: - Data

    private func refreshData() {
        let allPositions = PersistenceService.shared.loadAllPositionMastery()
        var famByOpening: [String: OpeningFamiliarity] = [:]
        let grouped = Dictionary(grouping: allPositions, by: \.openingID)
        for (openingID, positions) in grouped {
            famByOpening[openingID] = OpeningFamiliarity(openingID: openingID, positions: positions)
        }
        allFamiliarity = famByOpening
        dueReviewCount = SpacedRepScheduler().dueItems().count
        importedGames = PersistenceService.shared.loadImportedGames()
        var s = PersistenceService.shared.loadStreak()
        s.applyStreakFreezeIfNeeded()
        PersistenceService.shared.saveStreak(s)
        streak = s
    }

    private func checkForSavedSession() {
        guard let info = GamePlayViewModel.savedSessionInfo() else { return }
        let allOpenings = database.openings(forColor: .white) + database.openings(forColor: .black)
        if let opening = allOpenings.first(where: { $0.id == info.openingID }) {
            resumeOpening = opening
            resumeLineID = info.lineID
            showResumePrompt = true
        }
    }

    // MARK: - Zone 1: Hero Card

    @ViewBuilder
    private var zone1Hero: some View {
        if let opening = activeOpening {
            let fam = allFamiliarity[opening.id]
            let famColor = fam.map { AppColor.familiarity($0.tier) } ?? AppColor.info
            NavigationLink {
                OpeningDetailView(opening: opening)
            } label: {
                HStack(spacing: AppSpacing.md) {
                    // Mini board
                    heroMiniBoard(for: opening)

                    // Info
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(greeting)
                            .font(.caption)
                            .foregroundStyle(AppColor.secondaryText)

                        Text(opening.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppColor.primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: AppSpacing.sm) {
                            if let fam, !fam.positions.isEmpty {
                                PillBadge(
                                    text: "\(fam.percentage)% — \(fam.tier.displayName)".uppercased(),
                                    color: famColor
                                )
                            }
                            if let fam, !fam.positions.isEmpty {
                                Text("\(fam.positions.count) positions")
                                    .font(.caption)
                                    .foregroundStyle(AppColor.secondaryText)
                            }
                        }

                        // Coach welcome message
                        if let fam {
                            let coach = CoachPersonality.forOpening(opening)
                            let guidance = CoachGuidance(
                                personality: coach,
                                familiarity: fam,
                                openingName: opening.name
                            )
                            Text("\(coach.humanName): \"\(guidance.welcomeBackMessage)\"")
                                .font(.caption)
                                .foregroundStyle(AppColor.secondaryText)
                                .italic()
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, AppSpacing.xxxs)
                        }

                        Text("Continue")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(famColor)
                            .padding(.top, AppSpacing.xxxs)
                    }

                    Spacer(minLength: 0)
                }
                .padding(AppSpacing.cardPadding)
                .background {
                    RoundedRectangle(cornerRadius: AppRadius.lg)
                        .fill(AppColor.cardBackground)
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.lg)
                                .fill(
                                    LinearGradient(
                                        colors: [famColor.opacity(0.12), famColor.opacity(0.03)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                }
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
                .overlay(alignment: .topTrailing) {
                    // Streak flame
                    if streak.currentStreak > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                                .scaleEffect(streakPulse ? 1.15 : 1.0)
                            Text("\(streak.currentStreak)")
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.15), in: Capsule())
                        .padding(AppSpacing.sm)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if showResumePrompt {
                        Button {
                            selectedOpening = opening
                            showResumePrompt = false
                        } label: {
                            Text("Resume")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .buttonBackground(AppColor.success)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .padding(AppSpacing.sm)
                        .padding(.top, streak.currentStreak > 0 ? 32 : 0)
                    }
                }
            }
            .buttonStyle(ScaleButtonStyle())
        } else {
            // No active opening — CTA
            NavigationLink {
                OpeningBrowserView()
            } label: {
                HStack(spacing: AppSpacing.md) {
                    // Starting position mini board
                    GameBoardView(gameState: GameState(), allowInteraction: false)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                        .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(greeting)
                            .font(.caption)
                            .foregroundStyle(AppColor.secondaryText)

                        Text("Choose Your Opening")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppColor.primaryText)

                        Text("Pick a line to start learning")
                            .font(.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.tertiaryText)
                }
                .padding(AppSpacing.cardPadding)
                .cardBackground(cornerRadius: AppRadius.lg)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg)
                        .strokeBorder(
                            LinearGradient(
                                colors: [AppColor.info.opacity(0.4), AppColor.info.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }

    private func heroMiniBoard(for opening: Opening) -> some View {
        let state = GameState()
        for move in opening.mainLine.prefix(6) {
            state.makeMoveUCI(move.uci)
        }
        let perspective: PieceColor = opening.color == .white ? .white : .black
        return GameBoardView(gameState: state, perspective: perspective, allowInteraction: false)
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
            .allowsHitTesting(false)
    }

    // MARK: - Zone 2: Quick Actions

    private var zone2QuickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                if dueReviewCount > 0 {
                    NavigationLink {
                        QuickReviewView()
                    } label: {
                        actionChip(
                            icon: "arrow.counterclockwise",
                            label: "Quick Review",
                            color: AppColor.info,
                            badge: dueReviewCount
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }

                Button { selectedMode = .puzzles } label: {
                    actionChip(icon: "puzzlepiece.fill", label: "Random Puzzle", color: .orange)
                }
                .buttonStyle(ScaleButtonStyle())

                Button { selectedMode = .trainer } label: {
                    actionChip(icon: "figure.fencing", label: "Play Bot", color: .cyan)
                }
                .buttonStyle(ScaleButtonStyle())

                NavigationLink {
                    OpeningBrowserView()
                } label: {
                    actionChip(icon: "book.closed", label: "Browse Openings", color: AppColor.secondaryText)
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
    }

    private func actionChip(icon: String, label: String, color: Color, badge: Int? = nil) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColor.primaryText)
            if let badge, badge > 0 {
                Text("\(badge)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(color, in: Capsule())
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(color.opacity(0.1), in: Capsule())
    }

    // MARK: - Zone 3: Mode Cards (Enhanced)

    private var zone3Modes: some View {
        HStack(spacing: AppSpacing.md) {
            Button { selectedMode = .puzzles } label: {
                modeCardLabel(
                    icon: "puzzlepiece.fill",
                    title: "Puzzles",
                    subtitle: "Tactics training",
                    color: .orange
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Puzzles, Tactics training")

            Button { selectedMode = .trainer } label: {
                modeCardLabel(
                    icon: "figure.fencing",
                    title: "Trainer",
                    subtitle: "Play a full game",
                    color: .cyan,
                    stat: totalGamesPlayed > 0 ? "\(totalGamesPlayed) games" : nil
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Trainer, Play a full game")

            NavigationLink {
                if subscriptionService.isPro {
                    GameImportView()
                } else {
                    GameImportView()
                }
            } label: {
                modeCardLabel(
                    icon: "square.and.arrow.down",
                    title: "Import",
                    subtitle: "Lichess / Chess.com",
                    color: .green,
                    stat: importedGames.isEmpty ? nil : "\(importedGames.count) games"
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Import, Lichess and Chess.com games")
        }
    }

    private func modeCardLabel(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        stat: String? = nil
    ) -> some View {
        VStack(spacing: AppSpacing.xs) {
            ZStack {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(color.opacity(0.1))
                    .blur(radius: 6)
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.primaryText)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(AppColor.tertiaryText)
            if let stat {
                Text(stat)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.md))
    }

    // MARK: - Zone 4: Tip of the Day

    private var zone4Tip: some View {
        let tip = todayTip
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Image(systemName: "quote.opening")
                    .font(.title3)
                    .foregroundStyle(AppColor.tertiaryText)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(tip.quote)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(AppColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("— \(tip.author)")
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .fill(AppColor.cardBackground)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: AppRadius.lg)
                        .fill(AppColor.info.opacity(0.2))
                        .frame(height: 2)
                        .padding(.horizontal, AppSpacing.md)
                }
        }
    }

    // MARK: - Zone 5: Recent Games

    private var zone5RecentGames: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Recent Games")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.primaryText)
                Spacer()
                Text("\(recentGames.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppColor.secondaryText)
            }
            .padding(.horizontal, AppSpacing.cardPadding)
            .padding(.top, AppSpacing.cardPadding)
            .padding(.bottom, AppSpacing.sm)

            ForEach(Array(recentGames.enumerated()), id: \.element.id) { index, game in
                if index > 0 {
                    contextDivider
                }
                recentGameRow(game)
            }
            .padding(.bottom, AppSpacing.sm)
        }
        .cardBackground(cornerRadius: AppRadius.lg)
    }

    private func recentGameRow(_ game: TrainerGameResult) -> some View {
        HStack(spacing: AppSpacing.sm) {
            // Outcome accent strip
            RoundedRectangle(cornerRadius: 2)
                .fill(outcomeColor(game.outcome))
                .frame(width: 3, height: 28)

            // Outcome icon
            Image(systemName: outcomeIcon(game.outcome))
                .font(.subheadline)
                .foregroundStyle(outcomeColor(game.outcome))
                .frame(width: 20)

            // Details
            VStack(alignment: .leading, spacing: 1) {
                Text("\(game.botName) (\(game.botELO))")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
                Text("\(game.moveCount) moves")
                    .font(.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
            }

            Spacer()

            Text(game.date.relativeDisplay)
                .font(.caption2)
                .foregroundStyle(AppColor.tertiaryText)
        }
        .padding(.horizontal, AppSpacing.cardPadding)
        .padding(.vertical, AppSpacing.xs)
    }

    private func outcomeIcon(_ outcome: TrainerGameResult.Outcome) -> String {
        switch outcome {
        case .win: return "crown.fill"
        case .loss, .resigned: return "xmark.circle.fill"
        case .draw: return "equal.circle.fill"
        }
    }

    private func outcomeColor(_ outcome: TrainerGameResult.Outcome) -> Color {
        switch outcome {
        case .win: return AppColor.gold
        case .loss, .resigned: return AppColor.error
        case .draw: return AppColor.secondaryText
        }
    }

    // MARK: - Zone 6: Context Strip (Slimmed)

    private var zone6Context: some View {
        VStack(spacing: 0) {
            // Streak + Daily Goal
            contextRow {
                Label {
                    HStack(spacing: AppSpacing.xs) {
                        Text("\(streak.currentStreak)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(AppColor.primaryText)
                        Text("day streak")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                } icon: {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(streak.currentStreak > 0 ? .orange : AppColor.tertiaryText)
                }

                Spacer()

                HStack(spacing: AppSpacing.xs) {
                    let goalTarget = settings.dailyGoalTarget
                    let goalCompleted = settings.dailyGoalCompleted
                    Text("\(goalCompleted)/\(goalTarget)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppColor.secondaryText)
                    ProgressRing(
                        progress: goalTarget > 0 ? Double(goalCompleted) / Double(goalTarget) : 0,
                        color: goalCompleted >= goalTarget ? AppColor.success : AppColor.info,
                        lineWidth: 2.5,
                        size: 22
                    )
                }
            }

            // Rating
            if totalGamesPlayed > 0 {
                contextDivider

                Button {
                    showProgressDetail = true
                } label: {
                    contextRow {
                        Label {
                            HStack(spacing: AppSpacing.xs) {
                                Text("Rating")
                                    .foregroundStyle(AppColor.primaryText)
                                Text("\(progressService.estimatedRating)")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(AppColor.primaryText)
                            }
                        } icon: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundStyle(AppColor.info)
                        }

                        Spacer()

                        Image(systemName: progressService.trend.icon)
                            .font(.subheadline)
                            .foregroundStyle(trendColor)
                    }
                }
                .buttonStyle(ScaleButtonStyle())
            }

            // Tokens
            contextDivider

            Button {
                showTokenStore = true
            } label: {
                contextRow {
                    Label {
                        Text("Tokens")
                            .foregroundStyle(AppColor.primaryText)
                    } icon: {
                        Image(systemName: "star.circle.fill")
                            .foregroundStyle(AppColor.gold)
                    }
                    Spacer()
                    Text("\(tokenService.balance.balance)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppColor.gold)
                }
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .cardBackground(cornerRadius: AppRadius.lg)
    }

    // MARK: - Helpers

    private func contextRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: AppSpacing.md) {
            content()
        }
        .font(.subheadline)
        .padding(.horizontal, AppSpacing.cardPadding)
        .padding(.vertical, AppSpacing.md)
    }

    private var contextDivider: some View {
        Divider()
            .overlay(AppColor.elevatedBackground)
            .padding(.horizontal, AppSpacing.cardPadding)
    }

    private var trendColor: Color {
        switch progressService.trend {
        case .improving: return AppColor.success
        case .declining: return AppColor.error
        case .stable: return AppColor.secondaryText
        }
    }
}

// MARK: - Mode Navigation

private enum HomeMode: Hashable {
    case puzzles
    case trainer
}

// MARK: - Date Helpers

private extension Date {
    var relativeDisplay: String {
        let now = Date()
        let interval = now.timeIntervalSince(self)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        let days = Int(interval / 86400)
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days)d ago" }
        return "\(days / 7)w ago"
    }
}

// MARK: - Home Tour

enum HomeTourStep: CaseIterable {
    case hero
    case quickActions
    case modeCards

    var title: String {
        switch self {
        case .hero: return "Your Opening"
        case .quickActions: return "Quick Actions"
        case .modeCards: return "Training Modes"
        }
    }

    var body: String {
        switch self {
        case .hero: return "Tap here to continue your current opening or pick a new one."
        case .quickActions: return "Jump into reviews, puzzles, or bot games."
        case .modeCards: return "Deeper sessions with puzzle sets and personalised bots."
        }
    }

    var icon: String {
        switch self {
        case .hero: return "chess.board"
        case .quickActions: return "bolt.fill"
        case .modeCards: return "gamecontroller.fill"
        }
    }

    var stepIndex: Int {
        switch self {
        case .hero: return 0
        case .quickActions: return 1
        case .modeCards: return 2
        }
    }
}

// MARK: - Tour Anchor Extension

private extension View {
    func anchoredForTour(_ step: HomeTourStep, in anchors: Binding<[HomeTourStep: CGRect]>) -> some View {
        self.background {
            GeometryReader { geo in
                Color.clear
                    .preference(key: TourAnchorKey.self, value: [step: geo.frame(in: .global)])
            }
        }
        .onPreferenceChange(TourAnchorKey.self) { value in
            anchors.wrappedValue.merge(value) { _, new in new }
        }
    }
}

private struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [HomeTourStep: CGRect] = [:]
    static func reduce(value: inout [HomeTourStep: CGRect], nextValue: () -> [HomeTourStep: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Tour Overlay

private struct TourOverlay: View {
    let step: HomeTourStep
    let anchors: [HomeTourStep: CGRect]
    let onAdvance: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { geo in
            let highlightRect = anchors[step] ?? .zero
            let inset: CGFloat = 8
            let expandedRect = highlightRect.insetBy(dx: -inset, dy: -inset)

            ZStack {
                // Dark scrim with cutout
                Canvas { context, size in
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .color(.black.opacity(0.6))
                    )
                    context.blendMode = .destinationOut
                    context.fill(
                        Path(roundedRect: expandedRect, cornerRadius: 16),
                        with: .color(.white)
                    )
                }
                .compositingGroup()
                .ignoresSafeArea()

                // Tooltip card
                let tooltipBelow = expandedRect.maxY + 12 + 140 < geo.size.height
                let tooltipY = tooltipBelow ? expandedRect.maxY + 12 : expandedRect.minY - 12 - 140

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: step.icon)
                            .font(.title3)
                            .foregroundStyle(.cyan)
                        Text(step.title)
                            .font(.headline)
                            .foregroundStyle(AppColor.primaryText)
                    }

                    Text(step.body)
                        .font(.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        // Step dots
                        HStack(spacing: 6) {
                            ForEach(HomeTourStep.allCases, id: \.stepIndex) { s in
                                Circle()
                                    .fill(s == step ? Color.cyan : AppColor.tertiaryText.opacity(0.4))
                                    .frame(width: 6, height: 6)
                            }
                        }

                        Spacer()

                        Button("Skip") {
                            onDismiss()
                        }
                        .font(.caption)
                        .foregroundStyle(AppColor.tertiaryText)

                        Button("Got it") {
                            onAdvance()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.cyan)
                    }
                }
                .padding(AppSpacing.cardPadding)
                .cardBackground(cornerRadius: AppRadius.lg)
                .padding(.horizontal, AppSpacing.screenPadding)
                .position(
                    x: geo.size.width / 2,
                    y: tooltipY + 70
                )
            }
        }
        .allowsHitTesting(true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tour: \(step.title). \(step.body)")
    }
}
