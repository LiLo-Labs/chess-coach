import SwiftUI
import StoreKit

/// Reusable paywall sheet for upgrading to Pro.
struct ProUpgradeView: View {
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xxl) {
                Spacer(minLength: AppSpacing.xxxl)

                // Icon
                Image(systemName: "crown.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColor.gold)

                // Title
                Text("Unlock ChessCoach Pro")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColor.primaryText)
                    .multilineTextAlignment(.center)

                // Subtitle
                Text("Master openings faster with AI-powered coaching")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xxl)

                // Features list
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    featureRow(icon: "brain", text: "AI-powered coaching explanations")
                    featureRow(icon: "sparkles", text: "Deep \"Explain why\" analysis")
                    featureRow(icon: "cpu", text: "On-device AI model")
                    featureRow(icon: "server.rack", text: "Ollama & Claude API support")
                }
                .padding(.horizontal, AppSpacing.xxl)

                // Free vs Pro comparison table
                comparisonTable
                    .padding(.horizontal, AppSpacing.xxl)

                Spacer(minLength: AppSpacing.sm)

                // Purchase button
                if let product = subscriptionService.product {
                    Button {
                        Task { await subscriptionService.purchase() }
                    } label: {
                        HStack {
                            if subscriptionService.purchaseState == .purchasing {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                            Text("Unlock Pro — \(product.displayPrice)")
                                .font(.body.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColor.guided, in: RoundedRectangle(cornerRadius: AppRadius.lg))
                    }
                    .buttonStyle(.plain)
                    .disabled(subscriptionService.purchaseState == .purchasing)
                    .padding(.horizontal, AppSpacing.xxl)
                } else {
                    ProgressView("Loading...")
                        .padding()
                }

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

                // Legal disclosures
                VStack(spacing: AppSpacing.xxs) {
                    Text("One-time purchase. No subscription.")
                        .font(.caption2)
                        .foregroundStyle(AppColor.tertiaryText)
                }
                .padding(.horizontal, AppSpacing.xxl)

                Spacer(minLength: AppSpacing.lg)
            }
        }
        .background(AppColor.background)
        .preferredColorScheme(.dark)
        .task {
            do {
                try await subscriptionService.loadProduct()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .onChange(of: subscriptionService.isPro) { _, newValue in
            if newValue { dismiss() }
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    // MARK: - Comparison Table

    private var comparisonTable: some View {
        VStack(spacing: AppSpacing.sm) {
            // Header row
            HStack(spacing: 0) {
                Text("Feature")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColor.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Free")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColor.secondaryText)
                    .frame(width: 44, alignment: .center)
                Text("Pro")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColor.gold)
                    .frame(width: 44, alignment: .center)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.bottom, AppSpacing.xxs)

            Divider()
                .background(AppColor.secondaryText.opacity(0.3))

            // Feature rows
            comparisonRow("All openings",        free: true,  pro: true)
            comparisonRow("Board + spaced rep",  free: true,  pro: true)
            comparisonRow("Hardcoded coaching",  free: true,  pro: false)
            comparisonRow("AI coaching",         free: false, pro: true)
            comparisonRow("Deep explanations",   free: false, pro: true)
            comparisonRow("Ask Coach chat",       free: false, pro: true)
            comparisonRow("On-device AI model",  free: false, pro: true)
        }
        .padding(AppSpacing.md)
        .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.md))
    }

    private func comparisonRow(_ label: String, free: Bool, pro: Bool) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(AppColor.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            checkmark(enabled: free)
                .frame(width: 44, alignment: .center)
                .accessibilityLabel(free ? "Included in Free" : "Not included in Free")
            checkmark(enabled: pro, highlightColor: AppColor.gold)
                .frame(width: 44, alignment: .center)
                .accessibilityLabel(pro ? "Included in Pro" : "Not included in Pro")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(free ? "included" : "not included") in Free, \(pro ? "included" : "not included") in Pro")
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xxs)
    }

    private func checkmark(enabled: Bool, highlightColor: Color = AppColor.success) -> some View {
        Group {
            if enabled {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(highlightColor)
            } else {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(AppColor.tertiaryText)
            }
        }
    }

    // MARK: - Feature Row

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(AppColor.gold)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppColor.primaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Small inline prompt for gated features — shows a lock + "Unlock Pro" button.
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
                Text("\(feature) requires Pro")
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
