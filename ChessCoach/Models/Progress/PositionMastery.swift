import Foundation

/// Per-position spaced repetition mastery.
/// Superset of ReviewItem: same SM-2 fields plus attempt tracking.
/// Key: openingID + ply + lineID.
struct PositionMastery: Codable, Identifiable, Sendable {
    let id: UUID
    let openingID: String
    let fen: String
    let ply: Int
    var lineID: String?
    var correctMove: String?
    var playerColor: String?

    // SM-2 fields (from ReviewItem)
    var interval: Int
    var easeFactor: Double
    var repetitions: Int
    var nextReviewDate: Date

    // Attempt tracking
    var totalAttempts: Int
    var correctAttempts: Int

    init(
        openingID: String,
        fen: String,
        ply: Int,
        lineID: String? = nil,
        correctMove: String? = nil,
        playerColor: String? = nil
    ) {
        self.id = UUID()
        self.openingID = openingID
        self.fen = fen
        self.ply = ply
        self.lineID = lineID
        self.correctMove = correctMove
        self.playerColor = playerColor
        self.interval = 1
        self.easeFactor = 2.5
        self.repetitions = 0
        self.nextReviewDate = Date()
        self.totalAttempts = 0
        self.correctAttempts = 0
    }

    /// Unique position key for deduplication and lookup.
    var positionKey: String {
        "\(openingID)/\(lineID ?? "main")/\(ply)"
    }

    var isDue: Bool {
        nextReviewDate <= Date()
    }

    var accuracy: Double {
        totalAttempts > 0 ? Double(correctAttempts) / Double(totalAttempts) : 0
    }

    var isMastered: Bool {
        repetitions >= 3 && accuracy >= 0.8
    }

    /// SM-2 review. Quality: 0 (complete failure) to 5 (perfect response).
    mutating func review(quality: Int) {
        let q = max(0, min(5, quality))

        if q < 3 {
            repetitions = 0
            interval = 1
        } else {
            switch repetitions {
            case 0: interval = 1
            case 1: interval = 6
            default: interval = Int(Double(interval) * easeFactor)
            }
            repetitions += 1
        }

        let qd = Double(q)
        easeFactor = easeFactor + (0.1 - (5.0 - qd) * (0.08 + (5.0 - qd) * 0.02))
        easeFactor = max(1.3, easeFactor)

        nextReviewDate = Calendar.current.date(byAdding: .day, value: interval, to: Date()) ?? Date()
    }

    /// Record a play attempt at this position.
    mutating func recordAttempt(correct: Bool) {
        totalAttempts += 1
        if correct { correctAttempts += 1 }
    }

    /// Create from a legacy ReviewItem, optionally seeding accuracy from MistakeTracker.
    static func fromReviewItem(_ item: ReviewItem, mistakeCount: Int = 0, correctCount: Int = 0) -> PositionMastery {
        var pm = PositionMastery(
            openingID: item.openingID,
            fen: item.fen,
            ply: item.ply,
            lineID: item.lineID,
            correctMove: item.correctMove,
            playerColor: item.playerColor
        )
        pm.id = item.id
        pm.interval = item.interval
        pm.easeFactor = item.easeFactor
        pm.repetitions = item.repetitions
        pm.nextReviewDate = item.nextReviewDate
        pm.totalAttempts = mistakeCount + correctCount
        pm.correctAttempts = correctCount
        return pm
    }

    // Allow overwriting id for migration
    private enum CodingKeys: String, CodingKey {
        case id, openingID, fen, ply, lineID, correctMove, playerColor
        case interval, easeFactor, repetitions, nextReviewDate
        case totalAttempts, correctAttempts
    }
}

// Allow `id` to be set during migration
extension PositionMastery {
    init(
        id: UUID,
        openingID: String,
        fen: String,
        ply: Int,
        lineID: String? = nil,
        correctMove: String? = nil,
        playerColor: String? = nil
    ) {
        self.id = id
        self.openingID = openingID
        self.fen = fen
        self.ply = ply
        self.lineID = lineID
        self.correctMove = correctMove
        self.playerColor = playerColor
        self.interval = 1
        self.easeFactor = 2.5
        self.repetitions = 0
        self.nextReviewDate = Date()
        self.totalAttempts = 0
        self.correctAttempts = 0
    }
}
