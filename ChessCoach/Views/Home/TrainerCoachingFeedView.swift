import SwiftUI

/// Vertical per-move coaching feed shown during trainer games.
/// Each entry shows move pairs, friendly names, coaching text, and quality badge.
/// Tapping a row calls `onTapEntry` with the ply for replay.
struct TrainerCoachingFeedView: View {
    let entries: [TrainerCoachingEntry]
    let isLoading: Bool
    var onTapEntry: ((Int) -> Void)?
    var onRequestExplanation: ((TrainerCoachingEntry) -> Void)?

    /// Group consecutive white+black entries into move pairs.
    private var movePairs: [MovePair] {
        var pairs: [MovePair] = []
        var i = 0
        let sorted = entries.sorted { $0.ply < $1.ply }
        while i < sorted.count {
            let entry = sorted[i]
            if entry.isWhiteMove {
                let blackEntry = (i + 1 < sorted.count && !sorted[i + 1].isWhiteMove)
                    ? sorted[i + 1] : nil
                pairs.append(MovePair(white: entry, black: blackEntry))
                i += blackEntry != nil ? 2 : 1
            } else {
                // Black move without a preceding white move
                pairs.append(MovePair(white: nil, black: entry))
                i += 1
            }
        }
        return pairs.reversed() // newest first
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Loading indicator at top
                    if isLoading {
                        loadingRow
                            .id("loading")
                    }

                    // Feed rows (newest first)
                    ForEach(movePairs) { pair in
                        feedRow(pair)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .onChange(of: entries.count) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("loading", anchor: .top)
                }
            }
        }
    }

    // MARK: - Move Pair

    struct MovePair: Identifiable {
        let white: TrainerCoachingEntry?
        let black: TrainerCoachingEntry?

        var id: String {
            (white?.id.uuidString ?? "") + (black?.id.uuidString ?? "")
        }

        var moveNumber: Int { white?.moveNumber ?? black?.moveNumber ?? 0 }
        var latestPly: Int { black?.ply ?? white?.ply ?? 0 }

        /// The primary entry to display coaching for (prefer player move)
        var primaryEntry: TrainerCoachingEntry? {
            if let w = white, w.isPlayerMove { return w }
            if let b = black, b.isPlayerMove { return b }
            return white ?? black
        }
    }

    // MARK: - Feed Row

    private func feedRow(_ pair: MovePair) -> some View {
        let isNewest = pair.id == movePairs.first?.id

        return Button {
            onTapEntry?(pair.latestPly)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // Move header with friendly names + category badge
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // White's move
                    if let white = pair.white {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            Text(OpeningMove.friendlyName(from: white.moveSAN))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(moveColor(white))
                        }
                    }

                    // Black's move
                    if let black = pair.black {
                        if pair.white != nil {
                            Text("·")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color(white: 0.35))
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            Text(OpeningMove.friendlyName(from: black.moveSAN))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(moveColor(black))
                        }
                    }

                    Spacer(minLength: 0)

                    // Explain in detail sparkle button
                    if let primary = pair.primaryEntry {
                        if primary.isExplaining {
                            ProgressView().controlSize(.mini).tint(.purple)
                                .accessibilityLabel("Loading explanation")
                        } else if primary.explanation != nil {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(.purple)
                                .accessibilityLabel("Explanation available")
                        } else {
                            Button {
                                onRequestExplanation?(primary)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "sparkles")
                                        .font(.caption2)
                                    Text("Explain")
                                        .font(.caption2.weight(.medium))
                                }
                                .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Get detailed explanation")
                        }
                    }

                    // Category badge for primary entry
                    if let primary = pair.primaryEntry {
                        categoryBadge(primary)
                    }
                }

                // Algebraic notation (secondary)
                let algebraic = algebraicText(pair)
                Text(algebraic)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)

                // Coaching text — show LLM explanation if available, otherwise hardcoded
                if let primary = pair.primaryEntry {
                    if let explanation = primary.explanation {
                        Text(explanation)
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    } else {
                        Text(primary.coaching)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }

                // Opening indicator
                if let name = (pair.primaryEntry ?? pair.white ?? pair.black)?.openingName {
                    let entry = pair.primaryEntry ?? pair.white ?? pair.black
                    let inBook = entry?.isInBook ?? false
                    HStack(spacing: 3) {
                        Image(systemName: "book.fill")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text(inBook ? name : "Off book")
                            .font(.caption2)
                    }
                    .foregroundStyle(inBook ? .cyan.opacity(0.7) : AppColor.warning.opacity(0.7))
                    .accessibilityLabel(inBook ? "Opening: \(name)" : "Off book")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(white: isNewest ? 0.13 : 0.10))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.vertical, 2)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(feedRowAccessibilityText(for: pair))
        .accessibilityHint("Double tap to replay from this position")
        .id(pair.id)
    }

    // MARK: - Helpers

    private func feedRowAccessibilityText(for pair: MovePair) -> String {
        var parts: [String] = []
        let num = pair.moveNumber

        if let white = pair.white {
            let name = OpeningMove.friendlyName(from: white.moveSAN)
            parts.append("Move \(num), White: \(name)")
        }
        if let black = pair.black {
            let name = OpeningMove.friendlyName(from: black.moveSAN)
            parts.append("Black: \(name)")
        }

        if let primary = pair.primaryEntry {
            // Quality badge
            if let sc = primary.scoreCategory {
                parts.append(sc.displayName)
            } else {
                parts.append(primary.category.feedLabel)
            }

            // Coaching text
            if let explanation = primary.explanation {
                parts.append(explanation)
            } else {
                parts.append(primary.coaching)
            }
        }

        if let name = (pair.primaryEntry ?? pair.white ?? pair.black)?.openingName {
            let entry = pair.primaryEntry ?? pair.white ?? pair.black
            let inBook = entry?.isInBook ?? false
            parts.append(inBook ? "Opening: \(name)" : "Off book")
        }

        return parts.joined(separator: ". ")
    }

    private func moveColor(_ entry: TrainerCoachingEntry) -> Color {
        if entry.category == .mistake { return AppColor.error }
        if entry.category == .deviation { return .orange }
        if !entry.isPlayerMove { return Color(white: 0.65) }
        return .white
    }

    private func algebraicText(_ pair: MovePair) -> String {
        let num = pair.moveNumber
        if let w = pair.white, let b = pair.black {
            return "\(num). \(w.moveSAN) \(b.moveSAN)"
        } else if let w = pair.white {
            return "\(num). \(w.moveSAN)"
        } else if let b = pair.black {
            return "\(num)... \(b.moveSAN)"
        }
        return ""
    }

    private func categoryBadge(_ entry: TrainerCoachingEntry) -> some View {
        Group {
            if let sc = entry.scoreCategory {
                Text(sc.displayName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(categoryColor(sc))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(categoryColor(sc).opacity(0.15), in: Capsule())
            } else {
                Text(entry.category.feedLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(moveCategoryColor(entry.category))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(moveCategoryColor(entry.category).opacity(0.15), in: Capsule())
            }
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(AppColor.secondaryText)
            Text("Evaluating move...")
                .font(.caption)
                .foregroundStyle(AppColor.tertiaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Evaluating your move")
    }

    // MARK: - Colors

    private func categoryColor(_ sc: ScoreCategory) -> Color {
        switch sc {
        case .masterful: return AppColor.gold
        case .strong: return AppColor.success
        case .solid: return AppColor.info
        case .developing: return AppColor.warning
        case .needsWork: return AppColor.error
        }
    }

    private func moveCategoryColor(_ mc: MoveCategory) -> Color {
        switch mc {
        case .goodMove: return AppColor.success
        case .okayMove: return AppColor.info
        case .mistake: return AppColor.error
        case .deviation: return AppColor.warning
        case .opponentMove: return AppColor.secondaryText
        }
    }
}

// MARK: - MoveCategory Feed Label

extension MoveCategory {
    var feedLabel: String {
        switch self {
        case .goodMove: return "Good"
        case .okayMove: return "OK"
        case .mistake: return "Mistake"
        case .deviation: return "Deviation"
        case .opponentMove: return "Opponent"
        }
    }
}
