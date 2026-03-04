import Foundation

final class SpacedRepScheduler: Sendable {
    private let storage: PersistenceService

    init(storage: PersistenceService = .shared) {
        self.storage = storage
    }

    func addItem(openingID: String, lineID: String? = nil, fen: String, ply: Int, correctMove: String? = nil, playerColor: String? = nil) {
        var positions = storage.loadAllPositionMastery()
        let candidate = PositionMastery(openingID: openingID, fen: fen, ply: ply, lineID: lineID, correctMove: correctMove, playerColor: playerColor)
        guard !positions.contains(where: { $0.positionKey == candidate.positionKey }) else { return }
        positions.append(candidate)
        storage.savePositionMastery(positions)
    }

    func dueItems(forOpening openingID: String? = nil) -> [PositionMastery] {
        storage.loadAllPositionMastery().filter { p in
            p.isDue && (openingID == nil || p.openingID == openingID)
        }
    }

    func dueItems(forLine lineID: String) -> [PositionMastery] {
        storage.loadAllPositionMastery().filter { $0.isDue && $0.lineID == lineID }
    }

    func dueItems() -> [PositionMastery] {
        dueItems(forOpening: nil)
    }

    func review(itemID: UUID, quality: Int) {
        var positions = storage.loadAllPositionMastery()
        guard let index = positions.firstIndex(where: { $0.id == itemID }) else { return }
        positions[index].review(quality: quality)
        storage.savePositionMastery(positions)
    }

    func recordAttempt(id: UUID, correct: Bool) {
        var positions = storage.loadAllPositionMastery()
        guard let index = positions.firstIndex(where: { $0.id == id }) else { return }
        positions[index].recordAttempt(correct: correct)
        storage.savePositionMastery(positions)
    }

    func findItem(openingID: String, ply: Int) -> PositionMastery? {
        storage.loadAllPositionMastery().first { $0.openingID == openingID && $0.ply == ply }
    }

    func allItems(forOpening openingID: String) -> [PositionMastery] {
        storage.loadAllPositionMastery().filter { $0.openingID == openingID }
    }
}
