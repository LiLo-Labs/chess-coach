import SwiftUI

/// Coaching feed for GamePlayView — delegates to shared CoachingFeedView.
extension GamePlayView {

    @ViewBuilder
    var coachingFeed: some View {
        let feedEntries = viewModel.feedEntries.map { FeedEntry.from($0) }

        if viewModel.mode.isSession {
            CoachingFeedView(
                entries: feedEntries,
                isLoading: viewModel.isEvaluating || viewModel.isCoachingLoading,
                explainStyle: .textAndIcon,
                header: liveStatus,
                scrollAnchor: "live",
                onTapEntry: { ply in
                    viewModel.enterReplay(ply: ply)
                },
                onRequestExplanation: { entry in
                    if let original = viewModel.feedEntries.first(where: { $0.ply == entry.ply }) {
                        viewModel.requestExplanation(for: original)
                    }
                }
            )
            .background(AppColor.background)
        } else {
            CoachingFeedView(
                entries: feedEntries,
                isLoading: viewModel.isEvaluating || viewModel.isCoachingLoading,
                explainStyle: .textAndIcon,
                onTapEntry: { ply in
                    viewModel.enterReplay(ply: ply)
                },
                onRequestExplanation: { entry in
                    if let original = viewModel.feedEntries.first(where: { $0.ply == entry.ply }) {
                        viewModel.requestExplanation(for: original)
                    }
                }
            )
            .background(AppColor.background)
        }
    }

    // MARK: - Live Status (Session)

    @ViewBuilder
    private var liveStatus: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            if let variation = viewModel.suggestedVariation {
                variationBanner(variation: variation)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.xxs)
            }

            if case let .userDeviated(expected, _) = viewModel.bookStatus {
                DeviationBanner.UserDeviation(
                    expected: expected,
                    isUnguided: viewModel.mode.sessionMode == .unguided
                )
                .padding(.horizontal, AppSpacing.lg)
            } else if case let .opponentDeviated(expected, playedSAN, _) = viewModel.bookStatus {
                DeviationBanner.OpponentDeviation(
                    expected: expected,
                    playedSAN: playedSAN,
                    bestMoveDescription: viewModel.bestResponseDescription
                )
                .padding(.horizontal, AppSpacing.lg)
            } else if case .offBook = viewModel.bookStatus {
                DeviationBanner.OffBook(bestMoveDescription: viewModel.bestResponseDescription)
                    .padding(.horizontal, AppSpacing.lg)
            } else if viewModel.discoveryMode {
                DeviationBanner.Discovery(optionCount: viewModel.branchPointOptions?.count ?? 2)
                    .padding(.horizontal, AppSpacing.lg)
            }

            sessionActionButtons
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.xxs)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.bookStatus)
    }

    // MARK: - Session Action Buttons

    @ViewBuilder
    private var sessionActionButtons: some View {
        HStack(spacing: AppSpacing.sm) {
            if case .userDeviated = viewModel.bookStatus {
                Button(action: { viewModel.retryLastMove() }) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.orange)
                .controlSize(.small)

                Button(action: { Task { await viewModel.continueAfterDeviation() } }) {
                    Text("Continue")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.secondary)
                .controlSize(.small)
            }

            if case .opponentDeviated = viewModel.bookStatus {
                Button(action: { Task { await viewModel.restartSession() } }) {
                    Label("Retry", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.mint)
                .controlSize(.small)
            }

            if case .offBook = viewModel.bookStatus {
                Button(action: { Task { await viewModel.restartSession() } }) {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.cyan)
                .controlSize(.small)
            }

            Spacer()
        }
    }

    // MARK: - Variation Banner

    private func variationBanner(variation: OpeningLine) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption2)
                .foregroundStyle(.teal)
            Text("You played into the \(variation.name)")
                .font(.caption)
                .foregroundStyle(.teal)
            Spacer()
            Button {
                viewModel.switchToLine(variation)
            } label: {
                Text("Switch")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.teal)
                    .padding(.horizontal, AppSpacing.md - 2)
                    .padding(.vertical, AppSpacing.xxs)
                    .buttonBackground(.teal.opacity(0.12))
            }
            .buttonStyle(.plain)
        }
        .padding(AppSpacing.md - 2)
        .background(Color.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.sm))
    }
}
