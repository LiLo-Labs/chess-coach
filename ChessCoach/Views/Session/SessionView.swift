import SwiftUI

struct SessionView: View {
    @State private var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    init(opening: Opening) {
        self._viewModel = State(initialValue: SessionViewModel(opening: opening))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            sessionHeader

            Spacer()

            // Coaching bubble
            if let coaching = viewModel.coachingText {
                CoachingBubble(text: coaching, isLoading: viewModel.isCoachingLoading)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Board
            GameBoardView(
                gameState: viewModel.gameState,
                allowInteraction: viewModel.isUserTurn && !viewModel.isThinking && !viewModel.sessionComplete
            ) { from, to in
                Task {
                    await viewModel.userMoved(from: from, to: to)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .padding()

            // Status bar
            statusBar

            Spacer()
        }
        .background(Color(.systemGroupedBackground))
        .overlay {
            if viewModel.sessionComplete {
                sessionCompleteOverlay
            }
        }
        .task {
            await viewModel.startSession()
        }
    }

    // MARK: - Subviews

    private var sessionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.opening.name)
                    .font(.headline)
                Text("Move \(viewModel.moveCount / 2 + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("End Session") {
                viewModel.endSession()
                dismiss()
            }
            .font(.subheadline)
            .foregroundStyle(.red)
        }
        .padding()
    }

    private var statusBar: some View {
        HStack {
            if viewModel.isThinking {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Opponent thinking...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.isUserTurn {
                Text("Your turn")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text("Opponent's turn")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: viewModel.opening.color == .white ? "circle" : "circle.fill")
                    .font(.caption2)
                Text("Playing \(viewModel.opening.color == .white ? "White" : "Black")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var sessionCompleteOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                Text("Session Complete!")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("You practiced the \(viewModel.opening.name) opening through \(viewModel.moveCount / 2) moves.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(40)
        }
    }
}
