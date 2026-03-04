import Foundation

/// Composes personality strings with dynamic context to produce natural-sounding guidance.
@MainActor
struct CoachGuidance {
    let personality: CoachPersonality
    let familiarity: OpeningFamiliarity
    let openingName: String

    // MARK: - SessionCompleteView

    func sessionCompleteMessage(milestone: FamiliarityMilestone?) -> String {
        if let milestone {
            let reaction = personality.onMilestone.randomElement() ?? "Well done!"
            return "\(reaction) You've reached \(milestone.thresholdPercentage)% familiarity — \(milestone.tierReached.displayName)!"
        }

        let pct = familiarity.percentage
        if pct >= 70 {
            return personality.onEncouragement.randomElement() ?? "Keep it up — you're doing great!"
        } else if pct >= 30 {
            return "\(personality.onNextStep.randomElement() ?? "") Keep practicing to build familiarity."
        } else {
            return personality.onConsolation.randomElement() ?? "Keep practicing — every session helps."
        }
    }

    // MARK: - HomeView Hero Card

    var welcomeBackMessage: String {
        let opener = personality.onWelcomeBack.randomElement() ?? "Welcome back!"
        let pct = familiarity.percentage

        let context: String
        if pct >= 70 {
            context = "You're familiar with the \(openingName). Keep sharpening your skills."
        } else if pct >= 30 {
            context = "\(pct)% familiar — keep building your repertoire."
        } else if pct > 0 {
            context = "Still learning the \(openingName). Let's practice!"
        } else {
            context = "Ready to start learning the \(openingName)?"
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
