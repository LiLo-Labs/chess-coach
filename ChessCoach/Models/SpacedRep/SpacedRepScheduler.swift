import Foundation

final class SpacedRepScheduler: Sendable {
    private let storage: PersistenceService

    init(storage: PersistenceService = .shared) {
        self.storage = storage
    }

    // MARK: - PositionMastery API

    func addPosition(openingID: String, lineID: String? = nil, fen: String, ply: Int, correctMove: String? = nil, playerColor: String? = nil) {
        var positions = storage.loadAllPositionMastery()
        let key = "\(openingID)/\(lineID ?? "main")/\(ply)"
        guard !positions.contains(where: { $0.positionKey == key }) else { return }
        let position = PositionMastery(openingID: openingID, fen: fen, ply: ply, lineID: lineID, correctMove: correctMove, playerColor: playerColor)
        positions.append(position)
        storage.savePositionMastery(positions)
    }

    func duePositions(forOpening openingID: String? = nil) -> [PositionMastery] {
        let positions = storage.loadAllPositionMastery()
        return positions.filter { p in
            p.isDue && (openingID == nil || p.openingID == openingID)
        }
    }

    func duePositions(forLine lineID: String) -> [PositionMastery] {
        storage.loadAllPositionMastery().filter { $0.isDue && $0.lineID == lineID }
    }

    func reviewPosition(id: UUID, quality: Int) {
        var positions = storage.loadAllPositionMastery()
        guard let index = positions.firstIndex(where: { $0.id == id }) else { return }
        positions[index].review(quality: quality)
        storage.savePositionMastery(positions)
    }

    func recordAttempt(id: UUID, correct: Bool) {
        var positions = storage.loadAllPositionMastery()
        guard let index = positions.firstIndex(where: { $0.id == id }) else { return }
        positions[index].recordAttempt(correct: correct)
        storage.savePositionMastery(positions)
    }

    func findPosition(openingID: String, ply: Int) -> PositionMastery? {
        storage.loadAllPositionMastery().first { $0.openingID == openingID && $0.ply == ply }
    }

    func allPositions(forOpening openingID: String) -> [PositionMastery] {
        storage.loadAllPositionMastery().filter { $0.openingID == openingID }
    }

    // MARK: - Bridge API (wraps PositionMastery as ReviewItem-compatible)

    func addItem(openingID: String, lineID: String? = nil, fen: String, ply: Int, correctMove: String? = nil, playerColor: String? = nil) {
        addPosition(openingID: openingID, lineID: lineID, fen: fen, ply: ply, correctMove: correctMove, playerColor: playerColor)
    }

    func dueItems(forOpening openingID: String? = nil) -> [PositionMastery] {
        duePositions(forOpening: openingID)
    }

    func dueItems(forLine lineID: String) -> [PositionMastery] {
        duePositions(forLine: lineID)
    }

    func dueItems() -> [PositionMastery] {
        duePositions()
    }

    func review(itemID: UUID, quality: Int) {
        reviewPosition(id: itemID, quality: quality)
    }

    func findItem(openingID: String, ply: Int) -> PositionMastery? {
        findPosition(openingID: openingID, ply: ply)
    }

    func allItems(forOpening openingID: String) -> [PositionMastery] {
        allPositions(forOpening: openingID)
    }
}
