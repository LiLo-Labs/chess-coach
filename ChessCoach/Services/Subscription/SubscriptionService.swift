import Foundation
import StoreKit

/// Manages subscription tier access via StoreKit 2 IAP.
@Observable
@MainActor
final class SubscriptionService {
    // Product IDs for each paid tier
    static let onDeviceProductID = "com.chesscoach.ondevice"
    static let cloudProductID = "com.chesscoach.cloud"
    static let proProductID = AppConfig.pro.productID

    private(set) var currentTier: SubscriptionTier = .free
    private(set) var unlockedPaths: Set<String> = [] // per-path à la carte unlocks
    private(set) var products: [String: Product] = [:]
    private(set) var purchaseState: PurchaseState = .idle

    /// Backward-compatible convenience — true if any paid tier is active.
    var isPro: Bool { currentTier != .free }

    /// True if tier includes AI capabilities.
    var hasAI: Bool { currentTier.hasAI }

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

    func loadProducts() async throws {
        let ids = [Self.onDeviceProductID, Self.cloudProductID, Self.proProductID]
        let loaded = try await Product.products(for: ids)
        for product in loaded {
            products[product.id] = product
        }
    }

    /// Legacy single-product loader for backward compat.
    func loadProduct() async throws {
        try await loadProducts()
    }

    /// Access the legacy "pro" product for display.
    var product: Product? { products[Self.proProductID] }

    func purchase(productID: String = proProductID) async {
        guard let product = products[productID] else {
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
                await checkEntitlement()
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

    /// Unlock a specific opening path (à la carte purchase).
    /// Called after StoreKit transaction succeeds, or directly for debug/restore.
    func unlockPath(_ pathID: String) {
        unlockedPaths.insert(pathID)
        UserDefaults.standard.set(Array(unlockedPaths), forKey: "chess_coach_unlocked_paths")
    }

    /// Product ID for a per-path unlock. Convention: base prefix + opening ID.
    static func pathProductID(for openingID: String) -> String {
        "com.chesscoach.opening.\(openingID)"
    }

    /// Purchase an individual opening path via StoreKit.
    func purchasePath(openingID: String) async {
        let productID = Self.pathProductID(for: openingID)

        // Load the path product if not already cached
        if products[productID] == nil {
            if let loaded = try? await Product.products(for: [productID]).first {
                products[productID] = loaded
            }
        }

        guard let product = products[productID] else {
            purchaseState = .failed("Opening pack not available")
            return
        }

        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case let .success(verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                unlockPath(openingID)
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

    /// Load per-path product info for display (price etc.)
    func loadPathProduct(for openingID: String) async -> Product? {
        let productID = Self.pathProductID(for: openingID)
        if let cached = products[productID] { return cached }
        if let loaded = try? await Product.products(for: [productID]).first {
            products[productID] = loaded
            return loaded
        }
        return nil
    }

    func restore() async {
        try? await AppStore.sync()
        await checkEntitlement()
        if currentTier != .free {
            purchaseState = .restored
        }
    }

    func isFeatureUnlocked(_ feature: ProFeature) -> Bool {
        let required = SubscriptionTier.minimumTier(for: feature)
        return tierSatisfies(required)
    }

    /// The set of starter opening IDs available in free tier.
    static let freeOpeningIDs: Set<String> = AppConfig.pro.freeOpeningIDs

    /// Check if an opening is accessible in the current tier.
    /// Access policy is centralized here — change this method to adjust paywalling.
    func isOpeningAccessible(_ openingID: String) -> Bool {
        currentTier.hasAllOpenings
        || Self.freeOpeningIDs.contains(openingID)
        || unlockedPaths.contains(openingID)
        || isPickedFreeOpening(openingID)
    }

    /// Check if this is the user's one free-pick opening.
    private func isPickedFreeOpening(_ openingID: String) -> Bool {
        guard let picked = UserDefaults.standard.string(forKey: AppSettings.Key.pickedFreeOpeningID) else {
            return false
        }
        return picked == openingID
    }

    /// Check if a learning layer is accessible in the current tier.
    func isLayerAccessible(_ layer: LearningLayer) -> Bool {
        if layer.isFreeLayer { return true }
        return tierSatisfies(.pro)
    }

    // MARK: - Tier Comparison

    /// Returns true if the user's current tier meets or exceeds the required tier.
    private func tierSatisfies(_ required: SubscriptionTier) -> Bool {
        let order: [SubscriptionTier] = [.free, .onDeviceAI, .cloudAI, .pro]
        guard let currentIdx = order.firstIndex(of: currentTier),
              let requiredIdx = order.firstIndex(of: required) else { return false }
        return currentIdx >= requiredIdx
    }

    // MARK: - Private

    private func checkEntitlement() async {
        // Check debug override first
        #if DEBUG
        if let debugTier = UserDefaults.standard.string(forKey: AppSettings.Key.debugTierOverride),
           let tier = SubscriptionTier(rawValue: debugTier) {
            currentTier = tier
            loadUnlockedPaths()
            return
        }
        // Legacy bool override
        if UserDefaults.standard.bool(forKey: AppSettings.Key.debugProOverride) {
            currentTier = .pro
            loadUnlockedPaths()
            return
        }
        #endif

        // Check StoreKit entitlements — highest tier wins
        var highestTier: SubscriptionTier = .free
        for await result in Transaction.currentEntitlements {
            if case let .verified(transaction) = result {
                switch transaction.productID {
                case Self.proProductID:
                    highestTier = .pro
                case Self.cloudProductID where highestTier != .pro:
                    highestTier = .cloudAI
                case Self.onDeviceProductID where highestTier == .free:
                    highestTier = .onDeviceAI
                default:
                    break
                }
            }
        }
        currentTier = highestTier
        loadUnlockedPaths()
    }

    private func loadUnlockedPaths() {
        let paths = UserDefaults.standard.stringArray(forKey: "chess_coach_unlocked_paths") ?? []
        unlockedPaths = Set(paths)
    }

    private nonisolated func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                if case let .verified(transaction) = result {
                    await transaction.finish()
                    await MainActor.run { [weak self] in
                        Task { await self?.checkEntitlement() }
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
