import Foundation

/// Familiarity tier for UI display.
enum FamiliarityTier: String, Codable, Sendable {
    case learning    // <30%
    case practicing  // 30-70%
    case familiar    // >=70%

    var displayName: String {
        switch self {
        case .learning: return "Learning"
        case .practicing: return "Practicing"
        case .familiar: return "Familiar"
        }
    }

    static func from(progress: Double) -> FamiliarityTier {
        if progress >= 0.7 { return .familiar }
        if progress >= 0.3 { return .practicing }
        return .learning
    }
}

/// Suggested next action for the user.
enum LearningAction: Sendable {
    case review          // Has due positions
    case drillWeak       // Has weak positions
    case learnMore       // Not all positions seen
    case play            // Familiar enough to play freely
}

/// Computed aggregate familiarity for an opening from its [PositionMastery].
/// Never stored — always computed fresh.
struct OpeningFamiliarity: Sendable {
    let openingID: String
    let positions: [PositionMastery]

    /// 0.0–1.0 overall familiarity progress.
    var progress: Double {
        guard !positions.isEmpty else { return 0 }
        let masteredCount = positions.filter(\.isMastered).count
        return Double(masteredCount) / Double(positions.count)
    }

    /// Integer percentage for display.
    var percentage: Int {
        Int((progress * 100).rounded())
    }

    var tier: FamiliarityTier {
        FamiliarityTier.from(progress: progress)
    }

    /// Positions due for review.
    var dueForReview: [PositionMastery] {
        positions.filter(\.isDue)
    }

    /// Positions with accuracy below 80% and at least one attempt.
    var weakPositions: [PositionMastery] {
        positions.filter { $0.totalAttempts > 0 && $0.accuracy < 0.8 }
    }

    /// Suggested next action.
    var suggestion: LearningAction {
        var hasDue = false
        var hasWeak = false
        for p in positions {
            if p.isDue { hasDue = true }
            if p.totalAttempts > 0 && p.accuracy < 0.8 { hasWeak = true }
            if hasDue && hasWeak { break }
        }
        if hasDue { return .review }
        if hasWeak { return .drillWeak }
        if progress < 0.7 { return .learnMore }
        return .play
    }

    /// Empty familiarity for openings with no position data.
    static func empty(openingID: String) -> OpeningFamiliarity {
        OpeningFamiliarity(openingID: openingID, positions: [])
    }
}

/// Milestone crossed when familiarity passes a threshold (30%, 70%, 100%).
struct FamiliarityMilestone: Sendable {
    let previousProgress: Double
    let newProgress: Double
    let crossedThreshold: Double  // 0.3, 0.7, or 1.0

    var thresholdPercentage: Int {
        Int(crossedThreshold * 100)
    }

    var tierReached: FamiliarityTier {
        FamiliarityTier.from(progress: crossedThreshold)
    }

    /// Detect milestone crossings between two progress values.
    static func detect(from oldProgress: Double, to newProgress: Double) -> FamiliarityMilestone? {
        let thresholds: [Double] = [0.3, 0.7, 1.0]
        for threshold in thresholds {
            if oldProgress < threshold && newProgress >= threshold {
                return FamiliarityMilestone(
                    previousProgress: oldProgress,
                    newProgress: newProgress,
                    crossedThreshold: threshold
                )
            }
        }
        return nil
    }
}
