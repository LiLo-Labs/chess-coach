import SwiftUI

/// Placeholder for the trainer mode — play full games against a bot.
/// Will feature varying bot skill levels and real win/loss conditions.
struct TrainerModeView: View {
    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "figure.fencing")
                .font(.system(size: 64))
                .foregroundStyle(.cyan)

            Text("Trainer")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                featurePreview(icon: "person.2.fill", text: "Play against bots at your skill level")
                featurePreview(icon: "trophy.fill", text: "Real win/loss conditions")
                featurePreview(icon: "brain", text: "AI coaching during the game")
                featurePreview(icon: "chart.line.uptrend.xyaxis", text: "Track your improvement over time")
            }
            .padding(.horizontal, AppSpacing.xxxl)

            Text("Coming soon")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColor.tertiaryText)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColor.cardBackground, in: Capsule())

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(AppColor.background)
        .preferredColorScheme(.dark)
        .navigationTitle("Trainer")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func featurePreview(icon: String, text: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.cyan)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppColor.secondaryText)
        }
    }
}
