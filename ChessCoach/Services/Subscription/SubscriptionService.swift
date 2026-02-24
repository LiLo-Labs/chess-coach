import Foundation
import StoreKit

/// Manages Pro tier access via StoreKit 2 non-consumable IAP.
@Observable
@MainActor
final class SubscriptionService {
    static let proProductID = "com.chesscoach.pro.lifetime"

    private(set) var isPro: Bool = false
    private(set) var product: Product?
    private(set) var purchaseState: PurchaseState = .idle

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case purchased
        case failed(String)
        case restored
    }

    private var transactionListener: Task<Void, Never>?

    init() {
        let listener = listenForTransactions()
        transactionListener = listener
        Task { await checkEntitlement() }
    }

    func tearDown() {
        transactionListener?.cancel()
    }

    // MARK: - Public API

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            product = products.first
        } catch {
            print("[ChessCoach] Failed to load products: \(error)")
        }
    }

    func purchase() async {
        guard let product else {
            purchaseState = .failed("Product not available")
            return
        }

        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case let .success(verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                isPro = true
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

    func restore() async {
        try? await AppStore.sync()
        await checkEntitlement()
        if isPro {
            purchaseState = .restored
        }
    }

    func isFeatureUnlocked(_ feature: ProFeature) -> Bool {
        isPro
    }

    // MARK: - Private

    private func checkEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case let .verified(transaction) = result,
               transaction.productID == Self.proProductID {
                isPro = true
                return
            }
        }
        // No entitlement found — check UserDefaults override for testing
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debug_pro_override") {
            isPro = true
            return
        }
        #endif
        isPro = false
    }

    private nonisolated func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                if case let .verified(transaction) = result,
                   transaction.productID == "com.chesscoach.pro.lifetime" {
                    await transaction.finish()
                    await MainActor.run { [weak self] in
                        self?.isPro = true
                        self?.purchaseState = .purchased
                    }
                }
            }
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
}
