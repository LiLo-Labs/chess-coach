import Foundation

struct ReviewItem: Codable, Identifiable, Sendable {
    let id: UUID
    let openingID: String
    let fen: String
    let ply: Int

    // SM-2 fields
    var interval: Int        // days until next review
    var easeFactor: Double   // >= 1.3
    var repetitions: Int     // consecutive correct responses
    var nextReviewDate: Date

    init(openingID: String, fen: String, ply: Int) {
        self.id = UUID()
        self.openingID = openingID
        self.fen = fen
        self.ply = ply
        self.interval = 1
        self.easeFactor = 2.5
        self.repetitions = 0
        self.nextReviewDate = Date()
    }

    /// Quality: 0 (complete failure) to 5 (perfect response)
    mutating func review(quality: Int) {
        let q = max(0, min(5, quality))

        if q < 3 {
            // Failed — reset
            repetitions = 0
            interval = 1
        } else {
            switch repetitions {
            case 0:
                interval = 1
            case 1:
                interval = 6
            default:
                interval = Int(Double(interval) * easeFactor)
            }
            repetitions += 1
        }

        // Update ease factor
        let qd = Double(q)
        easeFactor = easeFactor + (0.1 - (5.0 - qd) * (0.08 + (5.0 - qd) * 0.02))
        easeFactor = max(1.3, easeFactor)

        nextReviewDate = Calendar.current.date(byAdding: .day, value: interval, to: Date()) ?? Date()
    }

    var isDue: Bool {
        nextReviewDate <= Date()
    }
}
