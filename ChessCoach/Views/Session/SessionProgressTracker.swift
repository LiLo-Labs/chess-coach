import Foundation

struct SessionProgressInput {
    let opening: Opening
    let activeLineID: String?
    let activeMoves: [OpeningMove]
    let stats: SessionStats
    let sessionMode: SessionMode
    let sessionStartDate: Date
    let gameState: GameState
    let spacedRepScheduler: SpacedRepScheduler
    let currentLayer: LearningLayer
}

struct SessionProgressOutput {
    let sessionResult: SessionResult
    let updatedLayer: LearningLayer
}

struct SessionProgressTracker {

    @MainActor static func saveProgress(input: SessionProgressInput) -> SessionProgressOutput {
        let opening = input.opening
        let stats = input.stats
        let activeLineID = input.activeLineID

        var progress = PersistenceService.shared.loadProgress(forOpening: opening.id)
        let completed = input.gameState.plyCount >= input.activeMoves.count
        let accuracy = stats.accuracy

        let previousBest: Double
        if let lineID = activeLineID {
            previousBest = progress.progress(forLine: lineID).bestAccuracy
        } else {
            previousBest = progress.bestAccuracy
        }
        let isPersonalBest = accuracy > previousBest && progress.gamesPlayed > 0

        var phasePromotion: SessionResult.PhasePromotion?
        var linePhasePromotion: SessionResult.PhasePromotion?

        if let lineID = activeLineID {
            let (aggOld, lineOld) = progress.recordLineGame(lineID: lineID, accuracy: accuracy, won: completed)
            if let old = aggOld {
                phasePromotion = SessionResult.PhasePromotion(from: old, to: progress.currentPhase)
            }
            if let old = lineOld {
                linePhasePromotion = SessionResult.PhasePromotion(from: old, to: progress.progress(forLine: lineID).currentPhase)
            }

            if completed {
                switch input.sessionMode {
                case .guided:
                    progress.lineProgress[lineID]?.guidedCompletions += 1
                case .unguided:
                    progress.lineProgress[lineID]?.unguidedCompletions += 1
                    let currentBest = progress.lineProgress[lineID]?.unguidedBestAccuracy ?? 0
                    progress.lineProgress[lineID]?.unguidedBestAccuracy = max(currentBest, accuracy)
                case .practice:
                    break
                }
            }
        } else {
            let old = progress.recordGame(accuracy: accuracy, won: completed)
            if let old {
                phasePromotion = SessionResult.PhasePromotion(from: old, to: progress.currentPhase)
            }
        }

        PersistenceService.shared.saveProgress(progress)

        var mastery = PersistenceService.shared.loadMastery(forOpening: opening.id)
        let masteryBefore = mastery
        let sessionPES = stats.averagePES

        switch mastery.currentLayer {
        case .understandPlan:
            break
        case .executePlan:
            let modeStr = input.sessionMode == .guided ? "guided" : "unguided"
            mastery.recordExecutionSession(pes: sessionPES, mode: modeStr)
        case .discoverTheory:
            break
        case .handleVariety:
            if let responses = opening.opponentResponses?.responses {
                let moveHistory = input.gameState.moveHistory.map { $0.from + $0.to }
                let modeStr = input.sessionMode == .guided ? "guided" : "unguided"
                for response in responses {
                    if moveHistory.contains(response.move.uci) {
                        mastery.recordResponseHandled(responseID: response.id, pes: sessionPES, mode: modeStr)
                    }
                }
            }
        case .realConditions:
            mastery.recordRealConditionsSession(pes: sessionPES)
        }

        PersistenceService.shared.saveMastery(mastery)
        let updatedLayer = mastery.currentLayer

        var newlyUnlockedLines: [String] = []
        if let lines = opening.lines {
            for line in lines {
                if let parentID = line.parentLineID,
                   progress.isLineUnlocked(line.id, parentLineID: parentID) {
                    let lp = progress.progress(forLine: line.id)
                    if lp.gamesPlayed == 0 {
                        newlyUnlockedLines.append(line.name)
                    }
                }
            }
        }

        let dueReviewCount = input.spacedRepScheduler.dueItems().count

        let currentComposite: Double
        let currentPhase: LearningPhase
        if let lineID = activeLineID {
            let lp = progress.progress(forLine: lineID)
            currentComposite = lp.compositeScore
            currentPhase = lp.currentPhase
        } else {
            currentComposite = progress.compositeScore
            currentPhase = progress.currentPhase
        }

        let nextThreshold = currentPhase.promotionThreshold
        let minGames = currentPhase.minimumGames
        let gamesPlayed = activeLineID.map { progress.progress(forLine: $0).gamesPlayed }
            ?? progress.gamesPlayed
        let gamesUntilMinimum: Int? = minGames.map { max(0, $0 - gamesPlayed) }

        var streak = PersistenceService.shared.loadStreak()
        streak.recordPractice()
        PersistenceService.shared.saveStreak(streak)

        let timeSpent = Date().timeIntervalSince(input.sessionStartDate)
        let movesPerMinute: Double? = timeSpent > 0
            ? Double(stats.totalUserMoves) / (timeSpent / 60.0)
            : nil

        let layerPromotion: SessionResult.LayerPromotion?
        if updatedLayer != input.currentLayer {
            layerPromotion = SessionResult.LayerPromotion(from: input.currentLayer, to: updatedLayer)
        } else {
            layerPromotion = nil
        }

        let completedMilestones = OpeningMastery.newlyCompletedMilestones(before: masteryBefore, after: mastery)
        let nextMilestone = mastery.currentLayer.nextMilestone(from: mastery)
        let coach = CoachPersonality.forOpening(opening)
        let guidance = CoachGuidance(personality: coach, mastery: mastery, openingName: opening.name)
        let coachMessage = guidance.sessionCompleteMessage(pes: sessionPES, completedMilestones: completedMilestones)

        let result = SessionResult(
            accuracy: accuracy,
            isPersonalBest: isPersonalBest,
            phasePromotion: phasePromotion,
            linePhasePromotion: linePhasePromotion,
            newlyUnlockedLines: newlyUnlockedLines,
            dueReviewCount: dueReviewCount,
            compositeScore: currentComposite,
            nextPhaseThreshold: nextThreshold,
            gamesUntilMinimum: gamesUntilMinimum,
            timeSpent: timeSpent,
            movesPerMinute: movesPerMinute,
            averagePES: stats.moveScores.isEmpty ? nil : stats.averagePES,
            pesCategory: stats.moveScores.isEmpty ? nil : stats.pesCategory,
            moveScores: stats.moveScores.isEmpty ? nil : stats.moveScores,
            layerPromotion: layerPromotion,
            completedMilestones: completedMilestones,
            nextMilestone: nextMilestone,
            coachSessionMessage: coachMessage
        )

        return SessionProgressOutput(sessionResult: result, updatedLayer: updatedLayer)
    }
}
