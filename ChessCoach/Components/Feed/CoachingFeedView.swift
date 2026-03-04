import SwiftUI

/// Unified coaching feed view used across GamePlay, Trainer, and Session modes.
/// Accepts `[FeedEntry]` and renders move-pair-grouped rows with configurable callbacks.
struct CoachingFeedView<Header: View>: View {
    let entries: [FeedEntry]
    let isLoading: Bool
    var explainStyle: FeedRowCard.ExplainStyle = .textAndIcon

    /// Optional header content shown above the feed (e.g., session banners, action buttons).
    var header: Header?

    /// Scroll-to-top anchor ID (defaults to "loading").
    var scrollAnchor: String = "loading"

    /// Called when user taps a row. Receives the latest ply in the pair.
    var onTapEntry: ((Int) -> Void)?

    /// Called when user taps Explain. Receives the primary FeedEntry.
    var onRequestExplanation: ((FeedEntry) -> Void)?

    /// Empty state message.
    var emptyMessage: String = "Make your move on the board"

    var body: some View {
        let pairs = FeedMovePair.group(entries)

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

                    ForEach(pairs) { pair in
                        FeedRowCard(
                            pair: pair,
                            isNewest: pair.id == pairs.first?.id,
                            onTap: { onTapEntry?(pair.latestPly) },
                            explainStyle: explainStyle,
                            onRequestExplanation: onRequestExplanation
                        )
                    }

                    if entries.isEmpty && !isLoading {
                        Text(emptyMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, AppSpacing.sm)
                    }
                }
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.md)
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

/// Convenience initializer when no header is needed.
extension CoachingFeedView where Header == EmptyView {
    init(
        entries: [FeedEntry],
        isLoading: Bool,
        explainStyle: FeedRowCard.ExplainStyle = .textAndIcon,
        scrollAnchor: String = "loading",
        onTapEntry: ((Int) -> Void)? = nil,
        onRequestExplanation: ((FeedEntry) -> Void)? = nil,
        emptyMessage: String = "Make your move on the board"
    ) {
        self.entries = entries
        self.isLoading = isLoading
        self.explainStyle = explainStyle
        self.header = nil
        self.scrollAnchor = scrollAnchor
        self.onTapEntry = onTapEntry
        self.onRequestExplanation = onRequestExplanation
        self.emptyMessage = emptyMessage
    }
}
