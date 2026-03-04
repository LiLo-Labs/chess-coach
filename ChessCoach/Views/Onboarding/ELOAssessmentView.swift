import SwiftUI
import ChessKit

/// 10-puzzle adaptive skill assessment that estimates a user's ELO rating
/// using curated Lichess puzzles (CC0) with Elo-based difficulty selection.
/// Entry points: OnboardingView page 5, SettingsView, ProgressDetailView.
struct ELOAssessmentView: View {
    var onComplete: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    // MARK: - Phase State Machine

    private enum Phase: Equatable {
        case intro
        case solving
        case showingSolution(isCorrect: Bool)
        case feedback(isCorrect: Bool)
        case result(estimatedELO: Int)
    }

    @State private var phase: Phase = .intro
    @State private var estimatedELO = 800
    @State private var currentPuzzle: AssessmentPuzzle?
    @State private var usedIDs: Set<String> = []
    @State private var correctCount = 0
    @State private var puzzlesSolved = 0
    @State private var dotResults: [Bool] = [] // per-puzzle correct/wrong for progress dots
    @State private var gameState = GameState()
    @State private var feedbackGameState = GameState()
    @State private var puzzlePerspective: PieceColor = .white
    @State private var solutionArrowFrom: String?
    @State private var solutionArrowTo: String?
    @State private var showConfetti = false
    @State private var animatedELO = 0
    @State private var assessmentService: AssessmentService?

    private let maxPuzzles = 10

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.background
                    .ignoresSafeArea()

                switch phase {
                case .intro:
                    introView
                case .solving:
                    solvingView
                case .showingSolution(let isCorrect):
                    solutionDisplayView(isCorrect: isCorrect)
                case .feedback(let isCorrect):
                    feedbackView(isCorrect: isCorrect)
                case .result(let elo):
                    resultView(elo: elo)
                }

