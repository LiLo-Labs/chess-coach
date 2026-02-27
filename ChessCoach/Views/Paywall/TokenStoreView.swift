import SwiftUI

/// View for purchasing token packs and viewing balance/history.
struct TokenStoreView: View {
    @Environment(TokenService.self) private var tokenService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Balance section
                Section {
                    HStack {
                        Image(systemName: "star.circle.fill")
                            .font(.title)
                            .foregroundStyle(AppColor.gold)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(tokenService.balance.balance)")
                                .font(.title2.weight(.bold).monospacedDigit())
                                .foregroundStyle(AppColor.primaryText)
                            Text("tokens available")
                                .font(.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        }

                        Spacer()

                        if !tokenService.isDailyBonusClaimed {
                            Button {
                                let _ = tokenService.claimDailyBonus()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "gift.fill")
                                        .font(.caption)
                                    Text("+\(AppConfig.tokenEconomy.dailyBonusAmount)")
                                        .font(.caption.weight(.bold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppColor.success, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Bonus claimed")
                                .font(.caption)
                                .foregroundStyle(AppColor.tertiaryText)
                        }
                    }
                }
                .listRowBackground(AppColor.cardBackground)

                // Token packs
                Section("Get More Tokens") {
                    ForEach(AppConfig.tokenEconomy.packs, id: \.productID) { pack in
                        tokenPackRow(pack: pack)
                    }
                }
                .listRowBackground(AppColor.cardBackground)

                // What tokens can do
                Section("What You Can Do") {
                    infoRow(icon: "book.fill", color: AppColor.info, text: "Unlock any opening — \(AppConfig.tokenEconomy.openingUnlockCost) tokens")
                    infoRow(icon: "gift.fill", color: AppColor.success, text: "Daily bonus — \(AppConfig.tokenEconomy.dailyBonusAmount) free tokens/day")
                    infoRow(icon: "star.fill", color: AppColor.gold, text: "Complete layers — earn \(AppConfig.tokenEconomy.layerCompletionReward) tokens")
                }
                .listRowBackground(AppColor.cardBackground)

                // Recent transactions
                if !tokenService.transactions.isEmpty {
                    Section("Recent Activity") {
                        ForEach(tokenService.transactions.prefix(20)) { transaction in
                            transactionRow(transaction)
                        }
                    }
                    .listRowBackground(AppColor.cardBackground)
                }
            }
            .listStyle(.insetGrouped)
            .background(AppColor.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("Token Store")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
            }
            .task {
                try? await tokenService.loadProducts()
            }
        }
    }

    // MARK: - Token Pack Row

    private func tokenPackRow(pack: (productID: String, amount: Int, label: String)) -> some View {
        HStack {
            Image(systemName: "star.circle.fill")
                .font(.title3)
                .foregroundStyle(AppColor.gold)

            VStack(alignment: .leading, spacing: 2) {
                Text(pack.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.primaryText)
            }

            Spacer()

            if let product = tokenService.products[pack.productID] {
                Button {
                    Task { await tokenService.purchasePack(productID: pack.productID) }
                } label: {
                    Text(product.displayPrice)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppColor.guided, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(tokenService.purchaseState == .purchasing)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Info Row

    private func infoRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(text)
                .font(.caption)
                .foregroundStyle(AppColor.secondaryText)
        }
    }

    // MARK: - Transaction Row

    private func transactionRow(_ transaction: TokenTransaction) -> some View {
        HStack {
            Image(systemName: transaction.amount > 0 ? "plus.circle.fill" : "minus.circle.fill")
                .font(.caption)
                .foregroundStyle(transaction.amount > 0 ? AppColor.success : AppColor.error)

            VStack(alignment: .leading, spacing: 1) {
                Text(transactionLabel(transaction))
                    .font(.caption)
                    .foregroundStyle(AppColor.primaryText)
                Text(transaction.date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
            }

            Spacer()

            Text(transaction.amount > 0 ? "+\(transaction.amount)" : "\(transaction.amount)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(transaction.amount > 0 ? AppColor.success : AppColor.error)
        }
    }

    private func transactionLabel(_ transaction: TokenTransaction) -> String {
        switch transaction.reason {
        case .purchase: return "Token pack"
        case .dailyBonus: return "Daily bonus"
        case .unlockOpening: return "Unlocked opening"
        case .reward: return "Layer completed"
        }
    }
}
