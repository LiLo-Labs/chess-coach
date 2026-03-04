import SwiftUI

/// Shared deviation/off-book/discovery banner for session and gameplay coaching feeds.
enum DeviationBanner {

    // MARK: - User Deviation

    struct UserDeviation: View {
        let expected: OpeningMove
        var isUnguided: Bool = false

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(isUnguided
                     ? "Recommended move was \(expected.friendlyName)"
                     : "The plan plays \(expected.friendlyName) here")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)

                if !expected.explanation.isEmpty {
                    Text(expected.explanation)
                        .font(.caption2)
                        .foregroundStyle(.primary.opacity(0.6))
                }
            }
            .padding(AppSpacing.md - 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.sm))
        }
    }

    // MARK: - Opponent Deviation

    struct OpponentDeviation: View {
        let expected: OpeningMove
        let playedSAN: String
        var bestMoveDescription: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("Opponent played \(OpeningMove.friendlyName(from: playedSAN)) instead of \(expected.friendlyName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.mint)

                if let bestMove = bestMoveDescription {
                    Text("Try \(bestMove)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.mint.opacity(0.8))
                }
            }
            .padding(AppSpacing.md - 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.sm))
        }
    }

    // MARK: - Off Book

    struct OffBook: View {
        var bestMoveDescription: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("On your own \u{2014} play your plan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)

                if let bestMove = bestMoveDescription {
                    Text("Suggested: \(bestMove)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.cyan.opacity(0.8))
                }
            }
            .padding(AppSpacing.md - 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.sm))
        }
    }

    // MARK: - Discovery

    struct Discovery: View {
        let optionCount: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(optionCount) good options here \u{2014} can you find one?")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.mint)
            }
            .padding(AppSpacing.md - 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.sm))
        }
    }
}
