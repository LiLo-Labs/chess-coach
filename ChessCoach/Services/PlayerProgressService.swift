import Foundation

/// Tracks player progress: ELO estimation, per-opening accuracy, improvement trends.
/// Separate tracking for Human-Like vs Engine games.
@Observable @MainActor
final class PlayerProgressService {
    static let shared = PlayerProgressService()

    private(set) var humanELO: ELOEstimate
    private(set) var engineELO: ELOEstimate
    private(set) var openingAccuracy: [String: OpeningAccuracy] // keyed by opening ID
    private(set) var weeklyHistory: [WeeklySnapshot]

    private let defaults = UserDefaults.standard

    private init() {
        humanELO = Self.loadELO(key: "player_elo_human")
        engineELO = Self.loadELO(key: "player_elo_engine")
        openingAccuracy = Self.loadOpeningAccuracy()
        weeklyHistory = Self.loadWeeklyHistory()
    }

    // MARK: - ELO Update (simplified Elo system)

    /// Record a game result and update ELO estimate.
    func recordGame(
        opponentELO: Int,
        outcome: TrainerGameResult.Outcome,
        engineMode: TrainerEngineMode,
        openingID: String?,
        moveCount: Int
    ) {
        let elo = engineMode == .humanLike ? humanELO : engineELO

        // Calculate expected score
        let expected = 1.0 / (1.0 + pow(10.0, Double(opponentELO - elo.rating) / 400.0))

        // Actual score
        let actual: Double
        switch outcome {
        case .win: actual = 1.0
        case .loss, .resigned: actual = 0.0
        case .draw: actual = 0.5
        }

        // K-factor: higher for fewer games (more volatile early)
        let k: Double
        if elo.gamesPlayed < 10 { k = 40 }
        else if elo.gamesPlayed < 30 { k = 32 }
        else { k = 24 }

        let newRating = Int(Double(elo.rating) + k * (actual - expected))
        let clampedRating = max(100, min(3000, newRating))

        var updated = elo
        updated.rating = clampedRating
        updated.gamesPlayed += 1
        updated.peak = max(updated.peak, clampedRating)
        updated.lastGameDate = Date()

        // Track recent results for confidence
        updated.recentResults.append(actual)
        if updated.recentResults.count > 20 {
            updated.recentResults.removeFirst()
        }

        if engineMode == .humanLike {
            humanELO = updated
            Self.saveELO(updated, key: "player_elo_human")
        } else {
            engineELO = updated
            Self.saveELO(updated, key: "player_elo_engine")
        }

        // Update opening accuracy
        if let openingID {
            updateOpeningAccuracy(openingID: openingID, outcome: outcome, moveCount: moveCount)
        }

        // Update weekly snapshot
        updateWeeklySnapshot()
    }

    // MARK: - Opening Accuracy

    private func updateOpeningAccuracy(openingID: String, outcome: TrainerGameResult.Outcome, moveCount: Int) {
        var accuracy = openingAccuracy[openingID] ?? OpeningAccuracy(openingID: openingID)

        accuracy.totalGames += 1
        switch outcome {
        case .win: accuracy.wins += 1
        case .loss, .resigned: accuracy.losses += 1
        case .draw: accuracy.draws += 1
        }
        accuracy.lastPlayed = Date()

        openingAccuracy[openingID] = accuracy
        Self.saveOpeningAccuracy(openingAccuracy)
    }

    // MARK: - Weekly Snapshots

    private func updateWeeklySnapshot() {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let weekKey = Self.weekKey(weekStart)

        if var current = weeklyHistory.last, current.weekKey == weekKey {
            current.humanELO = humanELO.rating
            current.engineELO = engineELO.rating
            current.gamesPlayed += 1
            weeklyHistory[weeklyHistory.count - 1] = current
        } else {
            let snapshot = WeeklySnapshot(
                weekKey: weekKey,
                date: weekStart,
                humanELO: humanELO.rating,
                engineELO: engineELO.rating,
                gamesPlayed: 1
            )
            weeklyHistory.append(snapshot)
            // Keep last 52 weeks
            if weeklyHistory.count > 52 {
                weeklyHistory.removeFirst()
            }
        }

        Self.saveWeeklyHistory(weeklyHistory)
    }

