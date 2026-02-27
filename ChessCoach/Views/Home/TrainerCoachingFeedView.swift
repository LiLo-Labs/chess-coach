import SwiftUI

/// Scrollable per-move coaching feed shown during trainer games.
/// Each entry shows the move, coaching text, and quality indicator.
struct TrainerCoachingFeedView: View {
    let entries: [TrainerCoachingEntry]
    let isLoading: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(entries) { entry in
                        feedCard(entry)
                            .id(entry.id)
                    }

                    if isLoading {
                        loadingCard
                    }
                }
                .padding(.horizontal, AppSpacing.screenPadding)
            }
            .onChange(of: entries.count) {
                if let last = entries.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(last.id, anchor: .trailing)
                    }
                }
            }
        }
        .frame(height: 80)
    }

    // MARK: - Feed Card

    private func feedCard(_ entry: TrainerCoachingEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Move + quality badge
            HStack(spacing: 4) {
                Text(entry.moveLabel)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(AppColor.primaryText)

                categoryBadge(entry)
            }

            // Coaching text
            Text(entry.coaching)
                .font(.system(size: 10))
                .foregroundStyle(AppColor.secondaryText)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            // Opening indicator
            if let name = entry.openingName {
                HStack(spacing: 2) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 7))
                    Text(entry.isInBook ? name : "Off book")
                        .font(.system(size: 8))
                }
                .foregroundStyle(entry.isInBook ? .cyan.opacity(0.7) : AppColor.warning.opacity(0.7))
            }
        }
        .padding(8)
        .frame(width: 160, alignment: .leading)
        .background(cardBackground(for: entry), in: RoundedRectangle(cornerRadius: 8))
    }

    private func categoryBadge(_ entry: TrainerCoachingEntry) -> some View {
        Group {
            if let sc = entry.scoreCategory {
                Text(sc.displayName)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(categoryColor(sc))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(categoryColor(sc).opacity(0.15), in: Capsule())
            } else {
                // No eval — show move category
                Text(entry.category.feedLabel)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(moveCategoryColor(entry.category))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(moveCategoryColor(entry.category).opacity(0.15), in: Capsule())
            }
        }
    }

    private func cardBackground(for entry: TrainerCoachingEntry) -> Color {
        if !entry.isPlayerMove {
            return AppColor.cardBackground.opacity(0.5)
        }
        if let sc = entry.scoreCategory {
            return categoryColor(sc).opacity(0.06)
        }
        return AppColor.cardBackground
    }

    private var loadingCard: some View {
        VStack {
            ProgressView()
                .controlSize(.small)
                .tint(AppColor.secondaryText)
            Text("Evaluating...")
                .font(.system(size: 9))
                .foregroundStyle(AppColor.tertiaryText)
        }
        .frame(width: 80, height: 60)
        .background(AppColor.cardBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Colors

    private func categoryColor(_ sc: ScoreCategory) -> Color {
        switch sc {
        case .masterful: return AppColor.gold
        case .strong: return AppColor.success
        case .solid: return AppColor.info
        case .developing: return AppColor.warning
        case .needsWork: return AppColor.error
        }
    }

    private func moveCategoryColor(_ mc: MoveCategory) -> Color {
        switch mc {
        case .goodMove: return AppColor.success
        case .okayMove: return AppColor.info
        case .mistake: return AppColor.error
        case .deviation: return AppColor.warning
        case .opponentMove: return AppColor.secondaryText
        }
    }
}

// MARK: - MoveCategory Feed Label

extension MoveCategory {
    var feedLabel: String {
        switch self {
        case .goodMove: return "Good"
        case .okayMove: return "OK"
        case .mistake: return "Mistake"
        case .deviation: return "Deviation"
        case .opponentMove: return "Opponent"
        }
    }
}
