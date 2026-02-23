import Foundation

final class PersistenceService: @unchecked Sendable {
    static let shared = PersistenceService()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let progressKey = "chess_coach_progress"
    private let reviewItemsKey = "chess_coach_review_items"

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
}
