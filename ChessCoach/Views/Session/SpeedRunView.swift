import SwiftUI
import ChessKit

/// Speed run mode: board + timer, no coaching (improvement 3).
/// Timer starts on first move, stops on last correct move or first mistake.
struct SpeedRunView: View {
    let opening: Opening
    let lineID: String?

    @State private var gameState = GameState()
    @State private var startTime: Date?
    @State private var elapsedTime: TimeInterval = 0
    @State private var isRunning = false
    @State private var isComplete = false
    @State private var failed = false
    @State private var timer: Timer?
    @State private var bestTime: TimeInterval?
    @State private var correctMoveAtFailure: String?
    @Environment(\.dismiss) private var dismiss

    private var activeMoves: [OpeningMove] {
        if let lineID, let line = opening.lines?.first(where: { $0.id == lineID }) {
            return line.moves
        }
        return opening.mainLine
    }

    private var isUserTurn: Bool {
        (opening.color == .white && gameState.isWhiteTurn) ||
        (opening.color == .black && !gameState.isWhiteTurn)
    }

    /// Achievement tier based on elapsed time (only relevant when complete).
    private var achievementTier: AchievementTier? {
        guard isComplete else { return nil }
        if elapsedTime < 10 { return .gold }
        if elapsedTime < 20 { return .silver }
        if elapsedTime < 30 { return .bronze }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(AppColor.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close speed run")

                Spacer()

                Text("Speed Run")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)

                Spacer()

                // Timer
                Text(formattedTime)
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(
                        failed ? AppColor.error
                            : isComplete ? AppColor.success
                            : AppColor.primaryText
                    )
                    .accessibilityLabel("Timer: \(formattedTime)")
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.vertical, AppSpacing.md)

            // Board
            GameBoardView(
                gameState: gameState,
                perspective: opening.color == .white ? .white : .black,
                allowInteraction: isUserTurn && !isComplete && !failed
            ) { from, to in
                handleMove(from: from, to: to)
            }
            .aspectRatio(1, contentMode: .fit)

            Spacer()

            // Result
            if isComplete {
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(AppColor.success)

                    Text(formattedTime)
                        .font(.title.weight(.bold))
                        .foregroundStyle(AppColor.primaryText)

                    // Achievement tier badge
                    if let tier = achievementTier {
                        AchievementBadge(tier: tier, label: "Speed Demon")
                    }

                    if let best = bestTime {
                        Text("Best: \(formatTime(best))")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.secondaryText)
                    }

                    Button("Try Again") { restart() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Restart speed run")
                }
                .padding(AppSpacing.cardPadding)
            } else if failed {
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(AppColor.error)

                    Text("Wrong move!")
                        .font(.headline)
                        .foregroundStyle(AppColor.primaryText)

                    // Show the correct move that should have been played
                    if let correctSAN = correctMoveAtFailure {
                        HStack(spacing: AppSpacing.xxs) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption)
                                .foregroundStyle(AppColor.warning)
                            Text("Correct move: ")
                                .font(.subheadline)
                                .foregroundStyle(AppColor.secondaryText)
                            + Text(correctSAN)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(AppColor.primaryText)
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(AppColor.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.sm))
                    }

                    Button("Try Again") { restart() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Restart speed run")
                }
                .padding(AppSpacing.cardPadding)
            }

            Spacer()
        }
        .background(AppColor.background)
        .preferredColorScheme(.dark)
        .onAppear {
            let lineKey = lineID ?? "\(opening.id)/main"
            bestTime = PersistenceService.shared.loadSpeedRunRecords()[lineKey]
            if opening.color == .black {
                makeOpponentMove()
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private var formattedTime: String {
        formatTime(elapsedTime)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        let tenths = Int(t * 10) % 10
        if minutes > 0 {
            return String(format: "%d:%02d.%d", minutes, seconds, tenths)
        }
        return String(format: "%d.%d", seconds, tenths)
    }

    private func handleMove(from: String, to: String) {
        let ply = gameState.plyCount
        let uci = from + to

        // Start timer on first user move
        if startTime == nil {
            startTime = Date()
            isRunning = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                if let start = startTime {
                    elapsedTime = Date().timeIntervalSince(start)
                }
            }
        }

        // Check if correct
        guard ply < activeMoves.count, activeMoves[ply].uci == uci else {
            // Capture the correct move's SAN before setting failed state
            if ply < activeMoves.count {
                correctMoveAtFailure = activeMoves[ply].san
            }
            failed = true
            isRunning = false
            timer?.invalidate()
            SoundService.shared.play(.wrong)
            SoundService.shared.hapticDeviation()
            return
        }

        SoundService.shared.play(.move)
        SoundService.shared.hapticCorrectMove()

        // Check if line complete
        if gameState.plyCount >= activeMoves.count - 1 {
            isComplete = true
            isRunning = false
            timer?.invalidate()
            SoundService.shared.play(.correct)
            SoundService.shared.hapticLineComplete()
            // Save record
            let lineKey = lineID ?? "\(opening.id)/main"
            PersistenceService.shared.saveSpeedRunRecord(lineID: lineKey, time: elapsedTime)
            bestTime = min(bestTime ?? .infinity, elapsedTime)
            return
        }

        // Make opponent move
        makeOpponentMove()
    }

    private func makeOpponentMove() {
        let ply = gameState.plyCount
        guard ply < activeMoves.count else { return }
        let move = activeMoves[ply]
        _ = gameState.makeMoveUCI(move.uci)
    }

    private func restart() {
        gameState.reset()
        startTime = nil
        elapsedTime = 0
        isRunning = false
        isComplete = false
        failed = false
        correctMoveAtFailure = nil
        timer?.invalidate()
        timer = nil
        if opening.color == .black {
            makeOpponentMove()
        }
    }
}
