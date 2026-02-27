import SwiftUI

/// Placeholder for the puzzle/tactics training mode.
/// Will feature pin, fork, skewer, mate-in-N puzzles with difficulty scaling.
struct PuzzleModeView: View {
    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "puzzlepiece.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("Puzzles")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                featurePreview(icon: "target", text: "Pin, fork, skewer, discovered attack")
                featurePreview(icon: "crown.fill", text: "Mate-in-1, mate-in-2, mate-in-3")
                featurePreview(icon: "chart.bar.fill", text: "Difficulty scales with your skill")
                featurePreview(icon: "calendar", text: "Daily puzzle challenge")
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
        .navigationTitle("Puzzles")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func featurePreview(icon: String, text: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.orange)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppColor.secondaryText)
        }
    }
}
