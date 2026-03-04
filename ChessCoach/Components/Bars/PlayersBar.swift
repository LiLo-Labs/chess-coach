import SwiftUI

/// Player info display bar for session-based gameplay.
struct PlayersBar: View {
    // MARK: - Opponent

    let opponentName: String
    let opponentELO: Int
    let opponentDotColor: Color

    // MARK: - User

    let userName: String
    let userELO: Int
    let userDotColor: Color

    // MARK: - State

    let isThinking: Bool
    let showYourMove: Bool

    var body: some View {
        HStack(spacing: 0) {
            opponentSide
            Spacer()
            userSide
        }
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.vertical, 5)
        .background(AppColor.elevatedBackground)
    }

    // MARK: - Subviews

    private var opponentSide: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(opponentDotColor)
                .frame(width: 8, height: 8)
            Text(opponentName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("\(opponentELO)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            if isThinking {
                ProgressView().controlSize(.mini).tint(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(opponentName), rated \(opponentELO)\(isThinking ? ", thinking" : "")")
    }

    private var userSide: some View {
        HStack(spacing: 6) {
            if showYourMove {
                Text("YOUR MOVE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.3)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.15), in: Capsule())
                    .phaseAnimator([false, true]) { content, phase in
                        content.opacity(phase ? 1.0 : 0.6)
                    } animation: { _ in .easeInOut(duration: 0.8) }
            }
            Text("\(userELO)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(userName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            Circle()
                .fill(userDotColor)
                .frame(width: 8, height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(userName), rated \(userELO)\(showYourMove ? ", your move" : "")")
    }
}
