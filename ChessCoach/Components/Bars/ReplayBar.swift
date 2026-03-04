import SwiftUI

/// Move-navigation scrub bar with optional resume button.
struct ReplayBar: View {
    let totalPly: Int
    let replayPly: Int?
    let isReplaying: Bool

    let onGoToStart: () -> Void
    let onStepBack: () -> Void
    let onStepForward: () -> Void
    let onGoToEnd: () -> Void
    let onResume: () -> Void

    var body: some View {
        if totalPly > 0 {
            HStack(spacing: 4) {
                navButton(icon: "backward.end.fill", label: "Go to start", action: onGoToStart)
                    .disabled(isReplaying && replayPly == 0)

                navButton(icon: "chevron.left", label: "Step back", weight: .semibold, action: onStepBack)
                    .disabled(isReplaying && replayPly == 0)

                Spacer()

                if isReplaying {
                    Text("Move \(replayPly ?? 0) of \(totalPly)")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Ply \(totalPly)")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                navButton(icon: "chevron.right", label: "Step forward", weight: .semibold, action: onStepForward)
                    .disabled(!isReplaying)

                navButton(icon: "forward.end.fill", label: "Go to end", action: onGoToEnd)
                    .disabled(!isReplaying)

                if isReplaying {
                    Button(action: onResume) {
                        Text("Resume")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.green.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Resume")
                }
            }
            .foregroundStyle(.white.opacity(0.6))
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.screenPadding)
        }
    }

    private func navButton(icon: String, label: String, weight: Font.Weight = .regular, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(weight))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}
