import SwiftUI

/// Coaching feed for GamePlayView — uses Trainer's superior pattern:
/// visible Explain button, category badges, move-pair grouping.
extension GamePlayView {

    var coachingFeed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Live status at top (session banners + action buttons)
                    if viewModel.mode.isSession {
                        liveStatus
                            .id("live")
                    }

                    // Loading indicator
                    if viewModel.isEvaluating || viewModel.isCoachingLoading {
                        loadingRow
                            .id("loading")
                    }

                    // Feed rows (newest first) — move-pair grouped
                    ForEach(movePairs) { pair in
                        feedRow(pair)
                    }

                    // Empty state
                    if viewModel.feedEntries.isEmpty && !viewModel.isEvaluating && !viewModel.isCoachingLoading {
                        Text("Make your move on the board")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .background(AppColor.background)
            .onChange(of: viewModel.feedEntries.count) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(viewModel.mode.isSession ? "live" : "loading", anchor: .top)
                }
            }
        }
    }

    // MARK: - Move Pairs

    struct MovePair: Identifiable {
        let white: CoachingEntry?
        let black: CoachingEntry?

        var id: String {
            "\(white?.id ?? 0)-\(black?.id ?? 0)"
        }

        var moveNumber: Int { white?.moveNumber ?? black?.moveNumber ?? 0 }
        var latestPly: Int { black?.ply ?? white?.ply ?? 0 }

        var primaryEntry: CoachingEntry? {
            if let w = white, w.isPlayerMove { return w }
            if let b = black, b.isPlayerMove { return b }
            return white ?? black
        }
    }

    private var movePairs: [MovePair] {
        var pairs: [MovePair] = []
        var i = 0
        let sorted = viewModel.feedEntries.sorted { $0.ply < $1.ply }
        while i < sorted.count {
            let entry = sorted[i]
            if entry.isWhiteMove {
                let blackEntry = (i + 1 < sorted.count && !sorted[i + 1].isWhiteMove)
                    ? sorted[i + 1] : nil
                pairs.append(MovePair(white: entry, black: blackEntry))
                i += blackEntry != nil ? 2 : 1
            } else {
                pairs.append(MovePair(white: nil, black: entry))
                i += 1
            }
        }
        return pairs.reversed() // newest first
    }

    // MARK: - Feed Row

    private func feedRow(_ pair: MovePair) -> some View {
        let isNewest = pair.id == movePairs.first?.id

        return Button {
            viewModel.enterReplay(ply: pair.latestPly)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // Move header with friendly names + category badge
                HStack(alignment: .firstTextBaseline, spacing: 6) {
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

                    // Explain button — visible text label (Trainer's superior pattern)
                    if let primary = pair.primaryEntry {
                        explainButton(for: primary)
                    }

                    // Category badge
                    if let primary = pair.primaryEntry {
                        categoryBadge(primary)
                    }
                }

                // Algebraic notation
                Text(algebraicText(pair))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)

                // Coaching text — LLM explanation if available, otherwise hardcoded
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

    // MARK: - Explain Button

    @ViewBuilder
    private func explainButton(for entry: CoachingEntry) -> some View {
        if entry.isExplaining {
            ProgressView().controlSize(.mini).tint(.purple)
                .accessibilityLabel("Loading explanation")
        } else if entry.explanation != nil {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(.purple)
                .accessibilityLabel("Explanation available")
        } else {
            Button {
                viewModel.requestExplanation(for: entry)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                    Text("Explain")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(AppColor.info)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Get detailed explanation")
        }
    }

    // MARK: - Live Status (Session)

    @ViewBuilder
    private var liveStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Variation switch
            if let variation = viewModel.suggestedVariation {
                variationBanner(variation: variation)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            // Deviation banners
            if case let .userDeviated(expected, _) = viewModel.bookStatus {
                deviationBanner(expected: expected)
                    .padding(.horizontal, 16)
            } else if case let .opponentDeviated(expected, playedSAN, _) = viewModel.bookStatus {
                opponentDeviationBanner(expected: expected, played: playedSAN)
                    .padding(.horizontal, 16)
            } else if case .offBook = viewModel.bookStatus {
                offBookBanner
                    .padding(.horizontal, 16)
            } else if viewModel.discoveryMode {
                discoveryBanner
                    .padding(.horizontal, 16)
            }

            // Action buttons
            sessionActionButtons
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.bookStatus)
    }

    // MARK: - Session Action Buttons

    @ViewBuilder
    private var sessionActionButtons: some View {
        HStack(spacing: 8) {
            if case .userDeviated = viewModel.bookStatus {
                Button(action: { viewModel.retryLastMove() }) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.orange)
                .controlSize(.small)

                Button(action: { Task { await viewModel.continueAfterDeviation() } }) {
                    Text("Continue")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.secondary)
                .controlSize(.small)
            }

            if case .opponentDeviated = viewModel.bookStatus {
                Button(action: { Task { await viewModel.restartSession() } }) {
                    Label("Retry", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.mint)
                .controlSize(.small)
            }

            if case .offBook = viewModel.bookStatus {
                Button(action: { Task { await viewModel.restartSession() } }) {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.cyan)
                .controlSize(.small)
            }

            Spacer()
        }
    }

    // MARK: - Banners

    private func deviationBanner(expected: OpeningMove) -> some View {
        let isUnguided = viewModel.mode.sessionMode == .unguided

        return VStack(alignment: .leading, spacing: 4) {
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
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func opponentDeviationBanner(expected: OpeningMove, played: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Opponent played \(OpeningMove.friendlyName(from: played)) instead of \(expected.friendlyName)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.mint)

            if let bestMove = viewModel.bestResponseDescription {
                Text("Try \(bestMove)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.mint.opacity(0.8))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var offBookBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("On your own — play your plan")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.cyan)

            if let bestMove = viewModel.bestResponseDescription {
                Text("Suggested: \(bestMove)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.cyan.opacity(0.8))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var discoveryBanner: some View {
        VStack(alignment: .leading, spacing: 2) {
            let count = viewModel.branchPointOptions?.count ?? 2
            Text("\(count) good options here — can you find one?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.mint)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func variationBanner(variation: OpeningLine) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption2)
                .foregroundStyle(.teal)
            Text("You played into the \(variation.name)")
                .font(.caption)
                .foregroundStyle(.teal)
            Spacer()
            Button {
                viewModel.switchToLine(variation)
            } label: {
                Text("Switch")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.teal)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .buttonBackground(.teal.opacity(0.12))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func moveColor(_ entry: CoachingEntry) -> Color {
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

    @ViewBuilder
    private func categoryBadge(_ entry: CoachingEntry) -> some View {
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

    private func feedRowAccessibilityText(for pair: MovePair) -> String {
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
