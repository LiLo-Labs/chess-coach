import Foundation

/// Represents the user's current token balance and lifetime stats.
struct TokenBalance: Codable, Sendable {
    var balance: Int = 0
    var totalEarned: Int = 0
    var totalSpent: Int = 0

    mutating func credit(_ amount: Int) {
        balance += amount
        totalEarned += amount
    }

    mutating func debit(_ amount: Int) throws {
        guard balance >= amount else { throw TokenError.insufficientBalance }
        balance -= amount
        totalSpent += amount
    }
}

/// A single token transaction for audit trail.
struct TokenTransaction: Codable, Sendable, Identifiable {
    let id: UUID
    let date: Date
    let amount: Int          // positive = credit, negative = debit
    let reason: Reason
    let detail: String?      // e.g. opening ID, product ID

    enum Reason: String, Codable, Sendable {
        case purchase           // StoreKit token pack
        case dailyBonus         // Free daily login bonus
        case unlockOpening      // Spent to unlock an opening
        case reward             // Earned via achievement/completion
    }

    init(amount: Int, reason: Reason, detail: String? = nil) {
        self.id = UUID()
        self.date = Date()
        self.amount = amount
        self.reason = reason
        self.detail = detail
    }
}

enum TokenError: LocalizedError {
    case insufficientBalance
    case productNotAvailable

    var errorDescription: String? {
        switch self {
        case .insufficientBalance: return "Not enough tokens"
        case .productNotAvailable: return "Token pack not available"
        }
    }
}
