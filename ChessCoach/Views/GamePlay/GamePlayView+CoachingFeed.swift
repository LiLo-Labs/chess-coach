import SwiftUI

/// Coaching feed for GamePlayView — delegates to shared CoachingFeedView.
extension GamePlayView {

    var coachingFeed: some View {
        let feedEntries = viewModel.feedEntries.map { FeedEntry.from($0) }

        return CoachingFeedView(
            entries: feedEntries,
            isLoading: viewModel.isEvaluating || viewModel.isCoachingLoading,
            explainStyle: .textAndIcon,
            header: viewModel.mode.isSession ? AnyView(liveStatus) : nil,
            scrollAnchor: viewModel.mode.isSession ? "live" : "loading",
            onTapEntry: { ply in
                viewModel.enterReplay(ply: ply)
            },
            onRequestExplanation: { entry in
                // Bridge back to CoachingEntry-based explanation via matching ply
                if let original = viewModel.feedEntries.first(where: { $0.ply == entry.ply }) {
                    viewModel.requestExplanation(for: original)
                }
            }
        )
        .background(AppColor.background)
    }

    // MARK: - Live Status (Session)

    @ViewBuilder
    private var liveStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let variation = viewModel.suggestedVariation {
                variationBanner(variation: variation)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            if case let .userDeviated(expected, _) = viewModel.bookStatus {
                DeviationBanner.UserDeviation(
                    expected: expected,
                    isUnguided: viewModel.mode.sessionMode == .unguided
                )
                .padding(.horizontal, 16)
            } else if case let .opponentDeviated(expected, playedSAN, _) = viewModel.bookStatus {
                DeviationBanner.OpponentDeviation(
                    expected: expected,
                    playedSAN: playedSAN,
                    bestMoveDescription: viewModel.bestResponseDescription
                )
                .padding(.horizontal, 16)
            } else if case .offBook = viewModel.bookStatus {
                DeviationBanner.OffBook(bestMoveDescription: viewModel.bestResponseDescription)
                    .padding(.horizontal, 16)
            } else if viewModel.discoveryMode {
                DeviationBanner.Discovery(optionCount: viewModel.branchPointOptions?.count ?? 2)
                    .padding(.horizontal, 16)
            }

            sessionActionButtons
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.bookStatus)
    }

    // MARK: - Session Action Buttons

    @ViewBuilder
    private var sessionActionButtons: some View {
        HStack(spacing: 8) {
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
        HStack(spacing: 8) {
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.teal.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