                if showConfetti {
                    ConfettiView()
                        .ignoresSafeArea()
                }
            }
            .preferredColorScheme(.dark)
            .navigationTitle("Skill Assessment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
        }
    }

    // MARK: - Intro

    private var introView: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 64))
                .foregroundStyle(.cyan)
                .symbolEffect(.pulse, options: .repeating.speed(0.5))

            VStack(spacing: AppSpacing.sm) {
                Text("Quick Skill Check")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)

                Text("10 puzzles, ~3 minutes")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)

                Text("Find the best move in each position.\nPuzzles adapt to your level as you go.")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.tertiaryText)
                    .multilineTextAlignment(.center)
                    .padding(.top, AppSpacing.xs)
            }

            Spacer()

            VStack(spacing: AppSpacing.md) {
                Button {
                    startAssessment()
                } label: {
                    Text("Start Assessment")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.cyan, in: RoundedRectangle(cornerRadius: AppRadius.lg))
                }

                Button {
                    dismiss()
                } label: {
                    Text("Skip \u{2014} set manually")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
            .padding(.horizontal, AppSpacing.xxxl)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Solving

    private var solvingView: some View {
        VStack(spacing: AppSpacing.md) {
            progressDots
                .padding(.top, AppSpacing.md)

            if let puzzle = currentPuzzle {
                Text("Puzzle \(puzzlesSolved + 1) of \(maxPuzzles)")
                    .font(.caption)
                    .foregroundStyle(AppColor.secondaryText)

                if let theme = puzzle.themes.first {
                    Text(Self.themeDisplayNames[theme] ?? theme.capitalized)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xxxs)
                        .background(.cyan.opacity(0.6), in: Capsule())
                }

                Text(gameState.isWhiteTurn ? "White to move" : "Black to move")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColor.primaryText)

                GameBoardView(
                    gameState: gameState,
                    perspective: puzzlePerspective,
                    allowInteraction: true
                ) { from, to in
                    handleMove(from: from, to: to)
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(.horizontal, AppSpacing.lg)
            }

            Spacer()
        }
    }

    // MARK: - Solution Display

    private func solutionDisplayView(isCorrect: Bool) -> some View {
        VStack(spacing: AppSpacing.md) {
            progressDots
                .padding(.top, AppSpacing.md)

            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(isCorrect ? AppColor.success : AppColor.error)

            GeometryReader { geo in
                ZStack {
                    GameBoardView(
                        gameState: feedbackGameState,
                        perspective: puzzlePerspective,
                        allowInteraction: false
                    ) { _, _ in }
                    .aspectRatio(1, contentMode: .fit)

                    MoveArrowOverlay(
                        arrowFrom: solutionArrowFrom,
                        arrowTo: solutionArrowTo,
                        boardSize: min(geo.size.width, geo.size.height),
                        perspective: puzzlePerspective == .white
                    )
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, AppSpacing.lg)

            if !isCorrect, let san = currentPuzzle?.solutionSAN {
                Text("The move was **\(san)**")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)
            }

            Spacer()
        }
        .task {
            try? await Task.sleep(for: .seconds(AppConfig.animation.solutionDisplayDelay))
            guard !Task.isCancelled else { return }
            withAnimation { phase = .feedback(isCorrect: isCorrect) }
        }
    }

    // MARK: - Feedback

    private func feedbackView(isCorrect: Bool) -> some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()

            GameBoardView(
                gameState: feedbackGameState,
                perspective: puzzlePerspective,
                allowInteraction: false
            ) { _, _ in }
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, AppSpacing.lg)

            MoveFeedbackView(
                isCorrect: isCorrect,
                message: currentPuzzle?.explanation,
                solutionText: {
                    if !isCorrect, let san = currentPuzzle?.solutionSAN {
                        return "The move was \(san)"
                    }
                    return nil
                }(),
                actionLabel: puzzlesSolved >= maxPuzzles ? "See Results" : "Next",
                onAction: { advanceToNextPuzzle() }
            )

            Spacer()
                .frame(height: 40)
        }
    }

    // MARK: - Result

    private func resultView(elo: Int) -> some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            VStack(spacing: AppSpacing.sm) {
                Text("\(animatedELO)")
                    .font(.system(size: 64, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(AppColor.primaryText)
                    .contentTransition(.numericText())

                Text(eloDescription(for: elo))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(AppColor.secondaryText)

                Text("\(correctCount)/\(maxPuzzles) correct")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.tertiaryText)
            }

            Spacer()

            Button {
                onComplete(elo)
                dismiss()
            } label: {
                Text("Continue")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColor.success, in: RoundedRectangle(cornerRadius: AppRadius.lg))
            }
            .padding(.horizontal, AppSpacing.xxxl)
            .padding(.bottom, 40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.3)) {
                animatedELO = elo
            }
            if correctCount > 0 {
                showConfetti = true
            }
        }
    }

    // MARK: - Components

    private var progressDots: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(0..<maxPuzzles, id: \.self) { i in
                Circle()
                    .fill(dotColor(for: i))
                    .frame(width: 10, height: 10)
            }
        }
    }

    // MARK: - Logic

    private func startAssessment() {
        let service = AssessmentService()
        guard service.hasPuzzles else { return }
        assessmentService = service

        estimatedELO = 800
        usedIDs = []
        correctCount = 0
        puzzlesSolved = 0
        dotResults = []

        guard let puzzle = service.selectPuzzle(estimatedELO: estimatedELO, usedIDs: usedIDs) else { return }
        loadPuzzle(puzzle)
        withAnimation { phase = .solving }
    }

    private func loadPuzzle(_ puzzle: AssessmentPuzzle) {
        currentPuzzle = puzzle
        usedIDs.insert(puzzle.id)
        let gs = GameState(fen: puzzle.fen)
        gameState = gs
        puzzlePerspective = gs.isWhiteTurn ? .white : .black
    }

    private func handleMove(from: String, to: String) {
        guard let puzzle = currentPuzzle else { return }

        // Compare the first 4 characters (from+to) — handles promotion edge cases
        let moveUCI = "\(from)\(to)"
        let solutionBase = String(puzzle.solutionUCI.prefix(4))
        let isCorrect = moveUCI == solutionBase

        // Always build a fresh GameState showing the correct move for feedback.
        // GameState is a class, so we can't just copy gameState by reference.
        let correctState = GameState(fen: puzzle.fen)
        correctState.makeMoveUCI(puzzle.solutionUCI)
        feedbackGameState = correctState

        // Set up solution arrow from the correct move's UCI
        let solutionUCI = puzzle.solutionUCI
        if solutionUCI.count >= 4 {
            solutionArrowFrom = String(solutionUCI.prefix(2))
            solutionArrowTo = String(solutionUCI.dropFirst(2).prefix(2))
        }

        if isCorrect {
            correctCount += 1
            SoundService.shared.play(.correct)
            SoundService.shared.hapticCorrectMove()
        } else {
            SoundService.shared.play(.wrong)
            SoundService.shared.hapticDeviation()
            gameState.undoLastMove()
        }

        estimatedELO = AssessmentService.updateEstimate(
            current: estimatedELO,
            puzzleRating: puzzle.rating,
            correct: isCorrect
        )
        puzzlesSolved += 1
        dotResults.append(isCorrect)

        // Show the solution on the board briefly before advancing to feedback
        withAnimation { phase = .showingSolution(isCorrect: isCorrect) }
    }

    private func advanceToNextPuzzle() {
        if puzzlesSolved >= maxPuzzles {
            withAnimation { phase = .result(estimatedELO: estimatedELO) }
        } else if let service = assessmentService,
                  let puzzle = service.selectPuzzle(estimatedELO: estimatedELO, usedIDs: usedIDs) {
            loadPuzzle(puzzle)
            withAnimation { phase = .solving }
        } else {
            // Ran out of puzzles — show results with what we have
            withAnimation { phase = .result(estimatedELO: estimatedELO) }
        }
    }

    private func dotColor(for index: Int) -> Color {
        if index < dotResults.count {
            return dotResults[index] ? AppColor.success : AppColor.error
        } else if index == puzzlesSolved {
            return .cyan
        } else {
            return AppColor.tertiaryText.opacity(0.3)
        }
    }

    private func eloDescription(for elo: Int) -> String {
        switch elo {
        case ..<600: return "Complete Beginner"
        case 600..<800: return "Beginner"
        case 800..<1000: return "Novice"
        case 1000..<1200: return "Intermediate"
        case 1200..<1500: return "Club Player"
        case 1500..<1800: return "Advanced"
        default: return "Expert"
        }
    }

    // MARK: - Theme Display

    private static let themeDisplayNames: [String: String] = [
        "mateIn1": "Mate in 1", "mateIn2": "Mate in 2",
        "fork": "Fork", "pin": "Pin", "skewer": "Skewer",
        "sacrifice": "Sacrifice", "discoveredAttack": "Discovered Attack",
        "castling": "Castling", "kingSafety": "King Safety",
        "center": "Center Control", "development": "Development",
        "capture": "Capture", "recapture": "Recapture",
        "defense": "Defense", "attack": "Attack", "retreat": "Retreat",
        "opening": "Opening", "pawnBreak": "Pawn Break",
        "strategy": "Strategy", "outpost": "Outpost",
        "centralization": "Centralization", "prophylaxis": "Prophylaxis",
        "counterplay": "Counterplay", "counterattack": "Counterattack",
        "exchange": "Exchange", "regrouping": "Regrouping",
        "preparation": "Preparation", "tension": "Tension",
        "bishopPair": "Bishop Pair", "check": "Check",
        "scholarsMate": "Scholar's Mate", "foolsMate": "Fool's Mate",
        "morphy": "Morphy Defense", "middlegame": "Middlegame",
        "space": "Space", "tactic": "Tactics", "tactics": "Tactics",
    ]
}
