import SwiftUI
import ChessKit

/// First-run onboarding — welcome coaching demo, ELO picker, play.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppServices.self) private var appServices
    @Environment(SubscriptionService.self) private var subscriptionService
    @State private var page = 0

    var onComplete: () -> Void = {}

    private let totalPages = 3

    // Per-element stagger states
    @State private var showIcon = false
    @State private var showTitle = false
    @State private var showItems: [Bool] = Array(repeating: false, count: 6)
    @State private var showButton = false

    // Page 0 — coaching demo state
    @State private var tryItGameState: GameState? = nil
    @State private var puzzleSolved = false
    @State private var showPuzzleConfetti = false
    @State private var coachingStep = 0
    @State private var boardReady = false

    // Page 1 — assessment
    @State private var showELOAssessment = false

    // Page 2 — onboarding game
    @State private var showOnboardingGame = false

    var body: some View {
        ZStack {
            AppColor.background
                .ignoresSafeArea()

            TabView(selection: $page) {
                welcomePage.tag(0)
                skillPage.tag(1)
                letsPlayPage.tag(2)
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
        .fullScreenCover(isPresented: $showOnboardingGame) {
            GamePlayView(
                mode: .onboarding(playerELO: settings.userELO),
                isPro: false,
                stockfish: appServices.stockfish
            )
            .environment(settings)
            .environment(appServices)
            .environment(subscriptionService)
        }
        .onChange(of: showOnboardingGame) { _, showing in
            if !showing && (settings.hasPickedFreeOpening || settings.hasSeenOnboarding) {
                onComplete()
            }
        }
    }

    // MARK: - Animations

    private func triggerEntryAnimations() {
        showIcon = false
        showTitle = false
        showItems = Array(repeating: false, count: 6)
        showButton = false

        // Reset coaching demo state when leaving page 0
        if page != 0 {
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
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85).delay(1.0)) {
            showButton = true
        }
    }

    private func itemVisible(_ index: Int) -> Bool {
        index < showItems.count && showItems[index]
    }

    // MARK: - Page 0: Welcome (Coaching Demo)

    private let coachingTiles: [(icon: String, color: Color, text: String)] = [
        ("target", .orange, "The plan: aim your bishop at f7 — Black's weakest square."),
        ("arrow.right", .cyan, "The bishop on f1 has a clear diagonal to c4, pointing right at f7."),
        ("hand.point.right.fill", .green, "Play Bc4 — put the plan into action."),
    ]

    private var welcomePage: some View {
        VStack(spacing: AppSpacing.sm) {
            Spacer()

            VStack(spacing: 6) {
                Text(puzzleSolved ? "That's How It Works" : "ChessCoach")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)

                Text(puzzleSolved
                     ? "The right move becomes obvious."
                     : "Your personal chess coach — learn by playing")
                    .font(.subheadline)
                    .foregroundStyle(puzzleSolved ? AppColor.success : AppColor.secondaryText)
                    .multilineTextAlignment(.center)
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

    // MARK: - Page 1: Skill Level

    private var skillPage: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "person.fill.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.familiarity(.practicing))
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

            nextButton
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 10)
        }
        .sheet(isPresented: $showELOAssessment) {
            ELOAssessmentView { elo in
                settings.userELO = elo
            }
        }
    }

    // MARK: - Page 2: Let's Play

    private var letsPlayPage: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 56))
                .foregroundStyle(.cyan)
                .scaleEffect(showIcon ? 1.0 : 0.3)
                .opacity(showIcon ? 1 : 0)

            VStack(spacing: 8) {
                Text("Let's Play!")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)
                Text("Play a short game and we'll show you\nsomething cool about your moves.")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .offset(y: showTitle ? 0 : 20)
            .opacity(showTitle ? 1 : 0)

            Spacer()

            Button {
                showOnboardingGame = true
            } label: {
                Text("Start Game")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColor.success, in: RoundedRectangle(cornerRadius: AppRadius.lg))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.xxxl)
            .padding(.bottom, 40)
            .opacity(showButton ? 1 : 0)
            .offset(y: showButton ? 0 : 10)
        }
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
                .background(AppColor.familiarity(.learning), in: RoundedRectangle(cornerRadius: AppRadius.lg))
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
