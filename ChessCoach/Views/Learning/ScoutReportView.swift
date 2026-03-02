import SwiftUI
import ChessKit

/// Layer 4 sub-milestone: Read scouting cards for all opponent responses.
/// Card slideshow showing each opponent response with board, name, frequency, and plan adjustment.
struct ScoutReportView: View {
    let opening: Opening
    let onComplete: () -> Void

    @State private var currentIndex = 0
    @State private var allRead = false
    @State private var readCards: Set<Int> = []
    @Environment(\.dismiss) private var dismiss

    private var responses: [OpponentResponse] {
        opening.opponentResponses?.responses ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .foregroundStyle(AppColor.secondaryText)
                }

                Spacer()

                VStack(spacing: AppSpacing.xxxs) {
                    Text("Scout Report")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColor.primaryText)
                    Text("\(readCards.count)/\(responses.count) reviewed")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppColor.secondaryText)
                }

                Spacer()

                // Card counter
                if !responses.isEmpty {
                    Text("\(currentIndex + 1)/\(responses.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppColor.tertiaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppColor.tertiaryText.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.vertical, AppSpacing.md)

            if responses.isEmpty {
                emptyState
            } else {
                // Card
                TabView(selection: $currentIndex) {
                    ForEach(Array(responses.enumerated()), id: \.element.id) { index, response in
                        scoutCard(response: response, index: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .onChange(of: currentIndex) { _, newIndex in
                    readCards.insert(newIndex)
                    if readCards.count >= responses.count {
                        allRead = true
                    }
                }
                .onAppear { readCards.insert(0) }
            }

            // Bottom button
            if allRead {
                Button {
                    onComplete()
                    dismiss()
                } label: {
                    Text("Ready for Battle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppColor.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColor.layer(.handleVariety), in: Capsule())
                }
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.bottom, AppSpacing.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(AppColor.background)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.4), value: allRead)
    }

    // MARK: - Scout Card

    private func scoutCard(response: OpponentResponse, index: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                // Board showing position after response
                let state = boardState(for: response)
                let perspective: PieceColor = opening.color == .white ? .white : .black

                GameBoardView(gameState: state, perspective: perspective, allowInteraction: false)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    .allowsHitTesting(false)

                // Response header
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                            Text(response.name)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(AppColor.primaryText)

                            Text(response.eco)
                                .font(.caption.monospaced())
                                .foregroundStyle(AppColor.tertiaryText)
                        }

                        Spacer()

                        // Frequency badge
                        frequencyBadge(response.frequency)
                    }

                    // The move
                    HStack(spacing: AppSpacing.xs) {
                        Text("They play:")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.secondaryText)
                        Text(response.move.san)
                            .font(.subheadline.weight(.bold).monospaced())
                            .foregroundStyle(AppColor.layer(.handleVariety))
                    }
                }

                // Description
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("What to Expect")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.tertiaryText)
                        .textCase(.uppercase)
                        .tracking(0.4)

                    Text(response.description)
                        .font(.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Plan adjustment
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Adjust Your Plan")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.tertiaryText)
                        .textCase(.uppercase)
                        .tracking(0.4)

                    Text(response.planAdjustment)
                        .font(.subheadline)
                        .foregroundStyle(AppColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(AppSpacing.cardPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColor.layer(.handleVariety).opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.sm))
                }
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.bottom, AppSpacing.xxxl)
        }
    }

    private func frequencyBadge(_ frequency: Double) -> some View {
        let pct = Int(frequency * 100)
        let label: String
        let color: Color

        if pct >= 40 {
            label = "Very Common (\(pct)%)"
            color = AppColor.success
        } else if pct >= 20 {
            label = "Common (\(pct)%)"
            color = AppColor.info
        } else if pct >= 5 {
            label = "Uncommon (\(pct)%)"
            color = AppColor.warning
        } else {
            label = "Rare (\(pct)%)"
            color = AppColor.tertiaryText
        }

        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func boardState(for response: OpponentResponse) -> GameState {
        let state = GameState()
        if let afterMoves = opening.opponentResponses?.afterMoves {
            for uci in afterMoves {
                state.makeMoveUCI(uci)
            }
        }
        state.makeMoveUCI(response.move.uci)
        return state
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Image(systemName: "binoculars.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppColor.tertiaryText)
            Text("No opponent responses catalogued yet.")
                .font(.subheadline)
                .foregroundStyle(AppColor.secondaryText)
            Button {
                onComplete()
                dismiss()
            } label: {
                Text("Continue")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppColor.primaryText)
                    .padding(.horizontal, AppSpacing.xxl)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColor.layer(.handleVariety), in: Capsule())
            }
            Spacer()
        }
    }
}
