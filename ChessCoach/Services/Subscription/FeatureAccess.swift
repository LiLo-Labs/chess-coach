import Foundation

/// Protocol for service-level feature gating. Services query this instead
/// of receiving `isPro: Bool` parameters, keeping subscription logic out of
/// business logic.
protocol FeatureAccessProviding: Sendable {
    func isUnlocked(_ feature: ProFeature) async -> Bool
}

/// Production implementation backed by SubscriptionService.
final class FeatureAccess: FeatureAccessProviding, @unchecked Sendable {
    private let subscriptionService: SubscriptionService

    init(subscriptionService: SubscriptionService) {
        self.subscriptionService = subscriptionService
    }

    func isUnlocked(_ feature: ProFeature) async -> Bool {
        await MainActor.run { subscriptionService.isFeatureUnlocked(feature) }
    }
}

/// Simple implementation that gates based on a static tier.
/// Used as a default / backward-compat shim while views still pass `isPro: Bool`.
final class StaticFeatureAccess: FeatureAccessProviding, Sendable {
    private let tier: SubscriptionTier

    init(isPro: Bool) {
        self.tier = isPro ? .pro : .free
    }

    init(tier: SubscriptionTier) {
        self.tier = tier
    }

    func isUnlocked(_ feature: ProFeature) async -> Bool {
        let required = SubscriptionTier.minimumTier(for: feature)
        let order: [SubscriptionTier] = [.free, .onDeviceAI, .cloudAI, .pro]
        guard let currentIdx = order.firstIndex(of: tier),
              let requiredIdx = order.firstIndex(of: required) else { return false }
        return currentIdx >= requiredIdx
    }
}

/// Convenience: everything unlocked (for previews, tests, etc.).
final class UnlockedAccess: FeatureAccessProviding, Sendable {
    func isUnlocked(_ feature: ProFeature) async -> Bool { true }
}
