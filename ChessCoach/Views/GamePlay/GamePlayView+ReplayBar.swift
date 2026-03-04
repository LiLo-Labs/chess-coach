import SwiftUI

/// Replay scrub controls for GamePlayView.
extension GamePlayView {

    @ViewBuilder
    var replayBar: some View {
        ReplayBar(
            totalPly: viewModel.gameState.plyCount,
            replayPly: viewModel.replayPly,
            isReplaying: viewModel.isReplaying,
            onGoToStart: { viewModel.enterReplay(ply: 0) },
            onStepBack: {
                let current = viewModel.replayPly ?? viewModel.gameState.plyCount
                viewModel.enterReplay(ply: current - 1)
            },
            onStepForward: {
                let current = viewModel.replayPly ?? viewModel.gameState.plyCount
                viewModel.enterReplay(ply: current + 1)
            },
            onGoToEnd: { viewModel.exitReplay() },
            onResume: { viewModel.exitReplay() }
        )
    }
}
