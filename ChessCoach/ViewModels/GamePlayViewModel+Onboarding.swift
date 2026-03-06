import Foundation
import SwiftUI

/// Onboarding-mode logic: user plays ~8 moves, Maia responds, HolisticDetector runs silently.
extension GamePlayViewModel {

    private static let onboardingMessages = [
        "Good start! Let\u{2019}s see how you play.",
        "Developing your pieces \u{2014} nice.",
        "Building your position...",
        "You\u{2019}re finding a rhythm.",
        "Solid play so far.",
        "Interesting choice.",
        "Almost there \u{2014} one more move.",
        "Let\u{2019}s see what you\u{2019}ve got."
    ]

    func onboardingUserMoved(from: String, to: String) {
        onboardingMoveCount += 1
        SoundService.shared.play(.move)
        SoundService.shared.hapticPiecePlaced()

        // Run opening detection silently
        updateOpeningDetection()
        updateOnboardingDetection()

        // Add generic coaching entry
        addOnboardingFeedEntry()

        // Check if we should end
        if onboardingMoveCount >= 8 || gameState.isMate || gameState.legalMoves.isEmpty {
            completeOnboarding()
            return
        }

        // Opponent responds
        makeOnboardingOpponentMove()
    }

    private func makeOnboardingOpponentMove() {
        isThinking = true
        onboardingOpponentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let fen = self.gameState.fen
            let legalMoves = self.gameState.legalMoves.map { $0.description }

            guard !legalMoves.isEmpty else {
                self.isThinking = false
                return
            }

            var moveUCI: String?

            // Try Maia first for human-like play
            if let maia = self.maiaService {
                let history = self.gameState.moveHistory.map {
                    "\($0.from)\($0.to)\($0.promotion?.rawValue ?? "")"
                }
                moveUCI = try? await maia.sampleMove(
                    fen: fen,
                    legalMoves: legalMoves,
                    eloSelf: self.opponentELO,
                    eloOppo: self.userELO,
                    temperature: 1.0,
                    recentMoves: history
                )
            }

            guard !Task.isCancelled else { return }

            // Fallback to Stockfish
            if moveUCI == nil {
                moveUCI = await self.stockfish.bestMove(fen: fen, depth: AppConfig.engine.opponentMoveDepth)
            }

            guard !Task.isCancelled, let move = moveUCI else {
                self.isThinking = false
                return
            }

            self.gameState.makeMoveUCI(move)
            SoundService.shared.play(.move)
            self.isThinking = false

            // Only update detection after opponent move — skip redundant branch point computation
            self.updateOnboardingDetection()

            if self.gameState.isMate || self.gameState.legalMoves.isEmpty {
                self.completeOnboarding()
            }
        }
    }

    /// Update onboardingDetectedOpening from latest holisticDetection.
    private func updateOnboardingDetection() {
        if let best = holisticDetection.whiteFramework.primary {
            onboardingDetectedOpening = best.opening
            onboardingMatchDepth = best.matchDepth
        }
    }

    private func addOnboardingFeedEntry() {
        let index = min(onboardingMoveCount - 1, Self.onboardingMessages.count - 1)
        let coaching = Self.onboardingMessages[index]
        let moveNumber = (gameState.plyCount + 1) / 2

        insertFeedEntry(CoachingEntry(
            ply: gameState.plyCount - 1,
            moveNumber: moveNumber,
            moveSAN: "",
            isPlayerMove: true,
            coaching: coaching,
            category: .goodMove
        ))
    }

    /// Finalize onboarding: apply fallback if needed, trigger revelation overlay.
    private func completeOnboarding() {
        onboardingOpponentTask?.cancel()
        onboardingOpponentTask = nil

        if onboardingDetectedOpening == nil || onboardingMatchDepth < 3 {
            onboardingDetectedOpening = curatedFallbackOpening()
            onboardingMatchDepth = 0
        }
        onboardingComplete = true
    }

    /// Pick a curated opening based on the user's first move.
    private func curatedFallbackOpening() -> Opening? {
        let db = OpeningDatabase.shared
        let firstMove = gameState.moveHistory.first.map { "\($0.from)\($0.to)" }
        let whiteOpenings = db.openings(forColor: .white)
        switch firstMove {
        case "e2e4":
            return whiteOpenings.first(where: { $0.name.contains("Italian") }) ?? whiteOpenings.first
        case "d2d4":
            return whiteOpenings.first(where: { $0.name.contains("Queen") }) ?? whiteOpenings.first
        case "c2c4":
            return whiteOpenings.first(where: { $0.name.contains("English") }) ?? whiteOpenings.first
        default:
            return whiteOpenings.first
        }
    }
}
