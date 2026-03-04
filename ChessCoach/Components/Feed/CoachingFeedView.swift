import SwiftUI

/// Unified coaching feed view used across GamePlay, Trainer, and Session modes.
/// Accepts `[FeedEntry]` and renders move-pair-grouped rows with configurable callbacks.
struct CoachingFeedView: View {
    let entries: [FeedEntry]
    let isLoading: Bool
    var explainStyle: FeedRowCard.ExplainStyle = .textAndIcon

    /// Optional header content shown above the feed (e.g., session banners, action buttons).
    var header: AnyView?

    /// Scroll-to-top anchor ID (defaults to "loading").
    var scrollAnchor: String = "loading"

    /// Called when user taps a row. Receives the latest ply in the pair.
    var onTapEntry: ((Int) -> Void)?

    /// Called when user taps Explain. Receives the primary FeedEntry.
    var onRequestExplanation: ((FeedEntry) -> Void)?

    /// Empty state message.
    var emptyMessage: String = "Make your move on the board"

    private var movePairs: [FeedMovePair] {
        FeedMovePair.group(entries)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let header {
                        header
                            .id(scrollAnchor)
                    }

                    if isLoading {
                        FeedLoadingRow()
                            .id("loading")
                    }

                    ForEach(movePairs) { pair in
                        FeedRowCard(
                            pair: pair,
                            isNewest: pair.id == movePairs.first?.id,
                            onTap: { onTapEntry?(pair.latestPly) },
                            explainStyle: explainStyle,
                            onRequestExplanation: onRequestExplanation
                        )
                    }

                    if entries.isEmpty && !isLoading {
                        Text(emptyMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .onChange(of: entries.count) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(scrollAnchor, anchor: .top)
                }
            }
        }
    }
}
