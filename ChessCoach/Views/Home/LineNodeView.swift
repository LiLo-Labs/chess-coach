import SwiftUI

struct LineNodeView: View {
    let line: OpeningLine
    let lineProgress: LineProgress
    let isUnlocked: Bool
    let depth: Int

    @AppStorage("colorblind_mode") private var colorblindMode = false

    var body: some View {
        HStack(spacing: 12) {
            // Indentation
            if depth > 0 {
                HStack(spacing: 0) {
                    ForEach(0..<depth, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 1)
                            .padding(.horizontal, 9)
                    }
                }
            }

            // Branch indicator
            if depth > 0 {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.25))
            }

            // Lock / phase indicator
            if !isUnlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange.opacity(0.6))
            } else {
                phaseDot
            }

            // Name and info
            VStack(alignment: .leading, spacing: 3) {
                Text(line.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isUnlocked ? .white : .white.opacity(0.45))

                // Line preview (first 4-5 moves)
                Text(linePreview)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(isUnlocked ? 0.4 : 0.2))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(line.moves.count) moves")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))

                    if lineProgress.gamesPlayed > 0 {
                        Text("\(lineProgress.gamesPlayed) played")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }

            Spacer()

            // Right side: play button or progress or lock info
            if isUnlocked {
                if lineProgress.gamesPlayed > 0 {
                    HStack(spacing: 10) {
                        VStack(alignment: .trailing, spacing: 2) {
                            accuracyRing
                            Text(lineProgress.currentPhase.displayName)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        // Play chevron — makes it clear this is tappable
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                    }
                } else {
                    // New line — prominent "Start" CTA
                    HStack(spacing: 6) {
                        Text("Start")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.green.opacity(0.12), in: Capsule())
                }
            } else {
                // Locked — clearer explanation
                lockBadge
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(isUnlocked ? 1.0 : 0.6)
    }

    // MARK: - Lock badge

    private var lockBadge: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                Text("Locked")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.orange.opacity(0.7))

            Text("Complete parent line first")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Line preview

    private var linePreview: String {
        let previewMoves = Array(line.moves.prefix(5))
        var parts: [String] = []
        for (i, move) in previewMoves.enumerated() {
            if i % 2 == 0 {
                parts.append("\(i / 2 + 1).\(move.san)")
            } else {
                parts.append(move.san)
            }
        }
        let suffix = line.moves.count > 5 ? " ..." : ""
        return parts.joined(separator: " ") + suffix
    }

    // MARK: - Phase indicator

    private var phaseDot: some View {
        Group {
            if colorblindMode {
                Image(systemName: phaseShape)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(phaseColor)
            } else {
                Circle()
                    .fill(phaseColor)
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var phaseShape: String {
        switch lineProgress.currentPhase {
        case .learningMainLine: return "circle.fill"
        case .naturalDeviations: return "triangle.fill"
        case .widerVariations: return "square.fill"
        case .freePlay: return "star.fill"
        }
    }

    private var phaseColor: Color {
        switch lineProgress.currentPhase {
        case .learningMainLine: return .blue
        case .naturalDeviations: return .green
        case .widerVariations: return .orange
        case .freePlay: return .purple
        }
    }

    private var accuracyRing: some View {
        let threshold = lineProgress.currentPhase.promotionThreshold ?? 100
        let fillFraction = threshold > 0 ? min(lineProgress.compositeScore / threshold, 1.0) : 1.0

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 2)
                .frame(width: 28, height: 28)

            Circle()
                .trim(from: 0, to: fillFraction)
                .stroke(phaseColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(-90))

            Text("\(Int(lineProgress.accuracy * 100))")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
