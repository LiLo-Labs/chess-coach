import Testing
import Foundation
@testable import ChessCoach

@Suite(.serialized)
struct PersistenceMigrationTests {
    @Test func saveAndLoadPositionMastery() {
        let service = PersistenceService.shared
        let pm = PositionMastery(openingID: "persist_test", fen: "startpos", ply: 2, lineID: "persist_test/main", correctMove: "e2e4")
        service.savePositionMastery([pm])

        let loaded = service.loadAllPositionMastery()
        let found = loaded.first { $0.openingID == "persist_test" }
        #expect(found != nil)
        #expect(found?.ply == 2)
        #expect(found?.correctMove == "e2e4")
        #expect(found?.lineID == "persist_test/main")

        // Cleanup
        service.savePositionMastery(loaded.filter { $0.openingID != "persist_test" })
    }

    @Test func loadPositionMasteryFilteredByOpening() {
        let service = PersistenceService.shared
        let pm1 = PositionMastery(openingID: "filter_test", fen: "pos1", ply: 1)
        let pm2 = PositionMastery(openingID: "filter_test", fen: "pos2", ply: 3)
        let pm3 = PositionMastery(openingID: "other_opening", fen: "pos3", ply: 1)

        var all = service.loadAllPositionMastery().filter { $0.openingID != "filter_test" && $0.openingID != "other_opening" }
        all.append(contentsOf: [pm1, pm2, pm3])
        service.savePositionMastery(all)

        let filtered = service.loadAllPositionMastery().filter { $0.openingID == "filter_test" }
        #expect(filtered.count == 2)
        #expect(filtered.allSatisfy { $0.openingID == "filter_test" })

        // Cleanup
        service.savePositionMastery(service.loadAllPositionMastery().filter { $0.openingID != "filter_test" && $0.openingID != "other_opening" })
    }

    @Test func positionMasteryFromReviewItem() {
        let item = ReviewItem(openingID: "migrate_test", fen: "startpos", ply: 4, lineID: "migrate_test/main", correctMove: "f1c4")
        let pm = PositionMastery.fromReviewItem(item, mistakeCount: 3, correctCount: 2)

        #expect(pm.openingID == "migrate_test")
        #expect(pm.fen == "startpos")
        #expect(pm.ply == 4)
        #expect(pm.lineID == "migrate_test/main")
        #expect(pm.correctMove == "f1c4")
        #expect(pm.totalAttempts == 5)  // 3 mistakes + 2 correct
        #expect(pm.correctAttempts == 2)
        #expect(pm.id == item.id) // Preserves ID
    }
}
