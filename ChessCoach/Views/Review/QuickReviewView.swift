import SwiftUI
import ChessKit

struct QuickReviewView: View {
    let openingID: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var items: [ReviewItem] = []
    @State private var currentIndex = 0
    @State private var reviewedCount = 0
    @State private var feedbackState: FeedbackState = .waiting
    @State private var gameState: GameState
    @State private var consecutiveCorrect = 0

    private let scheduler = SpacedRepScheduler()
    private let db = OpeningDatabase()

    enum FeedbackState: Equatable {
        case waiting
        case correct
        case wrong(correctMove: String)
    }

    init(openingID: String? = nil) {
        self.openingID = openingID
        self._gameState = State(initialValue: GameState())
    }

    private var currentItem: ReviewItem? {
        guard currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    private var allDone: Bool {
        currentIndex >= items.count && !items.isEmpty
    }

    // Look up the opening name for a given openingID string
    private func openingName(for id: String) -> String? {
        db.opening(byID: id)?.name
    }

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            if items.isEmpty {
                allCaughtUpView
            } else if allDone {
                completedView
            } else if let item = currentItem {
                reviewItemView(item: item)
            }
        }
        .padding(AppSpacing.screenPadding)
        .background(AppColor.background)
        .preferredColorScheme(.dark)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadItems()
        }
    }

    // MARK: - Views

    private var allCaughtUpView: some View {
        EmptyStateView(
            icon: "checkmark.circle.fill",
            title: "All caught up!",
            subtitle: "No positions to review right now. Come back later.",
            actionTitle: "Done",
            action: { dismiss() }
        )
    }

    private var completedView: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.success)
            Text("All caught up!")
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColor.primaryText)
            Text("\(reviewedCount) position\(reviewedCount == 1 ? "" : "s") reviewed")
                .font(.subheadline)
                .foregroundStyle(AppColor.secondaryText)

            Button("Done") { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(AppColor.success, in: Capsule())
                .buttonStyle(.plain)
        }
    }

    private func reviewItemView(item: ReviewItem) -> some View {
        VStack(spacing: AppSpacing.lg) {
            // Progress header: count + optional opening name
            VStack(spacing: AppSpacing.xs) {
                // Opening context
                if let name = openingName(for: item.openingID) {
                    Text(name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.secondaryText)
                }

                Text("What's the correct move here?")
                    .font(.headline)
                    .foregroundStyle(AppColor.primaryText)
            }

            // Progress indicator
            progressIndicator

            // Streak indicator
            if consecutiveCorrect >= 3 {
                HStack(spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.xxs) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(AppColor.warning)
                        Text("\(consecutiveCorrect) in a row!")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppColor.warning)
                    }

                    if settings.bestReviewStreak > 0 {
                        Text("Best: \(settings.bestReviewStreak)")
                            .font(.caption2)
                            .foregroundStyle(consecutiveCorrect > settings.bestReviewStreak
                                             ? AppColor.gold : AppColor.tertiaryText)
                    }
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xxs)
                .background(AppColor.warning.opacity(0.12), in: Capsule())
            }

            // Board — interactive when waiting for answer
            GameBoardView(
                gameState: gameState,
                perspective: gameState.isWhiteTurn ? .white : .black,
                allowInteraction: feedbackState == .waiting
            ) { from, to in
                handleMove(from: from, to: to, item: item)
            }
            .aspectRatio(1, contentMode: .fit)

            // Feedback
            switch feedbackState {
            case .waiting:
                Text("Play the correct move on the board")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)

            case .correct:
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.success)
                    Text("Correct!")
                        .font(.headline)
                        .foregroundStyle(AppColor.success)
                }
                .sensoryFeedback(.success, trigger: feedbackState)

            case .wrong(let correctMove):
                VStack(spacing: AppSpacing.xxs) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColor.error)
                        Text("Not quite")
                            .font(.headline)
                            .foregroundStyle(AppColor.error)
                    }
                    Text("The correct move was \(correctMove)")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                }
                .sensoryFeedback(.error, trigger: feedbackState)
            }

            if feedbackState != .waiting {
                Button("Next") {
                    advanceToNext()
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(AppColor.guided, in: Capsule())
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        let total = items.count
        let current = currentIndex + 1
        let fraction = total > 0 ? Double(current) / Double(total) : 0

        return VStack(spacing: AppSpacing.xxs) {
            HStack {
                Text("\(current) of \(total)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColor.secondaryText)
                Spacer()
                Text("\(Int(fraction * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppColor.tertiaryText)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColor.cardBackground)
                        .frame(height: 4)
                    Capsule()
                        .fill(AppColor.guided)
                        .frame(width: geo.size.width * CGFloat(fraction), height: 4)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: fraction)
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - Logic

    private func loadItems() {
        if let openingID {
            items = scheduler.dueItems(forOpening: openingID)
        } else {
            items = scheduler.dueItems()
        }
        currentIndex = 0
        reviewedCount = 0
        consecutiveCorrect = 0
        loadCurrentPosition()
    }

    private func loadCurrentPosition() {
        guard let item = currentItem else { return }
        gameState.reset(fen: item.fen)
        feedbackState = .waiting
    }

    private func handleMove(from: String, to: String, item: ReviewItem) {
        let uciMove = from + to
        if let correct = item.correctMove, uciMove == correct {
            feedbackState = .correct
            scheduler.review(itemID: item.id, quality: 4)
            consecutiveCorrect += 1
            if consecutiveCorrect > settings.bestReviewStreak {
                settings.bestReviewStreak = consecutiveCorrect
            }
        } else {
            feedbackState = .wrong(correctMove: item.correctMove ?? "unknown")
            scheduler.review(itemID: item.id, quality: 1)
            consecutiveCorrect = 0
        }
        reviewedCount += 1
    }

    private func advanceToNext() {
        currentIndex += 1
        if currentIndex < items.count {
            loadCurrentPosition()
        }
    }
}
