import SwiftUI

/// Vertical per-move coaching feed shown during trainer games.
/// Thin wrapper around shared CoachingFeedView, converting TrainerCoachingEntry to FeedEntry.
struct TrainerCoachingFeedView: View {
    let entries: [TrainerCoachingEntry]
    let isLoading: Bool
    var onTapEntry: ((Int) -> Void)?
    var onRequestExplanation: ((TrainerCoachingEntry) -> Void)?

    /// Map to unified FeedEntry (1-based -> 0-based ply conversion).
    private var feedEntries: [FeedEntry] {
        entries.map { FeedEntry.from($0) }
    }

    var body: some View {
        CoachingFeedView(
            entries: feedEntries,
            isLoading: isLoading,
            explainStyle: .textAndIcon,
            onTapEntry: onTapEntry,
            onRequestExplanation: { feedEntry in
                // Bridge back to TrainerCoachingEntry by matching 1-based ply
                let oneBasedPly = feedEntry.ply + 1
                if let original = entries.first(where: { $0.ply == oneBasedPly }) {
                    onRequestExplanation?(original)
                }
            }
        )
    }
}
