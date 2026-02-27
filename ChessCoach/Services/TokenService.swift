import Foundation
import StoreKit

/// Manages the token economy: balance, purchases, rewards, and spending.
/// Injected as environment object at the app root.
@Observable
@MainActor
final class TokenService {
    private(set) var balance: TokenBalance
    private(set) var transactions: [TokenTransaction]
    private(set) var products: [String: Product] = [:]
    private(set) var purchaseState: PurchaseState = .idle

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case purchased
        case failed(String)
    }

    private let balanceKey = "chess_coach_token_balance"
    private let transactionsKey = "chess_coach_token_transactions"
    private let lastDailyBonusKey = "chess_coach_last_daily_bonus"
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        // Load persisted balance
        if let data = UserDefaults.standard.data(forKey: balanceKey),
           let saved = try? JSONDecoder().decode(TokenBalance.self, from: data) {
            self.balance = saved
        } else {
            self.balance = TokenBalance()
        }

        // Load transaction history (keep last 100)
        if let data = UserDefaults.standard.data(forKey: transactionsKey),
           let saved = try? JSONDecoder().decode([TokenTransaction].self, from: data) {
            self.transactions = saved
        } else {
            self.transactions = []
        }
    }

    // MARK: - Balance Operations

    /// Credit tokens to the balance (purchase, reward, daily bonus).
    func credit(_ amount: Int, reason: TokenTransaction.Reason, detail: String? = nil) {
        balance.credit(amount)
        record(TokenTransaction(amount: amount, reason: reason, detail: detail))
        save()
    }

    /// Spend tokens. Throws if insufficient balance.
    func spend(_ amount: Int, reason: TokenTransaction.Reason, detail: String? = nil) throws {
        try balance.debit(amount)
        record(TokenTransaction(amount: -amount, reason: reason, detail: detail))
        save()
    }

    /// Check if user can afford a given cost.
    func canAfford(_ cost: Int) -> Bool {
        balance.balance >= cost
    }

    /// Unlock an opening by spending tokens. Returns true on success.
    func unlockOpening(_ openingID: String, subscriptionService: SubscriptionService) -> Bool {
        let cost = AppConfig.tokenEconomy.openingUnlockCost
        do {
            try spend(cost, reason: .unlockOpening, detail: openingID)
            subscriptionService.unlockPath(openingID)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Daily Bonus

    /// Claim today's daily bonus if not already claimed. Returns the amount credited, or 0 if already claimed.
    func claimDailyBonus() -> Int {
        let today = todayString
        guard defaults.string(forKey: lastDailyBonusKey) != today else { return 0 }

        let amount = AppConfig.tokenEconomy.dailyBonusAmount
        credit(amount, reason: .dailyBonus)
        defaults.set(today, forKey: lastDailyBonusKey)
        return amount
    }

    /// Whether the daily bonus has been claimed today.
    var isDailyBonusClaimed: Bool {
        defaults.string(forKey: lastDailyBonusKey) == todayString
    }

    // MARK: - StoreKit Purchases

    func loadProducts() async throws {
        let ids = AppConfig.tokenEconomy.packs.map(\.productID)
        let loaded = try await Product.products(for: Set(ids))
        for product in loaded {
            products[product.id] = product
        }
    }

    func purchasePack(productID: String) async {
        guard let product = products[productID] else {
            purchaseState = .failed("Token pack not available")
            return
        }

        guard let pack = AppConfig.tokenEconomy.packs.first(where: { $0.productID == productID }) else {
            purchaseState = .failed("Unknown token pack")
            return
        }

        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case let .success(verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                credit(pack.amount, reason: .purchase, detail: productID)
                purchaseState = .purchased
            case .userCancelled:
                purchaseState = .idle
            case .pending:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Rewards

    /// Award tokens for completing a learning layer.
    func rewardLayerCompletion(openingID: String, layer: String) {
        let amount = AppConfig.tokenEconomy.layerCompletionReward
        credit(amount, reason: .reward, detail: "\(openingID):\(layer)")
    }

    // MARK: - Private

    private func record(_ transaction: TokenTransaction) {
        transactions.insert(transaction, at: 0)
        // Keep only recent history
        if transactions.count > 100 {
            transactions = Array(transactions.prefix(100))
        }
    }

    private func save() {
        if let data = try? encoder.encode(balance) {
            defaults.set(data, forKey: balanceKey)
        }
        if let data = try? encoder.encode(transactions) {
            defaults.set(data, forKey: transactionsKey)
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case let .unverified(_, error):
            throw error
        case let .verified(safe):
            return safe
        }
    }

    private var todayString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt.string(from: Date())
    }
}
