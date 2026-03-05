import SwiftUI
import ChessKit

/// Shows both sides' detected openings during play.
/// Layout: "You: Italian Game" left, separator, "Opp: Two Knights" right.
struct OpeningIndicatorBanner: View {
    let whiteOpening: String?
    let blackOpening: String?
    let playerColor: PieceColor

    private var isVisible: Bool {
        whiteOpening != nil || blackOpening != nil
    }

    private var youLabel: String? {
        playerColor == .white ? whiteOpening : blackOpening
    }

    private var oppLabel: String? {
        playerColor == .white ? blackOpening : whiteOpening
    }

    private var youDotColor: Color {
        playerColor == .white ? .white : Color(white: 0.3)
    }

    private var oppDotColor: Color {
        playerColor == .white ? Color(white: 0.3) : .white
    }

    var body: some View {
        if isVisible {
            HStack(spacing: 0) {
                if let youLabel {
                    sideView(dot: youDotColor, label: "You", name: youLabel)
                }

                if youLabel != nil && oppLabel != nil {
                    Text("|")
                        .font(.caption2)
                        .foregroundStyle(AppColor.tertiaryText)
                        .padding(.horizontal, 6)
                }

                if let oppLabel {
                    sideView(dot: oppDotColor, label: "Opp", name: oppLabel)
                }

                Spacer()
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.vertical, AppSpacing.xxs)
            .background(AppColor.elevatedBackground)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityDescription)
        }
    }

    private func sideView(dot: Color, label: String, name: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
            Text("\(label):")
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppColor.tertiaryText)
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppColor.secondaryText)
                .lineLimit(1)
        }
    }

    private var accessibilityDescription: String {
        var parts: [String] = []
        if let youLabel { parts.append("You: \(youLabel)") }
        if let oppLabel { parts.append("Opponent: \(oppLabel)") }
        return parts.joined(separator: ". ")
    }
}
