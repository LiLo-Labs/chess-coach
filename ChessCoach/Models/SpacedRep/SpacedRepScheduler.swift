import Foundation

final class SpacedRepScheduler: Sendable {
    private let storage: PersistenceService

    init(storage: PersistenceService = .shared) {
        self.storage = storage
    }

    func addItem(openingID: String, lineID: String? = nil, fen: String, ply: Int, correctMove: String? = nil, playerColor: String? = nil) {
        var items = storage.loadReviewItems()
        // Don't duplicate (check openingID + ply + optional lineID)
        guard !items.contains(where: {
            $0.openingID == openingID && $0.ply == ply && $0.lineID == lineID
        }) else { return }
        let item = ReviewItem(openingID: openingID, fen: fen, ply: ply, lineID: lineID, correctMove: correctMove, playerColor: playerColor)
        items.append(item)
        storage.saveReviewItems(items)
    }

    func dueItems(forOpening openingID: String? = nil) -> [ReviewItem] {
        let items = storage.loadReviewItems()
        return items.filter { item in
            item.isDue && (openingID == nil || item.openingID == openingID)
        }
    }

    /// Get due items for a specific line.
    func dueItems(forLine lineID: String) -> [ReviewItem] {
        let items = storage.loadReviewItems()
        return items.filter { $0.isDue && $0.lineID == lineID }
    }

    func review(itemID: UUID, quality: Int) {
        var items = storage.loadReviewItems()
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].review(quality: quality)
        storage.saveReviewItems(items)
    }

    /// Find a review item by opening and ply.
    func findItem(openingID: String, ply: Int) -> ReviewItem? {
        storage.loadReviewItems().first { $0.openingID == openingID && $0.ply == ply }
    }

    func allItems(forOpening openingID: String) -> [ReviewItem] {
        storage.loadReviewItems().filter { $0.openingID == openingID }
    }
}
