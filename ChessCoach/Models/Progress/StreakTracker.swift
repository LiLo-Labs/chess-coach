import Foundation

struct StreakTracker: Codable, Sendable {
    var practiceDates: [String] = []  // "yyyy-MM-dd" format, sorted, max 365
    var longestStreak: Int = 0
    var streakFreezes: Int = 0  // max 2 (improvement 24)
    var freezeUsedDates: [String] = []  // dates where a freeze was auto-applied

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    var currentStreak: Int {
        guard !practiceDates.isEmpty else { return 0 }
        let today = Self.dateFormatter.string(from: Date())
        let dateSet = Set(practiceDates)
        let freezeSet = Set(freezeUsedDates)

        var streak = 0
        var calendar = Calendar.current
        calendar.timeZone = .current
        var checkDate = Date()

        // If we haven't practiced today, start from yesterday
        if !dateSet.contains(today) && !freezeSet.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: checkDate) else { return 0 }
            let yesterdayStr = Self.dateFormatter.string(from: yesterday)
            if !dateSet.contains(yesterdayStr) && !freezeSet.contains(yesterdayStr) { return 0 }
            checkDate = yesterday
        }

        // Count consecutive days backward (including freeze days)
        while true {
            let dateStr = Self.dateFormatter.string(from: checkDate)
            if dateSet.contains(dateStr) || freezeSet.contains(dateStr) {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = prev
            } else {
                break
            }
        }

        return streak
    }

    var practicedToday: Bool {
        let today = Self.dateFormatter.string(from: Date())
        return practiceDates.contains(today)
    }

    mutating func recordPractice() {
        let today = Self.dateFormatter.string(from: Date())
        guard !practiceDates.contains(today) else { return }
        practiceDates.append(today)
        practiceDates.sort()

        // Trim to last 365 entries
        if practiceDates.count > 365 {
            practiceDates = Array(practiceDates.suffix(365))
        }

        longestStreak = max(longestStreak, currentStreak)

        // Earn a streak freeze for completing a 7-day streak (improvement 24)
        if currentStreak > 0 && currentStreak % 7 == 0 && streakFreezes < 2 {
            streakFreezes = min(streakFreezes + 1, 2)
        }
    }

    /// Auto-use a streak freeze for a missed day. Call on app launch.
    mutating func applyStreakFreezeIfNeeded() {
        guard streakFreezes > 0, !practiceDates.isEmpty else { return }
        let today = Self.dateFormatter.string(from: Date())
        guard !practiceDates.contains(today) else { return }

        var calendar = Calendar.current
        calendar.timeZone = .current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()) else { return }
        let yesterdayStr = Self.dateFormatter.string(from: yesterday)

        // Only freeze if yesterday was a missed day (would break streak)
        if !practiceDates.contains(yesterdayStr) && !freezeUsedDates.contains(yesterdayStr) {
            // Check if the day before yesterday was practiced
            guard let dayBefore = calendar.date(byAdding: .day, value: -2, to: Date()) else { return }
            let dayBeforeStr = Self.dateFormatter.string(from: dayBefore)
            if practiceDates.contains(dayBeforeStr) || freezeUsedDates.contains(dayBeforeStr) {
                freezeUsedDates.append(yesterdayStr)
                streakFreezes -= 1
            }
        }
    }
}
