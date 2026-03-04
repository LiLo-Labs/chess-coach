import Testing
import Foundation
@testable import ChessCoach

@Suite(.serialized)
struct SpacedRepIntegrationTests {
    @Test func positionMasteryWithLineID() {
        let pm = PositionMastery(openingID: "italian", fen: "startpos", ply: 4, lineID: "italian/main", correctMove: "f1c4")
        #expect(pm.lineID == "italian/main")
        #expect(pm.correctMove == "f1c4")
        #expect(pm.isDue)
    }

    @Test func positionMasteryDefaultsWithoutLineID() {
        let pm = PositionMastery(openingID: "italian", fen: "startpos", ply: 4)
        #expect(pm.lineID == nil)
        #expect(pm.correctMove == nil)
    }

    @Test func schedulerFindItemByOpeningAndPly() {
        let storage = PersistenceService.shared
        storage.savePositionMastery([])

        let scheduler = SpacedRepScheduler(storage: storage)
        scheduler.addItem(openingID: "test_find", lineID: "test_find/main", fen: "startpos", ply: 3, correctMove: "e2e4")

        let found = scheduler.findItem(openingID: "test_find", ply: 3)
        #expect(found != nil)
        #expect(found?.correctMove == "e2e4")

        let notFound = scheduler.findItem(openingID: "test_find", ply: 99)
        #expect(notFound == nil)

        storage.savePositionMastery([])
    }

    @Test func schedulerDueItemsForLine() {
        let storage = PersistenceService.shared
        storage.savePositionMastery([])

        let scheduler = SpacedRepScheduler(storage: storage)
        scheduler.addItem(openingID: "test_line", lineID: "test_line/main", fen: "pos1", ply: 1)
        scheduler.addItem(openingID: "test_line", lineID: "test_line/evans", fen: "pos2", ply: 2)
        scheduler.addItem(openingID: "test_line", lineID: "test_line/main", fen: "pos3", ply: 3)

        let mainDue = scheduler.dueItems(forLine: "test_line/main")
        #expect(mainDue.count == 2)

        let evansDue = scheduler.dueItems(forLine: "test_line/evans")
        #expect(evansDue.count == 1)

        storage.savePositionMastery([])
    }

    @Test func schedulerNoDuplicates() {
        let storage = PersistenceService.shared
        storage.savePositionMastery([])

        let scheduler = SpacedRepScheduler(storage: storage)
        scheduler.addItem(openingID: "dup_test", lineID: "dup_test/main", fen: "pos1", ply: 1)
        scheduler.addItem(openingID: "dup_test", lineID: "dup_test/main", fen: "pos1", ply: 1)

        let items = scheduler.dueItems(forLine: "dup_test/main")
        #expect(items.count == 1)

        storage.savePositionMastery([])
    }

    @Test func schedulerReviewUpdatesItem() {
        let storage = PersistenceService.shared
        storage.savePositionMastery([])

        let scheduler = SpacedRepScheduler(storage: storage)
        scheduler.addItem(openingID: "review_test", fen: "pos1", ply: 1)

        let items = scheduler.dueItems(forOpening: "review_test")
        #expect(items.count == 1)

        scheduler.review(itemID: items[0].id, quality: 5)

        // After review with quality 5, item should no longer be due (scheduled for tomorrow)
        let afterReview = scheduler.dueItems(forOpening: "review_test")
        #expect(afterReview.isEmpty)

        storage.savePositionMastery([])
    }
}
