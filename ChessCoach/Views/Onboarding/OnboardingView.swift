import SwiftUI
import ChessKit

/// First-run onboarding — origin story, openings intro, coaching demo, Pro, privacy, skill.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppServices.self) private var appServices
    @State private var page = 0

    var onComplete: () -> Void = {}

    private let totalPages = 8

    // Per-element stagger states
    @State private var showIcon = false
    @State private var showTitle = false
    @State private var showItems: [Bool] = Array(repeating: false, count: 6)
    @State private var showButton = false

    // Page 1 — breathing board
    @State private var boardBreathing = false

    // Page 2 — tech showcase stagger
    @State private var showTechCards: [Bool] = [false, false, false]

    // Page 6 — pro showcase stagger
    @State private var showProFeatures: [Bool] = [false, false, false, false]

    // Page 3 — coaching demo state
    @State private var tryItGameState: GameState? = nil
    @State private var puzzleSolved = false
    @State private var showPuzzleConfetti = false
    @State private var coachingStep = 0
    @State private var boardReady = false

    // Page 7 — assessment
    @State private var showELOAssessment = false

    var body: some View {
        ZStack {
            AppColor.background
                .ignoresSafeArea()

            TabView(selection: $page) {
                storyPage.tag(0)
                openingsPage.tag(1)
                techPage.tag(2)
                coachingDemoPage.tag(3)
                proPage.tag(4)
                proShowcasePage.tag(5)
                privacyPage.tag(6)
                skillPage.tag(7)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack {
                Spacer()
                HStack(alignment: .center) {
                    if page < totalPages - 1 {
                        Button("Skip") { onComplete() }
                            .font(.subheadline)
                            .foregroundStyle(AppColor.secondaryText)
                            .padding(.leading, AppSpacing.xxxl)
                            .accessibilityLabel("Skip introduction")
                    }
                    Spacer()
                    Text("\(page + 1) of \(totalPages)")
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                        .padding(.trailing, AppSpacing.xxxl)
                }
                .padding(.bottom, AppSpacing.lg)
            }

            if showPuzzleConfetti {
                ConfettiView()
                    .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: page) { _, _ in triggerEntryAnimations() }
        .onAppear { triggerEntryAnimations() }
    }

    // MARK: - Animations

    private func triggerEntryAnimations() {
        showIcon = false
        showTitle = false
        showItems = Array(repeating: false, count: 6)
        showTechCards = [false, false, false]
        showProFeatures = [false, false, false, false]
        showButton = false

        // Reset coaching demo state when leaving page 3
        if page != 3 {
            puzzleSolved = false
            showPuzzleConfetti = false
            coachingStep = 0
            boardReady = false
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1)) {
            showIcon = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3)) {
            showTitle = true
        }
        for i in 0..<6 {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.45 + Double(i) * 0.12)) {
                showItems[i] = true
            }
        }
        for i in 0..<3 {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3 + Double(i) * 0.2)) {
                showTechCards[i] = true
            }
        }
        for i in 0..<4 {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4 + Double(i) * 0.18)) {
                showProFeatures[i] = true
            }
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85).delay(1.0)) {
            showButton = true
        }
    }

    private func itemVisible(_ index: Int) -> Bool {
        index < showItems.count && showItems[index]
    }

    // MARK: - Page 1: The Story

    private var storyPage: some View {
        ZStack {
            // Ghosted background board
            GameBoardView(gameState: GameState(), allowInteraction: false)
                .frame(width: 220, height: 220)
                .opacity(0.15)
                .blur(radius: 3)
                .scaleEffect(boardBreathing ? 1.03 : 0.97)
                .onAppear {
                    withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                        boardBreathing = true
                    }
                }

            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "crown.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(AppColor.gold)
                    .symbolEffect(.pulse, options: .repeating.speed(0.4))
                    .scaleEffect(showIcon ? 1.0 : 0.3)
                    .opacity(showIcon ? 1 : 0)

                VStack(spacing: 16) {
                    Text("ChessCoach")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppColor.primaryText)

                    VStack(spacing: 8) {
                        Text("You learned the pieces.")
                            .opacity(itemVisible(0) ? 1 : 0)
                            .offset(y: itemVisible(0) ? 0 : 10)
                        Text("You played some games.")
                            .opacity(itemVisible(1) ? 1 : 0)
                            .offset(y: itemVisible(1) ? 0 : 10)
                        Text("Then you hit a wall.")
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColor.gold)
                            .opacity(itemVisible(2) ? 1 : 0)
                            .offset(y: itemVisible(2) ? 0 : 10)
                    }
                    .font(.title3)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
                }
                .offset(y: showTitle ? 0 : 20)
                .opacity(showTitle ? 1 : 0)

                Text("This app was built for exactly that moment.\nThe gap between knowing the rules and actually improving.")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xxxl)
                    .opacity(itemVisible(3) ? 1 : 0)
                    .offset(y: itemVisible(3) ? 0 : 10)

                Spacer()
                Spacer()
                nextButton
                    .opacity(showButton ? 1 : 0)
                    .offset(y: showButton ? 0 : 10)
            }
        }
    }

    // MARK: - Page 2: Why Openings Matter

    private var openingsPage: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()

            // Auto-playing preview board
            if let demoOpening = demoOpening {
                OpeningPreviewBoard(opening: demoOpening)
                    .scaleEffect(showIcon ? 1.0 : 0.85)
                    .opacity(showIcon ? 1 : 0)
            }

            VStack(spacing: 8) {
                Text("The Missing Piece? Openings.")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)

                Text("The first moves of every chess game follow patterns\nthat have been studied for centuries.")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .offset(y: showTitle ? 0 : 20)
            .opacity(showTitle ? 1 : 0)
            .padding(.horizontal, AppSpacing.lg)

            VStack(alignment: .leading, spacing: 14) {
                animatedBullet(1, icon: "map.fill", color: .cyan,
                               text: "An opening gives you **a plan from move one**")
                animatedBullet(2, icon: "person.2.fill", color: .orange,
                               text: "Pros don't memorize — they **understand the ideas**")
                animatedBullet(3, icon: "chart.line.uptrend.xyaxis", color: .green,
                               text: "Even one opening can **transform your results**")
            }
            .padding(.horizontal, AppSpacing.xxxl)

            Spacer()
            nextButton
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 10)
        }
    }

    private var demoOpening: Opening? {
        let db = OpeningDatabase.shared
        return db.opening(named: "Italian Game") ?? db.openings.first
    }

    // MARK: - Page 3: What's Under the Hood

    private var techPage: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()

            Text("What's Under the Hood")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)
                .offset(y: showTitle ? 0 : 20)
                .opacity(showTitle ? 1 : 0)

            VStack(spacing: 14) {
                techCard(
                    index: 0,
                    icon: "person.fill",
                    color: .cyan,
                    title: "Maia — Human-Like Play",
                    text: "Trained on millions of real games. Plays like a human at your level — with realistic mistakes, not random ones."
                )
                techCard(
                    index: 1,
                    icon: "cpu",
                    color: .orange,
                    title: "Stockfish — World's Strongest Engine",
                    text: "The same engine used by grandmasters. Analyzes every position and scores your plan execution."
                )
                techCard(
                    index: 2,
                    icon: "brain.head.profile",
                    color: .purple,
                    title: "On-Device AI Coach",
                    text: "A private AI that runs entirely on your phone. Explains every move in plain English — no internet needed."
                )
            }
            .padding(.horizontal, AppSpacing.xxl)

            Text("All of this runs locally on your device.\nNo cloud. No lag. Just you and the board.")
                .font(.caption)
                .foregroundStyle(AppColor.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxxl)
                .opacity(showTechCards.allSatisfy({ $0 }) ? 1 : 0)

            Spacer()
            nextButton
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 10)
        }
    }

    private func techCard(index: Int, icon: String, color: Color, title: String, text: String) -> some View {
        let visible = index < showTechCards.count && showTechCards[index]
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.primaryText)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(AppColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .scaleEffect(visible ? 1.0 : 0.9)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 20)
    }

    // MARK: - Page 4: Coaching Demo

    private let coachingTiles: [(icon: String, color: Color, text: String)] = [
        ("target", .orange, "The plan: aim your bishop at f7 — Black's weakest square."),
        ("arrow.right", .cyan, "The bishop on f1 has a clear diagonal to c4, pointing right at f7."),
        ("hand.point.right.fill", .green, "Play Bc4 — put the plan into action."),
    ]

    private var coachingDemoPage: some View {
        VStack(spacing: AppSpacing.sm) {
            Spacer()

            VStack(spacing: 6) {
                Text(puzzleSolved ? "That's How It Works" : "How We Teach")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)

                Text(puzzleSolved
                     ? "The right move becomes obvious."
                     : "The coach explains the plan — then you play it")
                    .font(.subheadline)
                    .foregroundStyle(puzzleSolved ? AppColor.success : AppColor.secondaryText)
            }
            .offset(y: showTitle ? 0 : 20)
            .opacity(showTitle ? 1 : 0)

            if let gs = tryItGameState {
                GameBoardView(
                    gameState: gs,
                    perspective: .white,
                    allowInteraction: coachingStep >= coachingTiles.count && !puzzleSolved
                ) { from, to in
                    handleDemoMove(from: from, to: to)
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, AppSpacing.xxl)
                .opacity(boardReady ? 1 : 0)
                .scaleEffect(boardReady ? 1.0 : 0.95)
            }

            // Coaching tiles — stagger in one by one
            VStack(spacing: AppSpacing.xs) {
                ForEach(Array(coachingTiles.prefix(coachingStep).enumerated()), id: \.offset) { _, tile in
                    coachingTileRow(icon: tile.icon, color: tile.color, text: tile.text)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
            .padding(.horizontal, AppSpacing.xxl)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: coachingStep)

            Spacer()

            if puzzleSolved {
                nextButton
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Color.clear.frame(height: 80)
            }
        }
        .onAppear {
            setupCoachingDemo()
        }
    }

    private func coachingTileRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundStyle(AppColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func setupCoachingDemo() {
        let gs = GameState()
        gs.makeMoveUCI("e2e4")
        gs.makeMoveUCI("e7e5")
        gs.makeMoveUCI("g1f3")
        gs.makeMoveUCI("b8c6")
        tryItGameState = gs

        withAnimation(.easeOut(duration: 0.4).delay(0.2)) {
            boardReady = true
        }
        for i in 1...coachingTiles.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 + Double(i) * 0.8) {
                withAnimation {
                    coachingStep = i
                }
            }
        }
    }

    private func handleDemoMove(from: String, to: String) {
        if "\(from)\(to)" == "f1c4" {
            puzzleSolved = true
            showPuzzleConfetti = true
            SoundService.shared.play(.correct)
            SoundService.shared.hapticCorrectMove()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                showButton = true
            }
        } else {
            SoundService.shared.hapticDeviation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                tryItGameState?.undoLastMove()
            }
        }
    }

    // MARK: - Page 5: Go Pro

    private var proPage: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            Image(systemName: "star.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))
                .scaleEffect(showIcon ? 1.0 : 0.3)
                .opacity(showIcon ? 1 : 0)

            VStack(spacing: 8) {
                Text("Free vs Pro")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)

                Text("Start free, upgrade when you're ready")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)
            }
            .offset(y: showTitle ? 0 : 20)
            .opacity(showTitle ? 1 : 0)

            VStack(spacing: 12) {
                proComparisonRow(0, icon: "book.closed.fill",
                                 free: "3 starter openings",
                                 pro: "All openings")
                proComparisonRow(1, icon: "brain.head.profile.fill",
                                 free: "Guided coaching",
                                 pro: "AI coach — explains every move")
                proComparisonRow(2, icon: "puzzlepiece.fill",
                                 free: "5 puzzles / day",
                                 pro: "Unlimited puzzles")
                proComparisonRow(3, icon: "chart.bar.fill",
                                 free: "Basic progress",
                                 pro: "Full scoring, spaced review, drills")
            }
            .padding(.horizontal, AppSpacing.xxl)

            Text("The free version is a real learning tool, not a trial.\nPro just takes it further.")
                .font(.caption)
                .foregroundStyle(AppColor.tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxxl)
                .opacity(itemVisible(4) ? 1 : 0)

            Spacer()
            nextButton
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 10)
        }
    }

    private func proComparisonRow(_ index: Int, icon: String, free: String, pro: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.yellow.opacity(0.8))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(free)
                    .font(.caption)
                    .foregroundStyle(AppColor.tertiaryText)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text(pro)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColor.primaryText)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.yellow.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .opacity(itemVisible(index) ? 1 : 0)
        .offset(y: itemVisible(index) ? 0 : 15)
    }

    // MARK: - Page 6: Pro Showcase

    private var proShowcasePage: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()

            Image(systemName: "wand.and.stars")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))
                .scaleEffect(showIcon ? 1.0 : 0.3)
                .opacity(showIcon ? 1 : 0)

            VStack(spacing: 8) {
                Text("What Pro Unlocks")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)

                Text("Everything you need to break through")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)
            }
            .offset(y: showTitle ? 0 : 20)
            .opacity(showTitle ? 1 : 0)

            VStack(spacing: 12) {
                proFeatureCard(
                    index: 0,
                    icon: "book.closed.fill",
                    color: .cyan,
                    title: "Every Opening",
                    text: "30+ openings with full move trees, plans, and opponent responses — not just 3 starters."
                )
                proFeatureCard(
                    index: 1,
                    icon: "brain.head.profile",
                    color: .purple,
                    title: "AI Coach on Every Move",
                    text: "Your private coach explains the why behind every position — powered by on-device AI."
                )
                proFeatureCard(
                    index: 2,
                    icon: "puzzlepiece.fill",
                    color: .orange,
                    title: "Unlimited Puzzles & Drills",
                    text: "No daily caps. Practice tactics, pattern recognition, and endgames as much as you want."
                )
                proFeatureCard(
                    index: 3,
                    icon: "chart.line.uptrend.xyaxis",
                    color: .green,
                    title: "Full Progress Tracking",
                    text: "Soundness scores, spaced review, mastery tracking — see exactly where you're improving."
                )
            }
            .padding(.horizontal, AppSpacing.xxl)

            Spacer()
            nextButton
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 10)
        }
    }

    private func proFeatureCard(index: Int, icon: String, color: Color, title: String, text: String) -> some View {
        let visible = index < showProFeatures.count && showProFeatures[index]
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.primaryText)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(AppColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .scaleEffect(visible ? 1.0 : 0.92)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 15)
    }

    // MARK: - Page 7: Privacy

    private var privacyPage: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))
                .scaleEffect(showIcon ? 1.0 : 0.3)
                .opacity(showIcon ? 1 : 0)

            Text("Your Privacy")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)
                .offset(y: showTitle ? 0 : 20)
                .opacity(showTitle ? 1 : 0)

            VStack(alignment: .leading, spacing: 14) {
                animatedPrivacyRow(0, icon: "xmark.shield.fill", text: "No data selling. Ever.")
                animatedPrivacyRow(1, icon: "eye.slash.fill", text: "No tracking.")
                animatedPrivacyRow(2, icon: "iphone", text: "AI runs on your device.")
                animatedPrivacyRow(3, icon: "heart.fill", text: "Your progress is yours.")
            }
            .padding(.horizontal, AppSpacing.xxxl)

            Spacer()
            nextButton
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 10)
        }
    }

    // MARK: - Page 8: Skill Level

    private var skillPage: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.layer(.handleVariety))
                .symbolEffect(.pulse, options: .repeating.speed(0.5))
                .scaleEffect(showIcon ? 1.0 : 0.3)
                .opacity(showIcon ? 1 : 0)

            HStack(spacing: 6) {
                Text("Your Level")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)
                HelpButton(topic: .skillLevel)
            }
            .offset(y: showTitle ? 0 : 20)
            .opacity(showTitle ? 1 : 0)

            // Assessment CTA
            Button {
                showELOAssessment = true
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "brain.head.profile")
                        .font(.title3)
                    Text("Assess My Level")
                        .font(.body.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.cyan, in: RoundedRectangle(cornerRadius: AppRadius.lg))
            }
            .padding(.horizontal, AppSpacing.xxxl)
            .opacity(itemVisible(0) ? 1 : 0)
            .offset(y: itemVisible(0) ? 0 : 20)

            // Manual stepper
            VStack(spacing: AppSpacing.sm) {
                Text("Or set manually")
                    .font(.caption)
                    .foregroundStyle(AppColor.tertiaryText)

                Text("\(settings.userELO)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColor.primaryText)
                    .contentTransition(.numericText())

                HStack(spacing: AppSpacing.xxl) {
                    Button {
                        withAnimation { settings.userELO = max(400, settings.userELO - 100) }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(settings.userELO <= 400 ? AppColor.tertiaryText : AppColor.secondaryText)
                    }
                    .disabled(settings.userELO <= 400)

                    Button {
                        withAnimation { settings.userELO = min(2000, settings.userELO + 100) }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(settings.userELO >= 2000 ? AppColor.tertiaryText : AppColor.secondaryText)
                    }
                    .disabled(settings.userELO >= 2000)
                }
                .accessibilityLabel("Your skill level: \(settings.userELO)")

                Text(eloDescription)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)
            }
            .offset(y: itemVisible(1) ? 0 : 20)
            .opacity(itemVisible(1) ? 1 : 0)

            Spacer()

            Button {
                withAnimation { onComplete() }
            } label: {
                Text("Let's Go!")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColor.success, in: RoundedRectangle(cornerRadius: AppRadius.lg))
            }
            .padding(.horizontal, AppSpacing.xxxl)
            .padding(.bottom, 40)
            .opacity(showButton ? 1 : 0)
            .offset(y: showButton ? 0 : 10)
        }
        .sheet(isPresented: $showELOAssessment) {
            ELOAssessmentView { elo in
                settings.userELO = elo
            }
        }
    }

    // MARK: - Animated Components

    private func animatedBullet(_ index: Int, icon: String, color: Color, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.body)
                .foregroundStyle(AppColor.primaryText)
        }
        .offset(x: itemVisible(index) ? 0 : -30)
        .opacity(itemVisible(index) ? 1 : 0)
    }

    private func animatedPrivacyRow(_ index: Int, icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 28)
                .scaleEffect(itemVisible(index) ? 1 : 0)
            Text(text)
                .font(.body.weight(.medium))
                .foregroundStyle(AppColor.primaryText)
        }
        .opacity(itemVisible(index) ? 1 : 0)
        .offset(x: itemVisible(index) ? 0 : -20)
    }

    // MARK: - Shared

    private var nextButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { page += 1 }
        } label: {
            Text("Next")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColor.layer(.executePlan), in: RoundedRectangle(cornerRadius: AppRadius.lg))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go to next page")
        .padding(.horizontal, AppSpacing.xxxl)
        .padding(.bottom, 40)
    }

    private var eloDescription: String {
        switch settings.userELO {
        case ..<600: return "Complete beginner"
        case 600..<800: return "Beginner"
        case 800..<1000: return "Novice"
        case 1000..<1200: return "Intermediate"
        case 1200..<1500: return "Club player"
        case 1500..<1800: return "Advanced"
        default: return "Expert"
        }
    }
}
