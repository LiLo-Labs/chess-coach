import Foundation

/// A visible checkpoint within a learning layer.
struct SubMilestone: Codable, Sendable, Identifiable {
    let id: String           // e.g. "L2.warmup"
    let title: String        // "Warm Up"
    let narrative: String    // "Play 5 sessions — just get comfortable"
    var isComplete: Bool = false
    var progress: Double = 0 // 0.0-1.0
}

/// Persisted state for a sub-milestone within OpeningMastery.
struct SubMilestoneState: Codable, Sendable {
    var isComplete: Bool = false
    var progress: Double = 0
    var completedDate: Date?
}

/// A recorded execution session (Layers 2 and 5).
struct ExecutionSession: Codable, Sendable {
    let pes: Double
    let mode: String  // "guided" or "unguided"
    let date: Date
}

/// A recorded response handling result (Layer 4).
struct ResponseResult: Codable, Sendable {
    let responseID: String
    let pes: Double
    let mode: String  // "guided" or "unguided"
    let date: Date
}

// MARK: - Milestone Definitions

extension LearningLayer {

    /// The sub-milestones for this layer, populated with live state from mastery.
    func milestones(from mastery: OpeningMastery) -> [SubMilestone] {
        let defs = milestoneDefinitions
        return defs.map { def in
            let state = mastery.milestoneStates[def.id] ?? SubMilestoneState()
            return SubMilestone(
                id: def.id,
                title: def.title,
                narrative: def.narrative,
                isComplete: state.isComplete,
                progress: state.progress
            )
        }
    }

    /// Static milestone definitions per layer.
    var milestoneDefinitions: [(id: String, title: String, narrative: String)] {
        switch self {
        case .understandPlan:
            return [
                ("L1.lesson", "Read the Plan", "Complete the opening lesson"),
                ("L1.quiz", "Concepts Quiz", "Pass 3 quizzes with at least 2/3 correct"),
                ("L1.practice", "Practice with Coaching", "Play 3 guided sessions — the coach will walk you through it"),
                ("L1.apply", "Apply the Plan", "Score PES 40+ in a guided session — show you understand the plan"),
                ("L1.mastery", "Mastery Check", "Ace the final quiz — 3/3 correct"),
            ]
        case .executePlan:
            return [
                ("L2.warmup", "Warm Up", "Play 5 guided sessions — just get comfortable"),
                ("L2.footing", "Find Your Footing", "Score PES 50+ in any 3 sessions"),
                ("L2.consistency", "Build Consistency", "Score PES 60+ in 3 consecutive sessions"),
                ("L2.excellence", "Push for Excellence", "Score PES 70+ in 3 consecutive sessions"),
                ("L2.prove", "Prove It", "Score PES 70+ in 3 consecutive unguided sessions"),
            ]
        case .discoverTheory:
            return [
                ("L3.story", "The Story", "Complete the theory lesson"),
                ("L3.name", "Name That Opening", "Identify 6 of 8 positions by their variation name"),
                ("L3.spot", "Spot the Variation", "Identify 4 of 6 partial move sequences"),
                ("L3.reinforce", "Reinforce", "Play 2 sessions scoring PES 60+ after the lesson"),
            ]
        case .handleVariety:
            return [
                ("L4.scout", "Scout Report", "Read the scouting cards for all opponent responses"),
                ("L4.first", "First Encounter", "Handle 2 different responses with PES 50+"),
                ("L4.adapt", "Adapt & Overcome", "Handle all responses with PES 55+"),
                ("L4.consistent", "Consistent Adaptation", "Score PES 65+ against 3 different responses"),
                ("L4.master", "Master of Variety", "Score PES 70+ against all responses, at least 1 unguided"),
            ]
        case .realConditions:
            return [
                ("L5.debut", "Debut", "Play 5 sessions with no hints"),
                ("L5.consistent", "Consistent Performer", "Score PES 75+ in 3 consecutive sessions"),
                ("L5.peak", "Peak Performance", "Score PES 85+ in any single session"),
                ("L5.streak", "Win Streak", "Win 3 consecutive games"),
                ("L5.master", "Opening Master", "Average PES 80+ across your last 10 sessions"),
            ]
        }
    }

    /// The next incomplete milestone for this layer.
    func nextMilestone(from mastery: OpeningMastery) -> SubMilestone? {
        milestones(from: mastery).first { !$0.isComplete }
    }

    /// Count of completed milestones for this layer.
    func completedMilestoneCount(from mastery: OpeningMastery) -> Int {
        milestones(from: mastery).filter(\.isComplete).count
    }
}
