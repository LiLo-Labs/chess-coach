import SwiftUI
import ChessKit

/// Puzzle solving mode — users find the best move in positions drawn from
/// opening book data, personal mistakes, and engine-evaluated positions.
struct PuzzleModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(AppServices.self) private var appServices
    @Environment(SubscriptionService.self) private var subscriptionService

    @State private var puzzleService: PuzzleService?
    @State private var puzzles: [Puzzle] = []
    @State private var currentIndex = 0
    @State private var sessionResult = PuzzleSessionResult()
    @State private var phase: PuzzlePhase = .loading
    @State private var gameState: GameState?
    @State private var feedbackGameState: GameState?
    @State private var feedbackMessage: String?
    @State private var feedbackIsCorrect = false
    @State private var showHint = false
    @State private var puzzlesSolvedToday: Int = 0
    @State private var puzzlePerspective: PieceColor = .white

    private let dailyFreeLimit = 5

    enum PuzzlePhase {
        case loading
        case solving
        case feedback
        case complete
        case error
    }

    private var currentPuzzle: Puzzle? {
        guard currentIndex < puzzles.count else { return nil }
        return puzzles[currentIndex]
    }


    var body: some View {
        ZStack {
            AppColor.background.ignoresSafeArea()

            switch phase {
            case .loading:
                loadingView
            case .solving:
                if let gs = gameState, let puzzle = currentPuzzle {
                    solvingView(gameState: gs, puzzle: puzzle)
                }
            case .feedback:
                if let gs = feedbackGameState, let puzzle = currentPuzzle {
                    feedbackView(gameState: gs, puzzle: puzzle)
                }
            case .complete:
                completeView
            case .error:
                errorView
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Puzzles")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPuzzles()
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: AppSpacing.lg) {
            ProgressView()
                .controlSize(.large)
                .tint(AppColor.gold)
            Text("Preparing puzzles...")
                .font(.subheadline)
                .foregroundStyle(AppColor.secondaryText)
        }
    }

    // MARK: - Solving

    private func solvingView(gameState: GameState, puzzle: Puzzle) -> some View {
        VStack(spacing: 0) {
            // Progress bar
            HStack(spacing: AppSpacing.xs) {
                Text("\(currentIndex + 1)/\(puzzles.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppColor.secondaryText)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColor.cardBackground)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColor.info)
                            .frame(width: geo.size.width * CGFloat(currentIndex) / CGFloat(max(puzzles.count, 1)), height: 4)
                    }
                }
                .frame(height: 4)

                HStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(sessionResult.streak > 0 ? .orange : AppColor.tertiaryText)
                    Text("\(sessionResult.streak)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(sessionResult.streak > 0 ? .orange : AppColor.tertiaryText)
                }
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.vertical, AppSpacing.sm)

            // Theme badge
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: puzzle.theme.icon)
                    .font(.caption2)
                Text(puzzle.theme.rawValue)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(AppColor.info)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(AppColor.info.opacity(0.12), in: Capsule())
            .padding(.bottom, AppSpacing.sm)

            // Instruction
            Text(gameState.isWhiteTurn ? "White to move" : "Black to move")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.primaryText)
                .padding(.bottom, AppSpacing.xs)

            // Board
            GameBoardView(
                gameState: gameState,
                perspective: puzzlePerspective,
                allowInteraction: true,
                onMove: { from, to in
                    handleMove(from: from, to: to, puzzle: puzzle)
                }
            )
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, AppSpacing.sm)

            Spacer()

            // Hint button
            VStack(spacing: AppSpacing.sm) {
                if showHint {
                    Text("Look for \(OpeningMove.friendlyName(from: puzzle.solutionSAN))")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.gold)
                        .transition(.opacity)
                } else {
                    Button {
                        withAnimation { showHint = true }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption)
                            Text("Show Hint")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(AppColor.gold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppColor.gold.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, AppSpacing.lg)
        }
    }

    // MARK: - Feedback

    private func feedbackView(gameState: GameState, puzzle: Puzzle) -> some View {
        VStack(spacing: 0) {
            // Board (non-interactive)
            GameBoardView(
                gameState: gameState,
                perspective: puzzlePerspective,
                allowInteraction: false
            )
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.top, AppSpacing.md)

            Spacer()

            MoveFeedbackView(
                isCorrect: feedbackIsCorrect,
                message: feedbackMessage,
                solutionText: feedbackIsCorrect ? nil : "The best move was \(OpeningMove.friendlyName(from: puzzle.solutionSAN)) (\(puzzle.solutionSAN))",
                actionLabel: currentIndex + 1 < puzzles.count ? "Next Puzzle" : "See Results",
                onAction: { advanceToNext() }
            )
            .padding(.bottom, AppSpacing.xxxl)
        }
    }

    // MARK: - Complete

    private var completeView: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            SessionSummaryCard(stats: [
                .init(label: "Solved", value: "\(sessionResult.solved)/\(sessionResult.total)"),
                .init(label: "Accuracy", value: "\(Int(sessionResult.accuracy * 100))%"),
                .init(label: "Best Streak", value: "\(sessionResult.bestStreak)"),
            ])
            .padding(.horizontal, AppSpacing.xxl)

            VStack(spacing: AppSpacing.sm) {
                Button {
                    restartSession()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Play Again")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.info, in: RoundedRectangle(cornerRadius: AppRadius.lg))
                }
                .buttonStyle(ScaleButtonStyle())

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColor.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppSpacing.xxl)

            Spacer()
        }
    }

    // MARK: - No Puzzles

    @Environment(\.dismiss) private var puzzleDismiss

    private var errorView: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()

            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 48))
                .foregroundStyle(AppColor.secondaryText)

            Text("No Puzzles Yet")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppColor.primaryText)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Puzzles are built from your repertoire. To get started:")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)

                Label("Pick an opening and play through Layer 1", systemImage: "1.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.primaryText)
                Label("Practice a few sessions to build your history", systemImage: "2.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.primaryText)
                Label("Come back here for targeted puzzles", systemImage: "3.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.primaryText)
            }
            .padding(AppSpacing.cardPadding)
            .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.md))
            .padding(.horizontal, AppSpacing.xxl)

            HStack(spacing: AppSpacing.md) {
                Button("Try Again") {
                    phase = .loading
                    Task { await loadPuzzles() }
                }
                .buttonStyle(.borderedProminent)

                Button("Go Back") {
                    puzzleDismiss()
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
    }

    // MARK: - Logic

    private func loadPuzzles() async {
        guard !Task.isCancelled else { return }

        let service = PuzzleService(stockfish: appServices.stockfish)
        puzzleService = service

        // Fast path: instant, no engine — we know immediately if there's content
        let fastPuzzles = service.generateFastPuzzles(count: 10, userELO: settings.userELO)

        if fastPuzzles.isEmpty {
            // Nothing to work with — show guidance immediately, no spinning
            phase = .error
            return
        }

        // Start solving right away with fast puzzles
        puzzles = fastPuzzles
        let gs = GameState(fen: fastPuzzles[0].fen)
        gameState = gs
        puzzlePerspective = gs.isWhiteTurn ? .white : .black
        phase = .solving
        showHint = false

        // Top up with engine puzzles in the background (appended for later in the session)
        guard !Task.isCancelled else { return }
        let remaining = 10 - fastPuzzles.count
        if remaining > 0 {
            let enginePuzzles = await service.generateEnginePuzzles(count: remaining, userELO: settings.userELO)
            if !enginePuzzles.isEmpty && !Task.isCancelled {
                puzzles.append(contentsOf: enginePuzzles)
            }
        }
    }

    private func handleMove(from: String, to: String, puzzle: Puzzle) {
        // Check if the move matches the solution
        let moveUCI = from + to
        let isCorrect = moveUCI == puzzle.solutionUCI ||
                         moveUCI == String(puzzle.solutionUCI.prefix(4)) // Handle promotion

        // Build a fresh board showing the correct move for feedback
        let correctState = GameState(fen: puzzle.fen)
        correctState.makeMoveUCI(puzzle.solutionUCI)
        feedbackGameState = correctState

        if isCorrect {
            SoundService.shared.play(.correct)
            SoundService.shared.hapticCorrectMove()
            sessionResult.recordSolve()
            feedbackIsCorrect = true
            feedbackMessage = puzzle.explanation ?? "Great job finding the best move!"
        } else {
            SoundService.shared.play(.wrong)
            SoundService.shared.hapticDeviation()
            sessionResult.recordFail()
            feedbackIsCorrect = false
            feedbackMessage = puzzle.explanation
            gameState?.undoLastMove()
        }

        withAnimation {
            phase = .feedback
        }
    }

    private func restartSession() {
        currentIndex = 0
        sessionResult = PuzzleSessionResult()
        showHint = false
        phase = .loading
        Task { await loadPuzzles() }
    }

    private func advanceToNext() {
        currentIndex += 1
        showHint = false

        if currentIndex < puzzles.count {
            let puzzle = puzzles[currentIndex]
            let gs = GameState(fen: puzzle.fen)
            gameState = gs
            puzzlePerspective = gs.isWhiteTurn ? .white : .black
            withAnimation {
                phase = .solving
            }
        } else {
            withAnimation {
                phase = .complete
            }
        }
    }
}
