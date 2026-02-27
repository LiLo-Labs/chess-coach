import Foundation

/// The 5-layer learning flow for plan-first opening learning.
enum LearningLayer: Int, Codable, Sendable, CaseIterable, Comparable {
    case understandPlan = 1   // Layer 1: Interactive lesson on the opening's plan
    case executePlan = 2      // Layer 2: Play scored on plan alignment, not exact moves
    case discoverTheory = 3   // Layer 3: Learn classical names and canonical move orders
    case handleVariety = 4    // Layer 4: Face different opponent responses each session
    case realConditions = 5   // Layer 5: Full game, no hints, maintenance layer

    static func < (lhs: LearningLayer, rhs: LearningLayer) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .understandPlan: return "Learn the Plan"
        case .executePlan: return "Practice the Plan"
        case .discoverTheory: return "The Story Behind the Moves"
        case .handleVariety: return "Face Different Opponents"
        case .realConditions: return "Play for Real"
        }
    }

    var shortName: String {
        switch self {
        case .understandPlan: return "Learn"
        case .executePlan: return "Practice"
        case .discoverTheory: return "Story"
        case .handleVariety: return "Opponents"
        case .realConditions: return "Real"
        }
    }

    var layerDescription: String {
        switch self {
        case .understandPlan:
            return "Learn what you're aiming for and the key ideas"
        case .executePlan:
            return "Play it your way — scored on following the plan, not memorizing exact moves"
        case .discoverTheory:
            return "Discover the history and names behind the moves you've been playing"
        case .handleVariety:
            return "Your opponent will surprise you — adapt your plan"
        case .realConditions:
            return "No hints — just you and the board"
        }
    }

    var nextLayer: LearningLayer? {
        LearningLayer(rawValue: rawValue + 1)
    }

    /// Whether this layer is available in the free tier.
    var isFreeLayer: Bool {
        switch self {
        case .understandPlan, .executePlan, .discoverTheory:
            return true
        case .handleVariety, .realConditions:
            return false
        }
    }
}

/// Tracks mastery progress for an opening using the plan-first learning model.
struct OpeningMastery: Codable, Sendable {
    let openingID: String
    var currentLayer: LearningLayer = .understandPlan
    var planUnderstanding: Bool = false           // Layer 1 completed
    var planQuizScore: Double?                    // Layer 1 quiz accuracy (0.0-1.0)
    var executionScores: [Double] = []            // Layer 2 PES history
    var theoryCompleted: Bool = false             // Layer 3 completed
    var theoryQuizScore: Double?                  // Layer 3 quiz accuracy (0.0-1.0)
    var responsesHandled: Set<String> = []        // Layer 4: opponent response IDs successfully faced
    var realConditionScores: [Double] = []        // Layer 5 PES history
    var averagePES: Double = 0                    // Rolling average across all sessions
    var sessionsPlayed: Int = 0
    var lastPlayed: Date?

    // Legacy compatibility: keep lineProgress for transition period
    var lineProgress: [String: LineProgress] = [:]

    /// Average PES from Layer 2 execution sessions.
    var executionAveragePES: Double {
        guard !executionScores.isEmpty else { return 0 }
        return executionScores.suffix(10).reduce(0, +) / Double(min(executionScores.count, 10))
    }

    /// Check if Layer 2 completion criteria are met (average PES >= 70).
    var isExecutionComplete: Bool {
        executionAveragePES >= 70 && executionScores.count >= 3
    }

    /// Number of distinct opponent responses handled with PES >= 65 in Layer 4.
    var varietyResponseCount: Int {
        responsesHandled.count
    }

    /// Check if Layer 4 completion criteria are met (3+ responses with PES >= 65).
    var isVarietyComplete: Bool {
        responsesHandled.count >= 3
    }

    /// Record completing Layer 1 (understanding the plan).
    mutating func completePlanUnderstanding(quizScore: Double? = nil) {
        planUnderstanding = true
        if let score = quizScore {
            planQuizScore = score
        }
        if currentLayer == .understandPlan {
            currentLayer = .executePlan
        }
    }

    /// Record a Layer 2 session PES score.
    mutating func recordExecutionSession(pes: Double) {
        executionScores.append(pes)
        sessionsPlayed += 1
        lastPlayed = Date()
        updateAveragePES()

        if isExecutionComplete && currentLayer == .executePlan {
            currentLayer = .discoverTheory
        }
    }

    /// Record completing Layer 3 (theory discovery).
    mutating func completeTheoryDiscovery(quizScore: Double? = nil) {
        theoryCompleted = true
        if let score = quizScore {
            theoryQuizScore = score
        }
        if currentLayer == .discoverTheory {
            currentLayer = .handleVariety
        }
    }

    /// Record handling an opponent response in Layer 4.
    mutating func recordResponseHandled(responseID: String, pes: Double) {
        if pes >= 65 {
            responsesHandled.insert(responseID)
        }
        sessionsPlayed += 1
        lastPlayed = Date()
        updateAveragePES()

        if isVarietyComplete && currentLayer == .handleVariety {
            currentLayer = .realConditions
        }
    }

    /// Record a Layer 5 (real conditions) session.
    mutating func recordRealConditionsSession(pes: Double) {
        realConditionScores.append(pes)
        sessionsPlayed += 1
        lastPlayed = Date()
        updateAveragePES()
    }

    private mutating func updateAveragePES() {
        let allScores = executionScores + realConditionScores
        guard !allScores.isEmpty else { return }
        averagePES = allScores.suffix(20).reduce(0, +) / Double(min(allScores.count, 20))
    }

    /// Migrate from legacy LineProgress + LearningPhase to the new layer model.
    static func fromLegacy(openingID: String, progress: OpeningProgress) -> OpeningMastery {
        var mastery = OpeningMastery(openingID: openingID)
        mastery.lineProgress = progress.lineProgress
        mastery.sessionsPlayed = progress.gamesPlayed
        mastery.lastPlayed = progress.lastPlayed

        // Map old phases to new layers
        switch progress.currentPhase {
        case .learningMainLine:
            mastery.currentLayer = .understandPlan
        case .naturalDeviations:
            mastery.currentLayer = .executePlan
            mastery.planUnderstanding = true
        case .widerVariations:
            mastery.currentLayer = .handleVariety
            mastery.planUnderstanding = true
            mastery.theoryCompleted = true
        case .freePlay:
            mastery.currentLayer = .realConditions
            mastery.planUnderstanding = true
            mastery.theoryCompleted = true
        }

        // Convert accuracy history to PES scores (approximate)
        mastery.executionScores = progress.accuracyHistory.map { $0 * 100 }
        mastery.averagePES = progress.accuracy * 100

        return mastery
    }
}
