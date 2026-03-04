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

    private let streakKey = "chess_coach_streak"
    private let mistakeTrackerKey = "chess_coach_mistakes"
    private let speedRunKey = "chess_coach_speed_runs"
    private let importedGamesKey = "chess_coach_imported_games"
    private let positionMasteryKey = "chess_coach_position_mastery"

    // MARK: - Position Mastery (v4 — position-level spaced rep)

    func savePositionMastery(_ positions: [PositionMastery]) {
        queue.sync {
            if let data = try? encoder.encode(positions) {
                defaults.set(data, forKey: positionMasteryKey)
            }
        }
    }

    func loadAllPositionMastery() -> [PositionMastery] {
        queue.sync {
            guard let data = defaults.data(forKey: positionMasteryKey),
                  let positions = try? decoder.decode([PositionMastery].self, from: data) else {
                return []
            }
            return positions
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

    // MARK: - Mistake Tracker

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

    // MARK: - Speed Run Records

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

    // MARK: - Session Auto-Save

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

    // MARK: - Imported Games

    func loadImportedGames() -> [ImportedGame] {
        queue.sync {
            guard let data = defaults.data(forKey: importedGamesKey),
                  let games = try? decoder.decode([ImportedGame].self, from: data) else {
                return []
            }
            return games
        }
    }

    func saveImportedGames(_ games: [ImportedGame]) {
        queue.sync {
            if let data = try? encoder.encode(games) {
                defaults.set(data, forKey: importedGamesKey)
            }
        }
    }

    /// Append new games, deduplicating by id.
    func appendImportedGames(_ newGames: [ImportedGame]) {
        queue.sync {
            var existing: [ImportedGame] = []
            if let data = defaults.data(forKey: importedGamesKey),
               let decoded = try? decoder.decode([ImportedGame].self, from: data) {
                existing = decoded
            }
            let existingIDs = Set(existing.map(\.id))
            let unique = newGames.filter { !existingIDs.contains($0.id) }
            let merged = existing + unique
            if let data = try? encoder.encode(merged) {
                defaults.set(data, forKey: importedGamesKey)
            }
        }
    }

    // MARK: - Private

    private func _loadSpeedRunRecords() -> [String: TimeInterval] {
        defaults.dictionary(forKey: speedRunKey) as? [String: TimeInterval] ?? [:]
    }
}
