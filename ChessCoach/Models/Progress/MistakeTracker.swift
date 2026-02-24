import Foundation

/// Tracks mistake patterns across sessions (improvement 2).
struct MistakeRecord: Codable, Sendable, Identifiable {
    var id: String { "\(openingID)/\(lineID ?? "main")/\(ply)" }
    let openingID: String
    let lineID: String?
    let ply: Int
    let expectedMove: String  // UCI
    var playedMoves: [String: Int] = [:]  // UCI -> count
    var totalCount: Int = 0
}

struct MistakeTracker: Codable, Sendable {
    var records: [String: MistakeRecord] = [:]  // keyed by MistakeRecord.id

    /// Record a mistake at a specific position.
    mutating func recordMistake(openingID: String, lineID: String?, ply: Int, expectedMove: String, playedMove: String) {
        let key = "\(openingID)/\(lineID ?? "main")/\(ply)"
        if records[key] == nil {
            records[key] = MistakeRecord(openingID: openingID, lineID: lineID, ply: ply, expectedMove: expectedMove)
        }
        records[key]?.playedMoves[playedMove, default: 0] += 1
        records[key]?.totalCount += 1
    }

    /// Get common mistakes for an opening, sorted by frequency.
    func mistakes(forOpening openingID: String) -> [MistakeRecord] {
        records.values
            .filter { $0.openingID == openingID }
            .sorted { $0.totalCount > $1.totalCount }
    }

    /// Get common mistakes for a specific line.
    func mistakes(forLine lineID: String) -> [MistakeRecord] {
        records.values
            .filter { $0.lineID == lineID }
            .sorted { $0.totalCount > $1.totalCount }
    }

    /// Get the most problematic positions (for daily puzzle, improvement 7).
    func topMistakes(count: Int = 5) -> [MistakeRecord] {
        Array(records.values.sorted { $0.totalCount > $1.totalCount }.prefix(count))
    }
}
