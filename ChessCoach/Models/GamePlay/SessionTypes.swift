import Foundation

func debugLog(_ message: String) {
    #if DEBUG
    let dateStr = ISO8601DateFormatter().string(from: Date())
    let line = "[\(dateStr)] \(message)\n"
    let tmp = FileManager.default.temporaryDirectory
    let logFile = tmp.appendingPathComponent("chesscoach_debug.log")
    if let handle = try? FileHandle(forWritingTo: logFile) {
        handle.seekToEndOfFile()
        if let data = line.data(using: .utf8) { handle.write(data) }
        handle.synchronizeFile()
        handle.closeFile()
    } else {
        try? line.data(using: .utf8)?.write(to: logFile)
    }
    #endif
}

struct ExplainContext {
    let fen: String
    let move: String
    let san: String?
    let ply: Int
    let moveHistory: [String]
    let coachingText: String
    let hasPlayed: Bool
}

enum BookStatus: Equatable, Sendable {
    case onBook
    case userDeviated(expected: OpeningMove, atPly: Int)
    case opponentDeviated(expected: OpeningMove, playedSAN: String, atPly: Int)
    case offBook(since: Int)
}

enum SessionMode: String, Codable, Sendable {
    case guided
    case unguided
    case practice
}

struct SessionStats {
    var movesOnBook: Int = 0
    var totalUserMoves: Int = 0
    var deviationPly: Int?
    var deviatedBy: DeviatedBy?
    var restarts: Int = 0
    var moveScores: [PlanExecutionScore] = []

    enum DeviatedBy { case user, opponent }

    var accuracy: Double {
        guard totalUserMoves > 0 else { return 0 }
        return Double(movesOnBook) / Double(totalUserMoves)
    }

    var averagePES: Double {
        guard !moveScores.isEmpty else { return 0 }
        return Double(moveScores.map(\.total).reduce(0, +)) / Double(moveScores.count)
    }

    var pesCategory: ScoreCategory {
        ScoreCategory.from(score: Int(averagePES))
    }
}
