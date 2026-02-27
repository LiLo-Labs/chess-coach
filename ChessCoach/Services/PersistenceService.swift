import Foundation

final class PersistenceService: @unchecked Sendable {
    static let shared = PersistenceService()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Serial queue that serialises every read-modify-write operation,
    /// eliminating data races when multiple callers access the service
    /// concurrently (C-5 fix).
    private let queue = DispatchQueue(label: "com.chesscoach.persistence", qos: .userInitiated)

    private let progressKey = "chess_coach_progress"
    private let reviewItemsKey = "chess_coach_review_items"
    private let streakKey = "chess_coach_streak"
    private let schemaVersionKey = "chess_coach_schema_version"
    private let mistakeTrackerKey = "chess_coach_mistakes"
    private let speedRunKey = "chess_coach_speed_runs"
    private let masteryKey = "chess_coach_mastery"

    private static let currentSchemaVersion = 3

    init() {
        queue.sync { migrateIfNeeded() }
    }

    // MARK: - User Progress

    func loadProgress(forOpening openingID: String) -> OpeningProgress {
        queue.sync { _loadProgress(forOpening: openingID) }
    }

    func saveProgress(_ progress: OpeningProgress) {
        queue.sync { _saveProgress(progress) }
    }

    func loadAllProgress() -> [String: OpeningProgress] {
        queue.sync { _loadAllProgress() }
    }

    // MARK: - Review Items

    func loadReviewItems() -> [ReviewItem] {
        queue.sync {
            guard let data = defaults.data(forKey: reviewItemsKey),
                  let items = try? decoder.decode([ReviewItem].self, from: data) else {
                return []
            }
            return items
        }
    }

    func saveReviewItems(_ items: [ReviewItem]) {
        queue.sync {
            if let data = try? encoder.encode(items) {
                defaults.set(data, forKey: reviewItemsKey)
            }
        }
    }

    // MARK: - Streak

    func loadStreak() -> StreakTracker {
        queue.sync {
            guard let data = defaults.data(forKey: streakKey),
                  let streak = try? decoder.decode(StreakTracker.self, from: data) else {
                return StreakTracker()
            }
            return streak
        }
    }

    func saveStreak(_ streak: StreakTracker) {
        queue.sync {
            if let data = try? encoder.encode(streak) {
                defaults.set(data, forKey: streakKey)
            }
        }
    }

    // MARK: - Mistake Tracker (improvement 2)

    func loadMistakeTracker() -> MistakeTracker {
        queue.sync {
            guard let data = defaults.data(forKey: mistakeTrackerKey) else {
                return MistakeTracker()
            }
            let tracker: MistakeTracker? = try? decoder.decode(MistakeTracker.self, from: data)
            return tracker ?? MistakeTracker()
        }
    }

    func saveMistakeTracker(_ tracker: MistakeTracker) {
        queue.sync {
            if let data = try? encoder.encode(tracker) {
                defaults.set(data, forKey: mistakeTrackerKey)
            }
        }
    }

    // MARK: - Speed Run Records (improvement 3)

    func loadSpeedRunRecords() -> [String: TimeInterval] {
        queue.sync { _loadSpeedRunRecords() }
    }

    func saveSpeedRunRecord(lineID: String, time: TimeInterval) {
        queue.sync {
            var records = _loadSpeedRunRecords()
            if let existing = records[lineID], existing <= time { return }
            records[lineID] = time
            defaults.set(records, forKey: speedRunKey)
        }
    }

    // MARK: - Opening Mastery (v3 — plan-first learning)

    func loadMastery(forOpening openingID: String) -> OpeningMastery {
        queue.sync { _loadMastery(forOpening: openingID) }
    }

    func saveMastery(_ mastery: OpeningMastery) {
        queue.sync { _saveMastery(mastery) }
    }

    func loadAllMastery() -> [String: OpeningMastery] {
        queue.sync { _loadAllMastery() }
    }

    // MARK: - Session Auto-Save (improvement 27)

    func saveSessionState(_ state: [String: Any]) {
        queue.sync {
            defaults.set(state, forKey: "chess_coach_saved_session")
        }
    }

    func loadSessionState() -> [String: Any]? {
        queue.sync {
            defaults.dictionary(forKey: "chess_coach_saved_session")
        }
    }

    func clearSessionState() {
        queue.sync {
            defaults.removeObject(forKey: "chess_coach_saved_session")
        }
    }

    // MARK: - Unsynchronised helpers (must only be called while already on `queue`)

    private func _loadProgress(forOpening openingID: String) -> OpeningProgress {
        let allProgress = _loadAllProgress()
        return allProgress[openingID] ?? OpeningProgress(openingID: openingID)
    }

    private func _saveProgress(_ progress: OpeningProgress) {
        var allProgress = _loadAllProgress()
        allProgress[progress.openingID] = progress
        if let data = try? encoder.encode(allProgress) {
            defaults.set(data, forKey: progressKey)
        }
    }

    private func _loadAllProgress() -> [String: OpeningProgress] {
        guard let data = defaults.data(forKey: progressKey),
              let progress = try? decoder.decode([String: OpeningProgress].self, from: data) else {
            return [:]
        }
        return progress
    }

    private func _loadSpeedRunRecords() -> [String: TimeInterval] {
        defaults.dictionary(forKey: speedRunKey) as? [String: TimeInterval] ?? [:]
    }

    private func _loadMastery(forOpening openingID: String) -> OpeningMastery {
        let allMastery = _loadAllMastery()
        return allMastery[openingID] ?? OpeningMastery(openingID: openingID)
    }

    private func _saveMastery(_ mastery: OpeningMastery) {
        var allMastery = _loadAllMastery()
        allMastery[mastery.openingID] = mastery
        if let data = try? encoder.encode(allMastery) {
            defaults.set(data, forKey: masteryKey)
        }
    }

    private func _loadAllMastery() -> [String: OpeningMastery] {
        guard let data = defaults.data(forKey: masteryKey),
              let mastery = try? decoder.decode([String: OpeningMastery].self, from: data) else {
            return [:]
        }
        return mastery
    }

    // MARK: - Migration

    private func migrateIfNeeded() {
        let currentVersion = defaults.integer(forKey: schemaVersionKey)

        if currentVersion < 2 {
            migrateV1ToV2()
        }
        if currentVersion < 3 {
            migrateV2ToV3()
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

    /// Migrate from v2 (LineProgress/OpeningProgress) to v3 (OpeningMastery).
    /// Converts existing progress data to the new plan-first learning model.
    /// Called from `init` while already on `queue`, so uses unsynchronised helpers.
    private func migrateV2ToV3() {
        let allProgress = _loadAllProgress()
        guard !allProgress.isEmpty else { return }

        var allMastery: [String: OpeningMastery] = [:]
        for (openingID, progress) in allProgress {
            allMastery[openingID] = OpeningMastery.fromLegacy(
                openingID: openingID,
                progress: progress
            )
        }

        if let data = try? encoder.encode(allMastery) {
            defaults.set(data, forKey: masteryKey)
        }
    }
}
