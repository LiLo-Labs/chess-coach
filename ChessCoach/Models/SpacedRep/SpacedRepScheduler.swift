import Foundation

final class SpacedRepScheduler: Sendable {
    private let storage: PersistenceService

    init(storage: PersistenceService = .shared) {
        self.storage = storage
    }

    func addItem(openingID: String, fen: String, ply: Int) {
        var items = storage.loadReviewItems()
        // Don't duplicate
        guard !items.contains(where: { $0.openingID == openingID && $0.ply == ply }) else { return }
        let item = ReviewItem(openingID: openingID, fen: fen, ply: ply)
        items.append(item)
        storage.saveReviewItems(items)
    }

    func dueItems(forOpening openingID: String? = nil) -> [ReviewItem] {
        let items = storage.loadReviewItems()
        return items.filter { item in
            item.isDue && (openingID == nil || item.openingID == openingID)
        }
    }

    func review(itemID: UUID, quality: Int) {
        var items = storage.loadReviewItems()
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].review(quality: quality)
        storage.saveReviewItems(items)
    }

    func allItems(forOpening openingID: String) -> [ReviewItem] {
        storage.loadReviewItems().filter { $0.openingID == openingID }
    }
}
