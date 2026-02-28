import Testing
import Foundation
@testable import ChessCoach

@Suite(.serialized)
struct OpeningDatabaseTests {
    @Test func databaseLoadsAllOpenings() {
        let db = OpeningDatabase()
        #expect(db.openings.count >= 10)
    }

    @Test func allOpeningsHaveMainLine() {
        let db = OpeningDatabase()
        for opening in db.openings {
            #expect(!opening.mainLine.isEmpty, "Opening \(opening.name) has empty main line")
            #expect(opening.mainLine.count >= 6, "Opening \(opening.name) has fewer than 6 moves")
        }
    }

    @Test func allOpeningsHaveValidMoves() {
        let db = OpeningDatabase()
        for opening in db.openings {
            for move in opening.mainLine {
                #expect(move.uci.count >= 4, "Move \(move.uci) in \(opening.name) is too short")
                #expect(!move.san.isEmpty, "SAN empty for move in \(opening.name)")
                #expect(!move.explanation.isEmpty, "Explanation empty for move \(move.san) in \(opening.name)")
            }
        }
    }

    @Test func openingByIDWorks() {
        let db = OpeningDatabase()
        let italian = db.opening(byID: "italian")
        #expect(italian != nil)
        #expect(italian?.name == "Italian Game")
    }

    @Test func openingByNameWorks() {
        let db = OpeningDatabase()
        let london = db.opening(named: "London System")
        #expect(london != nil)
        #expect(london?.id == "london")
    }

    @Test func colorFilteringIsComplete() {
        let db = OpeningDatabase()
        let white = db.openings(forColor: .white)
        let black = db.openings(forColor: .black)
        #expect(white.count + black.count == db.openings.count)
        #expect(white.allSatisfy { $0.color == .white })
        #expect(black.allSatisfy { $0.color == .black })
    }

    @Test func openingIsHashable() {
        let db = OpeningDatabase()
        let italian = db.opening(named: "Italian Game")!
        var set = Set<Opening>()
        set.insert(italian)
        #expect(set.contains(italian))
    }

    @Test func difficultyRange() {
        let db = OpeningDatabase()
        for opening in db.openings {
            #expect(opening.difficulty >= 1 && opening.difficulty <= 5,
                    "Opening \(opening.name) has invalid difficulty \(opening.difficulty)")
        }
    }

    @Test func whiteOpeningsStartWithWhiteMove() {
        let db = OpeningDatabase()
        for opening in db.openings(forColor: .white) {
            let firstMove = opening.mainLine[0].uci
            // White moves go from ranks 1-2 (pieces start on 1-2)
            let fromRank = firstMove.dropFirst().first!
            #expect(fromRank == "1" || fromRank == "2",
                    "White opening \(opening.name) first move \(firstMove) doesn't start from white's side")
        }
    }

    @Test func mainLineMovesReplayCorrectly() {
        let db = OpeningDatabase()
        for opening in db.openings {
            let gs = GameState()
            for (i, move) in opening.mainLine.enumerated() {
                let result = gs.makeMoveUCI(move.uci)
                #expect(result, "MainLine replay failed: \(opening.id) move \(i) '\(move.uci)' at FEN: \(gs.fen)")
                if !result { break }
            }
        }
    }

    @Test func lineMovesReplayCorrectly() {
        let db = OpeningDatabase()
        for opening in db.openings {
            guard let lines = opening.lines else { continue }
            for line in lines {
                let gs = GameState()
                for (i, move) in line.moves.enumerated() {
                    let result = gs.makeMoveUCI(move.uci)
                    #expect(result, "Line replay failed: \(opening.id)/\(line.id) move \(i) '\(move.uci)' at FEN: \(gs.fen)")
                    if !result { break }
                }
            }
        }
    }

    @Test func puzzleGenerationFromOpeningsWorks() {
        let db = OpeningDatabase()
        var puzzleCount = 0
        for opening in db.openings {
            let moves = opening.mainLine
            guard moves.count >= 4 else { continue }

            let gs = GameState()
            var ok = true
            for i in 0..<2 {
                if !gs.makeMoveUCI(moves[i].uci) {
                    ok = false
                    break
                }
            }
            guard ok else { continue }

            let solution = moves[2]
            if gs.makeMoveUCI(solution.uci) {
                puzzleCount += 1
            }
        }
        #expect(puzzleCount > 0, "Should generate at least some puzzles from opening data")
        print("[PuzzleTest] Generated \(puzzleCount) puzzles from \(db.openings.count) openings")
    }
}
