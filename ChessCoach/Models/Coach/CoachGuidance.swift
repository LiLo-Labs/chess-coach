import Foundation

/// Composes personality strings with dynamic context to produce natural-sounding guidance.
@MainActor
struct CoachGuidance {
    let personality: CoachPersonality
    let mastery: OpeningMastery
    let openingName: String

    // MARK: - OpeningDetailView — Current Layer Guidance

    var layerGuidanceMessage: String {
        let layer = mastery.currentLayer
        guard let next = layer.nextMilestone(from: mastery) else {
            return "\(personality.onEncouragement.randomElement() ?? "") All checkpoints complete — keep playing to sharpen your edge."
        }

        let opener = personality.onNextStep.randomElement() ?? ""
        let body: String

        switch next.id {
        // Layer 1
        case "L1.lesson":
            body = "Start with the lesson to understand the \(openingName) plan."
        case "L1.quiz":
            body = "Test your understanding — pass the quiz to move on."
        case "L1.practice":
            let left = max(0, 3 - mastery.planApplySessions.count)
            body = "Play \(left) guided session\(left == 1 ? "" : "s") with coaching — I'll explain every move as you go."
        case "L1.apply":
            let best = mastery.planApplySessions.map(\.pes).max() ?? 0
            body = best > 0 ? "Your best so far is \(Int(best)). Get to 40 and you've got it." : "Time to show you understand the plan — aim for PES 40+."
        case "L1.mastery":
            body = "Final quiz: get all 3 correct to prove you've got it."

        // Layer 2
        case "L2.warmup":
            let left = max(0, 5 - mastery.executionSessions.filter { $0.mode == "guided" }.count)
            body = "Play \(left) more guided session\(left == 1 ? "" : "s") — just get comfortable."
        case "L2.footing":
            let count = mastery.executionSessions.filter { $0.pes >= 50 }.count
            body = "Score PES 50+ in \(max(0, 3 - count)) more session\(3 - count == 1 ? "" : "s")."
        case "L2.consistency":
            body = "String together 3 sessions at PES 60+. Show me consistency."
        case "L2.excellence":
            body = "Now push for 3 consecutive sessions at PES 70+."
        case "L2.prove":
            body = "Prove it without hints — 3 consecutive unguided sessions at PES 70+."

        // Layer 3
        case "L3.story":
            body = "Discover the story behind the moves you've been playing."
        case "L3.name":
            body = "Can you name the variations? Identify 6 out of 8 positions."
        case "L3.spot":
            body = "Spot which variation is which from partial move sequences."
        case "L3.reinforce":
            let left = max(0, 2 - mastery.theoryReinforcementSessions)
            body = "Reinforce your knowledge — \(left) more session\(left == 1 ? "" : "s") at PES 60+."

        // Layer 4
        case "L4.scout":
            body = "Read the scouting report before your first encounter."
        case "L4.first":
            body = "Face 2 different opponent responses and score PES 50+."
        case "L4.adapt":
            body = "Handle all opponent responses with PES 55+."
        case "L4.consistent":
            body = "Score PES 65+ against 3 different responses."
        case "L4.master":
            body = "Master every response at PES 70+, including at least one unguided."

        // Layer 5
        case "L5.debut":
            let left = max(0, 5 - mastery.realConditionSessions.count)
            body = "Play \(left) more session\(left == 1 ? "" : "s") with no hints."
        case "L5.consistent":
            body = "Score PES 75+ in 3 consecutive sessions."
        case "L5.peak":
            body = "Chase PES 85+ in a single session. Your current peak: \(Int(mastery.peakPES))."
        case "L5.streak":
            body = "Win 3 games in a row."
        case "L5.master":
            body = "Average PES 80+ across your last 10 sessions."

        default:
            body = next.narrative
        }

        return "\(opener) \(body)".trimmingCharacters(in: .whitespaces)
    }

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
