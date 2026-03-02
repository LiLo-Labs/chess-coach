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
    var planUnderstanding: Bool = false           // Layer 1 completed (lesson done)
    var planQuizScore: Double?                    // Layer 1 quiz accuracy (0.0-1.0)
    var theoryCompleted: Bool = false             // Layer 3 completed
    var theoryQuizScore: Double?                  // Layer 3 quiz accuracy (0.0-1.0)
    var averagePES: Double = 0                    // Rolling average across all sessions
    var sessionsPlayed: Int = 0
    var lastPlayed: Date?

    // Legacy compatibility
    var lineProgress: [String: LineProgress] = [:]

    // Layer 1 — enhanced
    var planPracticeCompletions: Int = 0          // Main line memory runs
    var planApplySessions: [ExecutionSession] = [] // Guided sessions during L1
    var planMasteryQuizPassed: Bool = false        // Final quiz 3/3

    // Layer 2 — richer tracking
    var executionSessions: [ExecutionSession] = []

    // Layer 3 — enhanced
    var nameTheOpeningPassed: Bool = false
    var spotTheVariationPassed: Bool = false
    var theoryReinforcementSessions: Int = 0

    // Layer 4 — richer tracking
    var responseResults: [ResponseResult] = []
    var scoutReportRead: Bool = false

    // Layer 5 — achievement tracking
    var realConditionSessions: [ExecutionSession] = []
    var peakPES: Double = 0
    var bestConsecutiveWins: Int = 0

    // Sub-milestone states
    var milestoneStates: [String: SubMilestoneState] = [:]

    // Path unlock narrative
    var seenUnlockedPaths: Set<String> = []

    // MARK: - Simple Init

    init(openingID: String) {
        self.openingID = openingID
    }

    // MARK: - Backward Compat: executionScores / responsesHandled / realConditionScores

    /// Layer 2 PES history (computed from executionSessions for backward compat).
    var executionScores: [Double] {
        get { executionSessions.map(\.pes) }
        set {
            // Only used by legacy migration
            executionSessions = newValue.map {
                ExecutionSession(pes: $0, mode: "guided", date: Date())
            }
        }
    }

    /// Layer 4: opponent response IDs successfully faced (computed from responseResults).
    var responsesHandled: Set<String> {
        get {
            Set(responseResults.filter { $0.pes >= 65 }.map(\.responseID))
        }
        set {
            // Only used by legacy migration — create stub results
            for id in newValue where !responseResults.contains(where: { $0.responseID == id }) {
                responseResults.append(ResponseResult(responseID: id, pes: 65, mode: "guided", date: Date()))
            }
        }
    }

    /// Layer 5 PES history (computed from realConditionSessions for backward compat).
    var realConditionScores: [Double] {
        get { realConditionSessions.map(\.pes) }
        set {
            realConditionSessions = newValue.map {
                ExecutionSession(pes: $0, mode: "unguided", date: Date())
            }
        }
    }

    // MARK: - Computed Properties

    /// Average PES from Layer 2 execution sessions.
    var executionAveragePES: Double {
        let scores = executionScores
        guard !scores.isEmpty else { return 0 }
        return scores.suffix(10).reduce(0, +) / Double(min(scores.count, 10))
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

    // MARK: - Recording Methods

    /// Record completing Layer 1 (understanding the plan).
    mutating func completePlanUnderstanding(quizScore: Double? = nil) {
        planUnderstanding = true
        if let score = quizScore {
            planQuizScore = score
        }
        // Mark L1.lesson and L1.quiz milestones
        markMilestone("L1.lesson", progress: 1.0)
        if let score = quizScore, score >= 0.6 {
            markMilestone("L1.quiz", progress: 1.0)
        }
        if currentLayer == .understandPlan {
            // Don't auto-advance yet — need practice + apply milestones
            evaluateLayer1Milestones()
        }
    }

    /// Record a Layer 1 guided session (covers both "Practice with Coaching" and "Apply the Plan").
    mutating func recordPlanApplySession(pes: Double) {
        planApplySessions.append(ExecutionSession(pes: pes, mode: "guided", date: Date()))
        let count = planApplySessions.count

        // L1.practice: play 3 guided sessions (no score requirement)
        let practiceProgress = min(Double(count) / 3.0, 1.0)
        markMilestone("L1.practice", progress: practiceProgress)

        // L1.apply: score PES 40+ in any session
        let hasPES40 = planApplySessions.contains { $0.pes >= 40 }
        let applyProgress = hasPES40 ? 1.0 : min(planApplySessions.map(\.pes).max().map { $0 / 40.0 } ?? 0, 0.9)
        markMilestone("L1.apply", progress: applyProgress)

        sessionsPlayed += 1
        lastPlayed = Date()
        evaluateLayer1Milestones()
    }

    /// Record passing the mastery quiz (Layer 1).
    mutating func recordPlanMasteryQuiz(passed: Bool) {
        planMasteryQuizPassed = passed
        if passed {
            markMilestone("L1.mastery", progress: 1.0)
        }
        evaluateLayer1Milestones()
    }

    private mutating func evaluateLayer1Milestones() {
        // Check if all L1 milestones are complete
        let allComplete = ["L1.lesson", "L1.quiz", "L1.practice", "L1.apply", "L1.mastery"]
            .allSatisfy { milestoneStates[$0]?.isComplete == true }
        if allComplete && currentLayer == .understandPlan {
            currentLayer = .executePlan
        }
    }

    /// Record a Layer 2 session PES score.
    mutating func recordExecutionSession(pes: Double, mode: String = "guided") {
        let session = ExecutionSession(pes: pes, mode: mode, date: Date())
        executionSessions.append(session)
        sessionsPlayed += 1
        lastPlayed = Date()
        updateAveragePES()
        evaluateLayer2Milestones()

        if isExecutionComplete && currentLayer == .executePlan {
            currentLayer = .discoverTheory
        }
    }

    private mutating func evaluateLayer2Milestones() {
        let sessions = executionSessions

        // L2.warmup — 5 guided sessions
        let guidedCount = sessions.filter { $0.mode == "guided" }.count
        markMilestone("L2.warmup", progress: min(Double(guidedCount) / 5.0, 1.0))

        // L2.footing — PES >= 50 in any 3 sessions
        let above50 = sessions.filter { $0.pes >= 50 }.count
        markMilestone("L2.footing", progress: min(Double(above50) / 3.0, 1.0))

        // L2.consistency — PES >= 60 in 3 consecutive sessions
        let consec60 = longestConsecutiveRun(in: sessions, threshold: 60)
        markMilestone("L2.consistency", progress: min(Double(consec60) / 3.0, 1.0))

        // L2.excellence — PES >= 70 in 3 consecutive sessions
        let consec70 = longestConsecutiveRun(in: sessions, threshold: 70)
        markMilestone("L2.excellence", progress: min(Double(consec70) / 3.0, 1.0))

        // L2.prove — PES >= 70 in 3 consecutive unguided sessions
        let unguidedSessions = sessions.filter { $0.mode == "unguided" }
        let unguidedConsec70 = longestConsecutiveRun(in: unguidedSessions, threshold: 70)
        markMilestone("L2.prove", progress: min(Double(unguidedConsec70) / 3.0, 1.0))
    }

    /// Record completing Layer 3 (theory discovery).
    mutating func completeTheoryDiscovery(quizScore: Double? = nil) {
        theoryCompleted = true
        if let score = quizScore {
            theoryQuizScore = score
        }
        markMilestone("L3.story", progress: 1.0)
        evaluateLayer3Milestones()
    }

    /// Record passing the "Name That Opening" exercise.
    mutating func recordNameTheOpening(passed: Bool) {
        if passed { nameTheOpeningPassed = true }
        markMilestone("L3.name", progress: passed ? 1.0 : 0.5)
        evaluateLayer3Milestones()
    }

    /// Record passing the "Spot the Variation" exercise.
    mutating func recordSpotTheVariation(passed: Bool) {
        if passed { spotTheVariationPassed = true }
        markMilestone("L3.spot", progress: passed ? 1.0 : 0.5)
        evaluateLayer3Milestones()
    }

    /// Record a theory reinforcement session.
    mutating func recordTheoryReinforcement(pes: Double) {
        if pes >= 60 { theoryReinforcementSessions += 1 }
        let progress = min(Double(theoryReinforcementSessions) / 2.0, 1.0)
        markMilestone("L3.reinforce", progress: progress)
        sessionsPlayed += 1
        lastPlayed = Date()
        evaluateLayer3Milestones()
    }

    private mutating func evaluateLayer3Milestones() {
        let allComplete = ["L3.story", "L3.name", "L3.spot", "L3.reinforce"]
            .allSatisfy { milestoneStates[$0]?.isComplete == true }
        if allComplete && currentLayer == .discoverTheory {
            currentLayer = .handleVariety
        }
    }

    /// Record reading the scout report (Layer 4).
    mutating func recordScoutReportRead() {
        scoutReportRead = true
        markMilestone("L4.scout", progress: 1.0)
    }

    /// Record handling an opponent response in Layer 4.
    mutating func recordResponseHandled(responseID: String, pes: Double, mode: String = "guided") {
        responseResults.append(ResponseResult(responseID: responseID, pes: pes, mode: mode, date: Date()))
        sessionsPlayed += 1
        lastPlayed = Date()
        updateAveragePES()
        evaluateLayer4Milestones()

        if isVarietyComplete && currentLayer == .handleVariety {
            currentLayer = .realConditions
        }
    }

    private mutating func evaluateLayer4Milestones() {
        // L4.first — 2 different responses with PES >= 50
        let above50IDs = Set(responseResults.filter { $0.pes >= 50 }.map(\.responseID))
        markMilestone("L4.first", progress: min(Double(above50IDs.count) / 2.0, 1.0))

        // L4.adapt — all responses with PES >= 55 (assume we need at least 3 unique)
        let above55IDs = Set(responseResults.filter { $0.pes >= 55 }.map(\.responseID))
        markMilestone("L4.adapt", progress: min(Double(above55IDs.count) / 3.0, 1.0))

        // L4.consistent — PES >= 65 against 3 different responses
        let above65IDs = Set(responseResults.filter { $0.pes >= 65 }.map(\.responseID))
        markMilestone("L4.consistent", progress: min(Double(above65IDs.count) / 3.0, 1.0))

        // L4.master — PES >= 70 against all responses, at least 1 unguided
        let above70IDs = Set(responseResults.filter { $0.pes >= 70 }.map(\.responseID))
        let hasUnguided = responseResults.contains { $0.mode == "unguided" && $0.pes >= 70 }
        let masterProgress = min(Double(above70IDs.count) / 3.0, 1.0) * (hasUnguided ? 1.0 : 0.9)
        markMilestone("L4.master", progress: masterProgress)
    }

    /// Record a Layer 5 (real conditions) session.
    mutating func recordRealConditionsSession(pes: Double, won: Bool = false) {
        let session = ExecutionSession(pes: pes, mode: "unguided", date: Date())
        realConditionSessions.append(session)
        if pes > peakPES { peakPES = pes }
        sessionsPlayed += 1
        lastPlayed = Date()
        updateAveragePES()
        evaluateLayer5Milestones(won: won)
    }

    private mutating func evaluateLayer5Milestones(won: Bool) {
        let sessions = realConditionSessions

        // L5.debut — 5 sessions
        markMilestone("L5.debut", progress: min(Double(sessions.count) / 5.0, 1.0))

        // L5.consistent — PES >= 75 in 3 consecutive
        let consec75 = longestConsecutiveRun(in: sessions, threshold: 75)
        markMilestone("L5.consistent", progress: min(Double(consec75) / 3.0, 1.0))

        // L5.peak — PES >= 85 in any single session
        markMilestone("L5.peak", progress: min(peakPES / 85.0, 1.0))

        // L5.streak — Win 3 consecutive games (simplified: track via bestConsecutiveWins)
        if won {
            bestConsecutiveWins += 1
        } else {
            bestConsecutiveWins = 0
        }
        markMilestone("L5.streak", progress: min(Double(bestConsecutiveWins) / 3.0, 1.0))

        // L5.master — PES >= 80 average across last 10
        if sessions.count >= 10 {
            let last10Avg = sessions.suffix(10).map(\.pes).reduce(0, +) / 10.0
            markMilestone("L5.master", progress: min(last10Avg / 80.0, 1.0))
        } else {
            let avg = sessions.isEmpty ? 0 : sessions.map(\.pes).reduce(0, +) / Double(sessions.count)
            markMilestone("L5.master", progress: min(avg / 80.0, 1.0) * Double(sessions.count) / 10.0)
        }
    }

    // MARK: - Milestone Helpers

    /// Mark a milestone, updating progress and completion status.
    mutating func markMilestone(_ id: String, progress: Double) {
        var state = milestoneStates[id] ?? SubMilestoneState()
        state.progress = max(state.progress, progress) // Never go backward
        if progress >= 1.0 && !state.isComplete {
            state.isComplete = true
            state.completedDate = Date()
        }
        milestoneStates[id] = state
    }

    /// Returns milestones that just completed (comparing before/after states).
    static func newlyCompletedMilestones(before: OpeningMastery, after: OpeningMastery) -> [SubMilestone] {
        let layer = after.currentLayer
        let milestones = layer.milestones(from: after)
        return milestones.filter { ms in
            ms.isComplete && !(before.milestoneStates[ms.id]?.isComplete ?? false)
        }
    }

    // MARK: - Private Helpers

    private func longestConsecutiveRun(in sessions: [ExecutionSession], threshold: Double) -> Int {
        var maxRun = 0
        var currentRun = 0
        for session in sessions {
            if session.pes >= threshold {
                currentRun += 1
                maxRun = max(maxRun, currentRun)
            } else {
                currentRun = 0
            }
        }
        return maxRun
    }

    private mutating func updateAveragePES() {
        let allScores = executionScores + realConditionScores
        guard !allScores.isEmpty else { return }
        averagePES = allScores.suffix(20).reduce(0, +) / Double(min(allScores.count, 20))
    }

    // MARK: - Codable Migration

    enum CodingKeys: String, CodingKey {
        case openingID, currentLayer, planUnderstanding, planQuizScore
        case theoryCompleted, theoryQuizScore, averagePES, sessionsPlayed, lastPlayed
        case lineProgress
        // Layer 1 enhanced
        case planPracticeCompletions, planApplySessions, planMasteryQuizPassed
        // Layer 2
        case executionSessions
        case executionScores // legacy key
        // Layer 3 enhanced
        case nameTheOpeningPassed, spotTheVariationPassed, theoryReinforcementSessions
        // Layer 4
        case responseResults, scoutReportRead
        case responsesHandled // legacy key
        // Layer 5
        case realConditionSessions, peakPES, bestConsecutiveWins
        case realConditionScores // legacy key
        // Milestone states
        case milestoneStates, seenUnlockedPaths
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        openingID = try c.decode(String.self, forKey: .openingID)
        currentLayer = try c.decodeIfPresent(LearningLayer.self, forKey: .currentLayer) ?? .understandPlan
        planUnderstanding = try c.decodeIfPresent(Bool.self, forKey: .planUnderstanding) ?? false
        planQuizScore = try c.decodeIfPresent(Double.self, forKey: .planQuizScore)
        theoryCompleted = try c.decodeIfPresent(Bool.self, forKey: .theoryCompleted) ?? false
        theoryQuizScore = try c.decodeIfPresent(Double.self, forKey: .theoryQuizScore)
        averagePES = try c.decodeIfPresent(Double.self, forKey: .averagePES) ?? 0
        sessionsPlayed = try c.decodeIfPresent(Int.self, forKey: .sessionsPlayed) ?? 0
        lastPlayed = try c.decodeIfPresent(Date.self, forKey: .lastPlayed)
        lineProgress = try c.decodeIfPresent([String: LineProgress].self, forKey: .lineProgress) ?? [:]

        // Layer 1 enhanced
        planPracticeCompletions = try c.decodeIfPresent(Int.self, forKey: .planPracticeCompletions) ?? 0
        planApplySessions = try c.decodeIfPresent([ExecutionSession].self, forKey: .planApplySessions) ?? []
        planMasteryQuizPassed = try c.decodeIfPresent(Bool.self, forKey: .planMasteryQuizPassed) ?? false

        // Layer 2: try new format first, fall back to legacy
        if let sessions = try? c.decodeIfPresent([ExecutionSession].self, forKey: .executionSessions) {
            executionSessions = sessions ?? []
        } else if let scores = try? c.decodeIfPresent([Double].self, forKey: .executionScores) {
            executionSessions = (scores ?? []).map {
                ExecutionSession(pes: $0, mode: "guided", date: Date())
            }
        } else {
            executionSessions = []
        }

        // Layer 3 enhanced
        nameTheOpeningPassed = try c.decodeIfPresent(Bool.self, forKey: .nameTheOpeningPassed) ?? false
        spotTheVariationPassed = try c.decodeIfPresent(Bool.self, forKey: .spotTheVariationPassed) ?? false
        theoryReinforcementSessions = try c.decodeIfPresent(Int.self, forKey: .theoryReinforcementSessions) ?? 0

        // Layer 4: try new format first, fall back to legacy
        if let results = try? c.decodeIfPresent([ResponseResult].self, forKey: .responseResults) {
            responseResults = results
        } else if let handled = try? c.decodeIfPresent(Set<String>.self, forKey: .responsesHandled) {
            responseResults = handled.map {
                ResponseResult(responseID: $0, pes: 65, mode: "guided", date: Date())
            }
        } else {
            responseResults = []
        }
        scoutReportRead = try c.decodeIfPresent(Bool.self, forKey: .scoutReportRead) ?? false

        // Layer 5: try new format first, fall back to legacy
        if let sessions = try? c.decodeIfPresent([ExecutionSession].self, forKey: .realConditionSessions) {
            realConditionSessions = sessions
        } else if let scores = try? c.decodeIfPresent([Double].self, forKey: .realConditionScores) {
            realConditionSessions = scores.map {
                ExecutionSession(pes: $0, mode: "unguided", date: Date())
            }
        } else {
            realConditionSessions = []
        }
        peakPES = try c.decodeIfPresent(Double.self, forKey: .peakPES) ?? 0
        bestConsecutiveWins = try c.decodeIfPresent(Int.self, forKey: .bestConsecutiveWins) ?? 0

        // Milestones
        milestoneStates = try c.decodeIfPresent([String: SubMilestoneState].self, forKey: .milestoneStates) ?? [:]
        seenUnlockedPaths = try c.decodeIfPresent(Set<String>.self, forKey: .seenUnlockedPaths) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(openingID, forKey: .openingID)
        try c.encode(currentLayer, forKey: .currentLayer)
        try c.encode(planUnderstanding, forKey: .planUnderstanding)
        try c.encodeIfPresent(planQuizScore, forKey: .planQuizScore)
        try c.encode(theoryCompleted, forKey: .theoryCompleted)
        try c.encodeIfPresent(theoryQuizScore, forKey: .theoryQuizScore)
        try c.encode(averagePES, forKey: .averagePES)
        try c.encode(sessionsPlayed, forKey: .sessionsPlayed)
        try c.encodeIfPresent(lastPlayed, forKey: .lastPlayed)
        try c.encode(lineProgress, forKey: .lineProgress)
        // Layer 1
        try c.encode(planPracticeCompletions, forKey: .planPracticeCompletions)
        try c.encode(planApplySessions, forKey: .planApplySessions)
        try c.encode(planMasteryQuizPassed, forKey: .planMasteryQuizPassed)
        // Layer 2 — write new format only
        try c.encode(executionSessions, forKey: .executionSessions)
        // Layer 3
        try c.encode(nameTheOpeningPassed, forKey: .nameTheOpeningPassed)
        try c.encode(spotTheVariationPassed, forKey: .spotTheVariationPassed)
        try c.encode(theoryReinforcementSessions, forKey: .theoryReinforcementSessions)
        // Layer 4
        try c.encode(responseResults, forKey: .responseResults)
        try c.encode(scoutReportRead, forKey: .scoutReportRead)
        // Layer 5
        try c.encode(realConditionSessions, forKey: .realConditionSessions)
        try c.encode(peakPES, forKey: .peakPES)
        try c.encode(bestConsecutiveWins, forKey: .bestConsecutiveWins)
        // Milestones
        try c.encode(milestoneStates, forKey: .milestoneStates)
        try c.encode(seenUnlockedPaths, forKey: .seenUnlockedPaths)
    }

    // MARK: - Legacy Migration

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
