import SwiftUI

struct OpeningCard: View {
    let opening: Opening
    private let progress: OpeningProgress

    init(opening: Opening) {
        self.opening = opening
        self.progress = PersistenceService.shared.loadProgress(forOpening: opening.id)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Color indicator
            Circle()
                .fill(opening.color == .white ? Color.white : Color(white: 0.35))
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(opening.name)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(opening.description)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()

            // Progress indicator
            VStack(alignment: .trailing, spacing: 2) {
                if progress.gamesPlayed > 0 {
                    Text("\(Int(progress.accuracy * 100))%")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("\(progress.gamesPlayed) played")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.35))
                } else {
                    Text("New")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 12))
    }
}
