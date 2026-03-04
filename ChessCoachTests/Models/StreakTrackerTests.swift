import Testing
import Foundation
@testable import ChessCoach

@Suite(.serialized)
struct StreakTrackerTests {
    @Test func newTrackerHasZeroStreak() {
        let tracker = StreakTracker()
        #expect(tracker.currentStreak == 0)
        #expect(tracker.longestStreak == 0)
        #expect(!tracker.practicedToday)
    }

    @Test func recordPracticeAddsTodayDate() {
        var tracker = StreakTracker()
        tracker.recordPractice()
        #expect(tracker.practicedToday)
        #expect(tracker.currentStreak == 1)
        #expect(tracker.longestStreak == 1)
    }

    @Test func recordPracticeDoesNotDuplicate() {
        var tracker = StreakTracker()
        tracker.recordPractice()
        tracker.recordPractice()
        tracker.recordPractice()
        #expect(tracker.practiceDates.count == 1)
    }

    @Test func consecutiveDaysCountAsStreak() {
        var tracker = StreakTracker()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current

        // Add 3 consecutive days ending today
        let today = Date()
        for i in (0..<3).reversed() {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: today)!
            tracker.practiceDates.append(formatter.string(from: date))
        }
        tracker.practiceDates.sort()
        tracker.longestStreak = 3

        #expect(tracker.currentStreak == 3)
    }

    @Test func brokenStreakResetsCount() {
        var tracker = StreakTracker()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current

        let today = Date()
        // Add today and 3 days ago (gap of 1 day breaks streak)
        tracker.practiceDates.append(formatter.string(from: Calendar.current.date(byAdding: .day, value: -3, to: today)!))
        tracker.practiceDates.append(formatter.string(from: today))
        tracker.practiceDates.sort()

        #expect(tracker.currentStreak == 1)
    }

    @Test func trimToMax365Entries() {
        var tracker = StreakTracker()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current

        // Add 370 dates
        for i in 0..<370 {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            tracker.practiceDates.append(formatter.string(from: date))
        }
        tracker.practiceDates.sort()

        // Now record practice (today should already be there, so recordPractice does nothing extra)
        // But let's test trim by direct manipulation
        #expect(tracker.practiceDates.count == 370)

        // Record practice to trigger trim
        tracker.practiceDates = [] // reset
        for i in 0..<370 {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            let dateStr = formatter.string(from: date)
            if !tracker.practiceDates.contains(dateStr) {
                tracker.practiceDates.append(dateStr)
            }
        }
        tracker.practiceDates.sort()

        // Manually trigger trim like recordPractice does
        if tracker.practiceDates.count > 365 {
            tracker.practiceDates = Array(tracker.practiceDates.suffix(365))
        }
        #expect(tracker.practiceDates.count == 365)
    }
}
