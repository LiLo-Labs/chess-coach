import SwiftUI

/// Replay scrub controls for GamePlayView.
extension GamePlayView {

    @ViewBuilder
    var replayBar: some View {
        if viewModel.gameState.plyCount > 0 {
            HStack(spacing: 4) {
                Button { viewModel.enterReplay(ply: 0) } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.body)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(viewModel.isReplaying && viewModel.replayPly == 0)

                Button {
                    let current = viewModel.replayPly ?? viewModel.gameState.plyCount
                    viewModel.enterReplay(ply: current - 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(viewModel.isReplaying && viewModel.replayPly == 0)

                Spacer()

                if viewModel.isReplaying {
                    Text("Move \(viewModel.replayPly ?? 0) of \(viewModel.gameState.plyCount)")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Ply \(viewModel.gameState.plyCount)")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    let current = viewModel.replayPly ?? viewModel.gameState.plyCount
                    viewModel.enterReplay(ply: current + 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!viewModel.isReplaying)

                Button { viewModel.exitReplay() } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.body)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(!viewModel.isReplaying)

                if viewModel.isReplaying {
                    Button { viewModel.exitReplay() } label: {
                        Text("Resume")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .buttonBackground(.green.opacity(0.12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(.white.opacity(0.6))
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.screenPadding)
        }
    }
}
