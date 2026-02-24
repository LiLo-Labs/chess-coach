import SwiftUI

struct OpeningCard: View {
    let opening: Opening
    private let progress: OpeningProgress

    init(opening: Opening) {
        self.opening = opening
        self.progress = PersistenceService.shared.loadProgress(forOpening: opening.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.lg) {
                // Color indicator
                Circle()
                    .fill(opening.color == .white ? Color.white : Color(white: 0.35))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .strokeBorder(AppColor.tertiaryText, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                    Text(opening.name)
                        .font(.headline)
                        .foregroundStyle(AppColor.primaryText)

                    Text(opening.description)
                        .font(.caption)
                        .foregroundStyle(AppColor.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                // Progress indicator
                VStack(alignment: .trailing, spacing: 2) {
                    if progress.gamesPlayed > 0 {
                        Text(progress.gamesPlayed >= 3 ? "\(Int(progress.accuracy * 100))%" : "\(progress.gamesPlayed) played")
                            .font(.subheadline.monospacedDigit().weight(.bold))
                            .foregroundStyle(AppColor.primaryText)

                        if progress.totalLineCount > 0 {
                            Text("\(progress.masteredLineCount)/\(progress.totalLineCount) lines")
                                .font(.caption2)
                                .foregroundStyle(AppColor.secondaryText)
                        } else {
                            Text("\(progress.gamesPlayed) played")
                                .font(.caption2)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                    } else {
                        Text("New")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppColor.tertiaryText)
                    }
                }
            }

            // Progress bar toward next phase
            if progress.gamesPlayed > 0, let threshold = progress.currentPhase.promotionThreshold {
                ProgressView(value: progress.compositeScore, total: threshold)
                    .tint(AppColor.phase(progress.currentPhase))
                    .scaleEffect(y: 0.5)
                    .padding(.top, 4)
            }

            // Stage mini-pipeline: guided and unguided line counts
            if progress.totalLineCount > 0 {
                HStack(spacing: AppSpacing.xs) {
                    Text("\(progress.guidedLineCount)/\(progress.totalLineCount) guided · \(progress.unguidedLineCount)/\(progress.totalLineCount) unguided")
                        .font(.caption2)
                        .foregroundStyle(AppColor.tertiaryText)
                    Spacer()
                }
                .padding(.top, AppSpacing.xxxs)
            }

            // Last-played timestamp
            if progress.lastPlayed != nil {
                HStack {
                    Text(TimeAgo.string(from: progress.lastPlayed))
                        .font(.caption2)
                        .foregroundStyle(AppColor.tertiaryText)
                    Spacer()
                }
                .padding(.top, AppSpacing.xxxs)
            }
        }
        .appCard()
    }
}
