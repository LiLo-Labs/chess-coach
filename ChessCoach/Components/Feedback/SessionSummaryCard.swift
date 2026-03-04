import SwiftUI

/// Reusable post-session statistics display card.
/// Used in puzzle completion, session completion, and assessment results.
struct SessionSummaryCard: View {
    let stats: [Stat]
    var icon: String = "trophy.fill"
    var iconColor: Color = AppColor.gold
    var title: String = "Session Complete"

    struct Stat: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundStyle(iconColor)

            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)

            VStack(spacing: AppSpacing.md) {
                ForEach(stats) { stat in
                    HStack {
                        Text(stat.label)
                            .font(.subheadline)
                            .foregroundStyle(AppColor.secondaryText)
                        Spacer()
                        Text(stat.value)
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(AppColor.primaryText)
                    }
                }
            }
            .padding(AppSpacing.cardPadding)
            .background(AppColor.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.md))
        }
    }
}