    /// The player's "combined" estimated rating (average of both modes, weighted by games played).
    var estimatedRating: Int {
        let hGames = max(humanELO.gamesPlayed, 1)
        let eGames = max(engineELO.gamesPlayed, 1)
        let total = hGames + eGames
        return (humanELO.rating * hGames + engineELO.rating * eGames) / total
    }

    /// How confident we are in the estimate (0-1).
    var confidence: Double {
        let totalGames = humanELO.gamesPlayed + engineELO.gamesPlayed
        return min(1.0, Double(totalGames) / 30.0)
    }

    /// ELO trend direction.
    var trend: ELOTrend {
        guard weeklyHistory.count >= 2 else { return .stable }
        let recent = weeklyHistory.suffix(2)
        let prev = recent.first!
        let curr = recent.last!
        let avgPrev = (prev.humanELO + prev.engineELO) / 2
        let avgCurr = (curr.humanELO + curr.engineELO) / 2
        let diff = avgCurr - avgPrev
        if diff > 20 { return .improving }
        if diff < -20 { return .declining }
        return .stable
    }

    // MARK: - Persistence

    private static func loadELO(key: String) -> ELOEstimate {
        guard let data = UserDefaults.standard.data(forKey: key),
              let elo = try? JSONDecoder().decode(ELOEstimate.self, from: data) else {
            return ELOEstimate()
        }
        return elo
    }

    private static func saveELO(_ elo: ELOEstimate, key: String) {
        if let data = try? JSONEncoder().encode(elo) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadOpeningAccuracy() -> [String: OpeningAccuracy] {
        guard let data = UserDefaults.standard.data(forKey: "player_opening_accuracy"),
              let acc = try? JSONDecoder().decode([String: OpeningAccuracy].self, from: data) else {
            return [:]
        }
        return acc
    }

    private static func saveOpeningAccuracy(_ acc: [String: OpeningAccuracy]) {
        if let data = try? JSONEncoder().encode(acc) {
            UserDefaults.standard.set(data, forKey: "player_opening_accuracy")
        }
    }

    private static func loadWeeklyHistory() -> [WeeklySnapshot] {
        guard let data = UserDefaults.standard.data(forKey: "player_weekly_history"),
              let history = try? JSONDecoder().decode([WeeklySnapshot].self, from: data) else {
            return []
        }
        return history
    }

    private static func saveWeeklyHistory(_ history: [WeeklySnapshot]) {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "player_weekly_history")
        }
    }

    private static func weekKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-ww"
        return formatter.string(from: date)
    }
}

// MARK: - Models

struct ELOEstimate: Codable, Sendable {
    var rating: Int = 800           // Starting estimate
    var gamesPlayed: Int = 0
    var peak: Int = 800
    var lastGameDate: Date?
    var recentResults: [Double] = [] // Last 20 results (1.0=win, 0.5=draw, 0.0=loss)

    var recentWinRate: Double {
        guard !recentResults.isEmpty else { return 0 }
        return recentResults.reduce(0, +) / Double(recentResults.count)
    }
}

struct OpeningAccuracy: Codable, Sendable {
    let openingID: String
    var totalGames: Int = 0
    var wins: Int = 0
    var losses: Int = 0
    var draws: Int = 0
    var lastPlayed: Date?

    var winRate: Double {
        totalGames > 0 ? Double(wins) / Double(totalGames) : 0
    }
}

struct WeeklySnapshot: Codable, Sendable {
    let weekKey: String
    let date: Date
    var humanELO: Int
    var engineELO: Int
    var gamesPlayed: Int
}

enum ELOTrend: Sendable {
    case improving
    case declining
    case stable

    var icon: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .declining: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }

    var label: String {
        switch self {
        case .improving: return "Improving"
        case .declining: return "Declining"
        case .stable: return "Stable"
        }
    }
}
