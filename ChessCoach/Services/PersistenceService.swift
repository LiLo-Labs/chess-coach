import Foundation

final class PersistenceService: @unchecked Sendable {
    static let shared = PersistenceService()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let progressKey = "chess_coach_progress"
    private let reviewItemsKey = "chess_coach_review_items"
    private let streakKey = "chess_coach_streak"
    private let schemaVersionKey = "chess_coach_schema_version"
    private let mistakeTrackerKey = "chess_coach_mistakes"
    private let speedRunKey = "chess_coach_speed_runs"

    private static let currentSchemaVersion = 2

    init() {
        migrateIfNeeded()
    }

    // MARK: - User Progress

    func loadProgress(forOpening openingID: String) -> OpeningProgress {
        let allProgress = loadAllProgress()
        return allProgress[openingID] ?? OpeningProgress(openingID: openingID)
    }

    func saveProgress(_ progress: OpeningProgress) {
        var allProgress = loadAllProgress()
        allProgress[progress.openingID] = progress
        if let data = try? encoder.encode(allProgress) {
            defaults.set(data, forKey: progressKey)
        }
    }

    func loadAllProgress() -> [String: OpeningProgress] {
        guard let data = defaults.data(forKey: progressKey),
              let progress = try? decoder.decode([String: OpeningProgress].self, from: data) else {
            return [:]
        }
        return progress
    }

    // MARK: - Review Items

    func loadReviewItems() -> [ReviewItem] {
        guard let data = defaults.data(forKey: reviewItemsKey),
              let items = try? decoder.decode([ReviewItem].self, from: data) else {
            return []
        }
        return items
    }

    func saveReviewItems(_ items: [ReviewItem]) {
        if let data = try? encoder.encode(items) {
            defaults.set(data, forKey: reviewItemsKey)
        }
    }

    // MARK: - Streak

    func loadStreak() -> StreakTracker {
        guard let data = defaults.data(forKey: streakKey),
              let streak = try? decoder.decode(StreakTracker.self, from: data) else {
            return StreakTracker()
        }
        return streak
    }

    func saveStreak(_ streak: StreakTracker) {
        if let data = try? encoder.encode(streak) {
            defaults.set(data, forKey: streakKey)
        }
    }

    // MARK: - Mistake Tracker (improvement 2)

    func loadMistakeTracker() -> MistakeTracker {
        guard let data = defaults.data(forKey: mistakeTrackerKey) else {
            return MistakeTracker()
        }
        let tracker: MistakeTracker? = try? decoder.decode(MistakeTracker.self, from: data)
        return tracker ?? MistakeTracker()
    }

    func saveMistakeTracker(_ tracker: MistakeTracker) {
        if let data = try? encoder.encode(tracker) {
            defaults.set(data, forKey: mistakeTrackerKey)
        }
    }

    // MARK: - Speed Run Records (improvement 3)

    func loadSpeedRunRecords() -> [String: TimeInterval] {
        defaults.dictionary(forKey: speedRunKey) as? [String: TimeInterval] ?? [:]
    }

    func saveSpeedRunRecord(lineID: String, time: TimeInterval) {
        var records = loadSpeedRunRecords()
        if let existing = records[lineID], existing <= time { return }
        records[lineID] = time
        defaults.set(records, forKey: speedRunKey)
    }

    // MARK: - Session Auto-Save (improvement 27)

    func saveSessionState(_ state: [String: Any]) {
        defaults.set(state, forKey: "chess_coach_saved_session")
    }

    func loadSessionState() -> [String: Any]? {
        defaults.dictionary(forKey: "chess_coach_saved_session")
    }

    func clearSessionState() {
        defaults.removeObject(forKey: "chess_coach_saved_session")
    }

    // MARK: - Migration

    private func migrateIfNeeded() {
        let currentVersion = defaults.integer(forKey: schemaVersionKey)

        if currentVersion < 2 {
            migrateV1ToV2()
        }

        defaults.set(Self.currentSchemaVersion, forKey: schemaVersionKey)
    }

    /// Migrate from v1 (flat per-opening progress) to v2 (per-line progress).
    /// Existing progress becomes the "main" line entry.
    private func migrateV1ToV2() {
        guard let data = defaults.data(forKey: progressKey) else { return }

        // Try decoding as v1 format (no lineProgress field — will default to empty)
        guard var allProgress = try? decoder.decode([String: OpeningProgress].self, from: data) else {
            return
        }

        for (openingID, progress) in allProgress {
            if progress.lineProgress.isEmpty && progress.gamesPlayed > 0 {
                // Migrate existing aggregate progress to a main line entry
                let mainLineID = "\(openingID)/main"
                let mainLineProgress = LineProgress(
                    lineID: mainLineID,
                    openingID: openingID,
                    currentPhase: progress.currentPhase,
                    gamesPlayed: progress.gamesPlayed,
                    gamesWon: progress.gamesWon,
                    accuracyHistory: progress.accuracyHistory,
                    lastPlayed: progress.lastPlayed,
                    isUnlocked: true
                )
                allProgress[openingID]?.lineProgress[mainLineID] = mainLineProgress
            }
        }

        if let newData = try? encoder.encode(allProgress) {
            defaults.set(newData, forKey: progressKey)
        }
    }
}
