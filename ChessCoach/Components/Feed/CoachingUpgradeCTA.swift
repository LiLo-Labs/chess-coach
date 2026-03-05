import SwiftUI

/// Tappable prompt encouraging free-tier users to upgrade for deeper coaching analysis.
struct CoachingUpgradeCTA: View {
    @State private var showPaywall = false

    var body: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(AppColor.gold)
                Text("Unlock deeper analysis")
                    .font(.caption)
                    .foregroundStyle(AppColor.secondaryText)
                Spacer()
                Text("Upgrade")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColor.gold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColor.gold.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(AppColor.gold.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.sm))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaywall) {
            ProUpgradeView()
        }
    }
}
