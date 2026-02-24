import Testing
import Foundation
@testable import ChessCoach

@Suite(.serialized)
struct PersistenceMigrationTests {
    @Test func saveAndLoadLineProgress() {
        let service = PersistenceService.shared
        var progress = OpeningProgress(openingID: "migration_test")
        progress.recordLineGame(lineID: "migration_test/main", accuracy: 0.85, won: true)
        service.saveProgress(progress)

        let loaded = service.loadProgress(forOpening: "migration_test")
        #expect(loaded.gamesPlayed == 1)
        #expect(loaded.lineProgress["migration_test/main"]?.gamesPlayed == 1)
        #expect(loaded.lineProgress["migration_test/main"]?.accuracy == 0.85)
    }

    @Test func loadProgressReturnsDefaultForUnknownOpening() {
        let service = PersistenceService.shared
        let progress = service.loadProgress(forOpening: "never_played_opening_xyz")
        #expect(progress.gamesPlayed == 0)
        #expect(progress.currentPhase == .learningMainLine)
        #expect(progress.lineProgress.isEmpty)
    }

    @Test func multipleLinesSavedIndependently() {
        let service = PersistenceService.shared
        var progress = OpeningProgress(openingID: "multi_line_test")
        progress.recordLineGame(lineID: "multi_line_test/main", accuracy: 0.8, won: true)
        progress.recordLineGame(lineID: "multi_line_test/evans", accuracy: 0.6, won: false)
        service.saveProgress(progress)

        let loaded = service.loadProgress(forOpening: "multi_line_test")
        #expect(loaded.lineProgress.count == 2)
        #expect(loaded.lineProgress["multi_line_test/main"]?.gamesWon == 1)
        #expect(loaded.lineProgress["multi_line_test/evans"]?.gamesWon == 0)
    }
}
