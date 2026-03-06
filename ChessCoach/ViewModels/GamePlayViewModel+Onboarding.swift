import Foundation
import SwiftUI

/// Onboarding-mode logic: user plays ~8 moves, Maia responds, HolisticDetector runs silently.
extension GamePlayViewModel {

    func onboardingUserMoved(from: String, to: String) {
        onboardingMoveCount += 1
        SoundService.shared.play(.move)
        SoundService.shared.hapticPiecePlaced()

        // Run opening detection silently
        updateOpeningDetection()

        // Store best white opening match
        if let best = holisticDetection.whiteFramework.primary {
            onboardingDetectedOpening = best.opening
        }

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
        Task { @MainActor [weak self] in
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
                    eloOppo: self.opponentELO,
                    temperature: 1.0,
                    recentMoves: history
                )
            }

            // Fallback to Stockfish
            if moveUCI == nil {
                moveUCI = await self.stockfish.bestMove(fen: fen, depth: 8)
            }

            guard let move = moveUCI else {
                self.isThinking = false
                return
            }

            self.gameState.makeMoveUCI(move)
            SoundService.shared.play(.move)
            self.isThinking = false

            self.updateOpeningDetection()
            if let best = self.holisticDetection.whiteFramework.primary {
                self.onboardingDetectedOpening = best.opening
            }

            if self.gameState.isMate || self.gameState.legalMoves.isEmpty {
                self.completeOnboarding()
            }
        }
    }

    private func addOnboardingFeedEntry() {
        // Use generic, encouraging feedback without opening names
        let messages = [
            "Good start! Let's see how you play.",
            "Developing your pieces \u{2014} nice.",
            "Building your position...",
            "You're finding a rhythm.",
            "Solid play so far.",
            "Interesting choice.",
            "Almost there \u{2014} one more move.",
            "Let's see what you've got."
        ]
        let index = min(onboardingMoveCount - 1, messages.count - 1)
        let coaching = messages[index]
        let moveNumber = (gameState.plyCount + 1) / 2

        let entry = CoachingEntry(
            ply: gameState.plyCount - 1,
            moveNumber: moveNumber,
            moveSAN: "",
            isPlayerMove: true,
            coaching: coaching,
            category: .goodMove
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            feedEntries.insert(entry, at: 0)
        }
    }

    private func completeOnboarding() {
        if onboardingDetectedOpening == nil || (holisticDetection.whiteFramework.primary?.matchDepth ?? 0) < 3 {
            onboardingDetectedOpening = curatedFallbackOpening()
        }
        onboardingComplete = true
    }

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
