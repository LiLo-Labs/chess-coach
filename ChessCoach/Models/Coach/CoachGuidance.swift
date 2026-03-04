import Foundation

/// Composes personality strings with dynamic context to produce natural-sounding guidance.
@MainActor
struct CoachGuidance {
    let personality: CoachPersonality
    let mastery: OpeningMastery
    let openingName: String

    // MARK: - SessionCompleteView

    func sessionCompleteMessage(pes: Double, completedMilestones: [SubMilestone]) -> String {
        if let milestone = completedMilestones.first {
            let reaction = personality.onMilestone.randomElement() ?? "Well done!"
            return "\(reaction) You've completed \"\(milestone.title)\"!"
        }

        let layer = mastery.currentLayer
        if let next = layer.nextMilestone(from: mastery) {
            if next.progress > 0.7 {
                return "\(personality.onEncouragement.randomElement() ?? "") Almost there — \(next.title) is within reach."
            } else if pes >= 70 {
                return personality.onEncouragement.randomElement() ?? "Keep it up!"
            } else if pes >= 50 {
                return "\(personality.onNextStep.randomElement() ?? "") \(next.narrative)"
            } else {
                return personality.onConsolation.randomElement() ?? "Keep practicing."
            }
        }

        return personality.onSessionEnd.randomElement() ?? "Good session!"
    }

    // MARK: - HomeView Hero Card

    var welcomeBackMessage: String {
        let opener = personality.onWelcomeBack.randomElement() ?? "Welcome back!"
        let layer = mastery.currentLayer
        guard let next = layer.nextMilestone(from: mastery) else {
            return "\(opener) Keep pushing your \(openingName) to new heights."
        }

        let context: String
        if next.progress > 0.8 {
            context = "You're 1 session from \"\(next.title).\" Let's go!"
        } else if next.progress > 0.5 {
            context = "Halfway through \"\(next.title).\" Keep the momentum."
        } else {
            context = "\(next.narrative)"
        }

        return "\(opener) \(context)"
    }

    // MARK: - Locked Path Messages

    func lockedPathMessage(lineName: String, parentLineName: String) -> String {
        "Master the \(parentLineName) first. \(personality.onNextStep.randomElement() ?? "Walk before you run.")"
    }

    func unlockedPathMessage(lineName: String) -> String {
        let reaction = personality.onMilestone.randomElement() ?? "New path unlocked!"
        return "The \(lineName) opens before you! \(personality.humanName): \"\(reaction)\""
    }
}
