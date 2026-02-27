import Foundation

/// A chess puzzle — a position with one best move to find.
struct Puzzle: Identifiable, Codable, Sendable {
    let id: String
    let fen: String
    let solutionUCI: String       // e.g. "e2e4"
    let solutionSAN: String       // e.g. "e4"
    let theme: Theme
    let difficulty: Int            // 1-5
    let openingID: String?         // Source opening, if applicable
    let explanation: String?       // Why this move is best

    enum Theme: String, Codable, Sendable, CaseIterable {
        case findTheBestMove = "Find the Best Move"
        case openingKnowledge = "Opening Knowledge"
        case mistakeReview = "Mistake Review"
        case mateIn1 = "Mate in 1"
        case mateIn2 = "Mate in 2"

        var icon: String {
            switch self {
            case .findTheBestMove: return "target"
            case .openingKnowledge: return "book.fill"
            case .mistakeReview: return "exclamationmark.triangle.fill"
            case .mateIn1: return "crown.fill"
            case .mateIn2: return "crown.fill"
            }
        }
    }
}

/// Tracks puzzle session results.
struct PuzzleSessionResult: Codable, Sendable {
    var solved: Int = 0
    var failed: Int = 0
    var streak: Int = 0
    var bestStreak: Int = 0
    let date: Date

    init() {
        self.date = Date()
    }

    mutating func recordSolve() {
        solved += 1
        streak += 1
        if streak > bestStreak { bestStreak = streak }
    }

    mutating func recordFail() {
        failed += 1
        streak = 0
    }

    var total: Int { solved + failed }
    var accuracy: Double { total > 0 ? Double(solved) / Double(total) : 0 }
}
