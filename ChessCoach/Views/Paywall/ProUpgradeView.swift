import SwiftUI
import StoreKit

/// Multi-tier paywall showing all subscription options.
/// Optionally shows a "Just this opening" per-path purchase when an opening is specified.
struct ProUpgradeView: View {
    /// Optional: the specific opening the user was trying to access.
    /// When set, shows a per-path unlock option alongside tier upgrades.
    var lockedOpeningID: String?
    var lockedOpeningName: String?

    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(TokenService.self) private var tokenService
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var selectedTier: SubscriptionTier = .pro
    @State private var pathProduct: Product?
    @State private var showTokenStore = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xxl) {
                // Close button
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, AppSpacing.screenPadding)
                .padding(.top, AppSpacing.sm)

                // Header
                Image(systemName: "crown.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppColor.gold)

                Text("Choose Your Plan")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)

                Text("Learn openings your way — upgrade anytime")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xxl)

                // Per-path unlock option (when viewing a specific locked opening)
                if let openingName = lockedOpeningName, let openingID = lockedOpeningID {
                    perPathCard(openingName: openingName, openingID: openingID)
                        .padding(.horizontal, AppSpacing.screenPadding)

                    HStack {
                        VStack { Divider() }
                        Text("or upgrade your plan")
                            .font(.caption)
                            .foregroundStyle(AppColor.tertiaryText)
                        VStack { Divider() }
                    }
                    .padding(.horizontal, AppSpacing.xxl)
                }

                // Tier cards
                VStack(spacing: AppSpacing.md) {
                    tierCard(
                        tier: .onDeviceAI,
                        icon: "cpu",
                        color: .cyan,
                        features: [
                            "AI coaching runs privately on your device",
                            "\"Explain why\" move analysis",
                            "Ask Coach chat during sessions"
                        ]
                    )

                    tierCard(
                        tier: .cloudAI,
                        icon: "cloud",
                        color: .blue,
                        features: [
                            "Everything in On-Device AI",
                            "Connect Claude API or Ollama",
                            "Higher quality AI responses"
                        ]
                    )

                    tierCard(
                        tier: .pro,
                        icon: "crown.fill",
                        color: AppColor.gold,
                        badge: "Best Value",
                        features: [
                            "Everything in Cloud AI",
                            "All openings unlocked",
                            "Advanced learning layers",
                            "All future updates included"
                        ]
                    )
                }
                .padding(.horizontal, AppSpacing.screenPadding)

                // Purchase button
                purchaseButton
                    .padding(.horizontal, AppSpacing.xxl)

                // Restore
                Button("Restore Purchase") {
                    Task { await subscriptionService.restore() }
                }
                .font(.subheadline)
                .foregroundStyle(AppColor.secondaryText)

                if case let .failed(message) = subscriptionService.purchaseState {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(AppColor.error)
                }

                // Legal
                Text("One-time purchase. No subscription.")
                    .font(.caption2)
                    .foregroundStyle(AppColor.tertiaryText)

                Spacer(minLength: AppSpacing.lg)
            }
        }
        .background(AppColor.background)
        .preferredColorScheme(.dark)
        .task {
            do {
                try await subscriptionService.loadProducts()
            } catch {
                errorMessage = error.localizedDescription
            }
            // Load per-path product if a specific opening was specified
            if let openingID = lockedOpeningID {
                pathProduct = await subscriptionService.loadPathProduct(for: openingID)
            }
        }
        .onChange(of: subscriptionService.currentTier) { _, newTier in
            if newTier != .free { dismiss() }
        }
        .onChange(of: subscriptionService.purchaseState) { _, newState in
            // Dismiss when a per-path purchase completes
            if newState == .purchased, lockedOpeningID != nil {
                dismiss()
            }
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Tier Card

    private func tierCard(
        tier: SubscriptionTier,
        icon: String,
        color: Color,
        badge: String? = nil,
        features: [String]
    ) -> some View {
        let isSelected = selectedTier == tier
        let isOwned = subscriptionService.currentTier == tier

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedTier = tier }
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(color)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: AppSpacing.xs) {
                            Text(tier.displayName)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppColor.primaryText)

                            if let badge {
                                Text(badge)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(color, in: Capsule())
                            }

                            if isOwned {
                                Text("Current")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(AppColor.success, in: Capsule())
                            }
                        }

                        if let product = subscriptionService.products[productID(for: tier)] {
                            Text(product.displayPrice)
                                .font(.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                    }

                    Spacer()

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? color : AppColor.tertiaryText)
                }

                ForEach(features, id: \.self) { feature in
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(color.opacity(0.8))
                        Text(feature)
                            .font(.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
            }
            .padding(AppSpacing.cardPadding)
            .background(
                isSelected ? color.opacity(0.08) : AppColor.cardBackground,
                in: RoundedRectangle(cornerRadius: AppRadius.md)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(isSelected ? color : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isOwned)
    }

    // MARK: - Purchase Button

    @ViewBuilder
    private var purchaseButton: some View {
        let tierOwned = subscriptionService.currentTier == selectedTier
        let product = subscriptionService.products[productID(for: selectedTier)]

        if tierOwned {
            Text("You already have \(selectedTier.displayName)")
                .font(.subheadline)
                .foregroundStyle(AppColor.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        } else if let product {
            Button {
                Task { await subscriptionService.purchase(productID: product.id) }
            } label: {
                HStack {
                    if subscriptionService.purchaseState == .purchasing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text("Unlock \(selectedTier.displayName) — \(product.displayPrice)")
                        .font(.body.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColor.guided, in: RoundedRectangle(cornerRadius: AppRadius.lg))
            }
            .buttonStyle(.plain)
            .disabled(subscriptionService.purchaseState == .purchasing)
        } else {
            ProgressView("Loading prices...")
                .padding()
        }
    }

    // MARK: - Per-Path Card

    private func perPathCard(openingName: String, openingID: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: "book.fill")
                    .font(.title3)
                    .foregroundStyle(AppColor.info)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Just this opening")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppColor.primaryText)
                    Text(openingName)
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }

                Spacer()

                if let pathProduct {
                    Text(pathProduct.displayPrice)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppColor.info)
                }
            }

            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppColor.info.opacity(0.8))
                Text("Full access to \(openingName) — all lessons and practice modes")
                    .font(.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }

            // Token unlock option
            let tokenCost = AppConfig.tokenEconomy.openingUnlockCost
            let canAfford = tokenService.canAfford(tokenCost)

            Button {
                if tokenService.unlockOpening(openingID, subscriptionService: subscriptionService) {
                    dismiss()
                }
            } label: {
                HStack {
                    Image(systemName: "star.circle.fill")
                        .font(.caption)
                    Text("Use \(tokenCost) Tokens")
                        .font(.body.weight(.semibold))
                    if !canAfford {
                        Text("(\(tokenService.balance.balance) available)")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    canAfford ? AppColor.gold : AppColor.gold.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: AppRadius.lg)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canAfford)

            // IAP fallback
            Button {
                Task { await subscriptionService.purchasePath(openingID: openingID) }
            } label: {
                HStack {
                    if subscriptionService.purchaseState == .purchasing {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                    Text(pathProduct != nil ? "Buy — \(pathProduct!.displayPrice)" : "Buy Opening")
                        .font(.body.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppColor.info, in: RoundedRectangle(cornerRadius: AppRadius.lg))
            }
            .buttonStyle(.plain)
            .disabled(subscriptionService.purchaseState == .purchasing)

            if !canAfford {
                Button {
                    showTokenStore = true
                } label: {
                    Text("Get more tokens")
                        .font(.caption)
                        .foregroundStyle(AppColor.gold)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.cardPadding)
        .background(AppColor.info.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(AppColor.info.opacity(0.3), lineWidth: 1)
        )
        .sheet(isPresented: $showTokenStore) {
            TokenStoreView()
        }
    }

    // MARK: - Helpers

    private func productID(for tier: SubscriptionTier) -> String {
        switch tier {
        case .onDeviceAI: return SubscriptionService.onDeviceProductID
        case .cloudAI: return SubscriptionService.cloudProductID
        case .pro: return SubscriptionService.proProductID
        case .free: return ""
        }
    }
}

/// Small inline prompt for gated features — shows a lock + "Unlock" button.
struct ProGateBanner: View {
    @Environment(SubscriptionService.self) private var subscriptionService
    @State private var showPaywall = false

    let feature: String

    var body: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(AppColor.gold)
                Text("\(feature) requires upgrade")
                    .font(.caption)
                    .foregroundStyle(AppColor.secondaryText)
                Spacer()
                Text("Unlock")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColor.gold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppColor.gold.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppColor.gold.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.sm))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaywall) {
            ProUpgradeView()
        }
    }
}
