import SwiftUI

/// Shared move-pair row card used across GamePlay, Trainer, and Session coaching feeds.
/// Displays move header with friendly names, category badge, coaching text, and explain button.
struct FeedRowCard: View {
    let pair: FeedMovePair
    let isNewest: Bool
    var onTap: (() -> Void)?

    /// Explain button configuration
    var explainStyle: ExplainStyle = .textAndIcon

    /// Called when the user taps Explain (nil = button hidden)
    var onRequestExplanation: ((FeedEntry) -> Void)?

    enum ExplainStyle: Equatable {
        case textAndIcon      // "Explain" + sparkle icon (GamePlay, Trainer)
        case iconOnly         // sparkle icon only (Session)
        case locked           // gold locked sparkle (paywall gating)
        case hidden           // no explain button
    }

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                moveHeader
                algebraicNotation
                coachingText
                openingIndicator
            }
            .padding(.horizontal, AppSpacing.md + 2)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(Color(white: isNewest ? 0.13 : 0.10))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.vertical, AppSpacing.xxxs)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Double tap to replay from this position")
        .id(pair.id)
    }

    // MARK: - Move Header

    private var moveHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let white = pair.white {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(OpeningMove.friendlyName(from: white.moveSAN))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FeedColors.moveColor(white))
                }
            }

            if let black = pair.black {
                if pair.white != nil {
                    Text("\u{00B7}")
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
                        .foregroundStyle(FeedColors.moveColor(black))
                }
            }

            Spacer(minLength: 0)

            if let primary = pair.primaryEntry {
                explainButton(for: primary)
            }

            if let primary = pair.primaryEntry {
                if !primary.coaching.isEmpty {
                    CoachingTierBadge(isLLM: primary.isLLMCoaching)
                }
                categoryBadge(primary)
            }
        }
    }

    // MARK: - Explain Button

    @ViewBuilder
    private func explainButton(for entry: FeedEntry) -> some View {
        if entry.isExplaining {
            ProgressView().controlSize(.mini).tint(.purple)
                .accessibilityLabel("Loading explanation")
        } else if entry.explanation != nil {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(.purple)
                .accessibilityLabel("Explanation available")
        } else if explainStyle != .hidden, let onRequestExplanation {
            Button {
                onRequestExplanation(entry)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                    if explainStyle == .textAndIcon {
                        Text("Explain")
                            .font(.caption2.weight(.medium))
                    }
                }
                .foregroundStyle(explainStyleColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(explainStyle == .locked ? "Unlock detailed explanation" : "Get detailed explanation")
        }
    }

    private var explainStyleColor: some ShapeStyle {
        switch explainStyle {
        case .textAndIcon: return AnyShapeStyle(AppColor.info)
        case .iconOnly: return AnyShapeStyle(.tertiary)
        case .locked: return AnyShapeStyle(AppColor.gold.opacity(0.5))
        case .hidden: return AnyShapeStyle(.clear)
        }
    }

    // MARK: - Category Badge

    @ViewBuilder
    private func categoryBadge(_ entry: FeedEntry) -> some View {
        if let sc = entry.scoreCategory {
            Text(sc.displayName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(FeedColors.categoryColor(sc))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(FeedColors.categoryColor(sc).opacity(0.15), in: Capsule())
        } else {
            Text(entry.category.feedLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(FeedColors.moveCategoryColor(entry.category))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(FeedColors.moveCategoryColor(entry.category).opacity(0.15), in: Capsule())
        }
    }

    // MARK: - Algebraic Notation

    private var algebraicNotation: some View {
        Text(algebraicText)
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)
    }

    private var algebraicText: String {
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

    // MARK: - Coaching Text

    @ViewBuilder
    private var coachingText: some View {
        if let primary = pair.primaryEntry {
            if let explanation = primary.explanation {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(AppSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.sm - 2))
            } else {
                Text(primary.coaching)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    // MARK: - Opening Indicator

    @ViewBuilder
    private var openingIndicator: some View {
        if let entry = pair.primaryEntry ?? pair.white ?? pair.black,
           let name = entry.openingName {
            let inBook = entry.isInBook
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

    // MARK: - Accessibility

    private var accessibilityText: String {
        var parts: [String] = []
        let num = pair.moveNumber

        if let white = pair.white {
            parts.append("Move \(num), White: \(OpeningMove.friendlyName(from: white.moveSAN))")
        }
        if let black = pair.black {
            parts.append("Black: \(OpeningMove.friendlyName(from: black.moveSAN))")
        }
        if let primary = pair.primaryEntry {
            if let sc = primary.scoreCategory {
                parts.append(sc.displayName)
            } else {
                parts.append(primary.category.feedLabel)
            }
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
}

// MARK: - Loading Row

struct FeedLoadingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(AppColor.secondaryText)
            Text("Evaluating move...")
                .font(.caption)
                .foregroundStyle(AppColor.tertiaryText)
        }
        .padding(.horizontal, AppSpacing.md + 2)
        .padding(.vertical, AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Evaluating your move")
    }
}
