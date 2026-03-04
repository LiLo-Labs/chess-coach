import SwiftUI
import ChessKit

struct ImportedGameDetailView: View {
    let game: ImportedGame

    @State private var selectedPly: Int?
    @State private var boardState = GameState()

    private var playerMoves: [AnalyzedMove]? {
        guard let mistakes = game.mistakes else { return nil }
        return mistakes
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Header
                headerSection

                // Stats bar (if analyzed)
                if game.analysisComplete {
                    statsBar
                }

                // Board at selected position
                boardSection

                // Move list
                moveListSection
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.vertical, AppSpacing.md)
        }
        .background(AppColor.background)
        .navigationTitle(game.detectedOpening ?? "Game Detail")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { setupBoard() }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: AppSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let opening = game.detectedOpening {
                        Text(opening)
                            .font(.headline)
                            .foregroundStyle(AppColor.primaryText)
                    }
                    HStack(spacing: AppSpacing.sm) {
                        Text("vs \(game.opponentUsername)")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.secondaryText)
                        if let elo = game.opponentELO {
                            Text("(\(elo))")
                                .font(.caption)
                                .foregroundStyle(AppColor.tertiaryText)
                        }
                    }
                }
                Spacer()
                outcomeLabel
            }

            HStack(spacing: AppSpacing.md) {
                infoChip(icon: "person.fill", text: game.playerColor.capitalized)
                if let tc = game.timeClass {
                    infoChip(icon: "clock", text: tc.capitalized)
                }
                infoChip(icon: "number", text: "\(game.moveCount) moves")
                Text(game.datePlayed, style: .date)
                    .font(.caption)
                    .foregroundStyle(AppColor.tertiaryText)
            }
        }
        .padding(AppSpacing.cardPadding)
        .cardBackground(cornerRadius: AppRadius.lg)
    }

    private var outcomeLabel: some View {
        Group {
            switch game.outcome {
            case .win:
                PillBadge(text: "WIN", color: AppColor.gold)
            case .loss:
                PillBadge(text: "LOSS", color: AppColor.error)
            case .draw:
                PillBadge(text: "DRAW", color: AppColor.secondaryText)
            }
        }
    }

    private func infoChip(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(AppColor.secondaryText)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        HStack(spacing: AppSpacing.md) {
            if let cpLoss = game.averageCentipawnLoss {
                statItem(label: "Avg CPL", value: "\(Int(cpLoss))", color: cpLoss < 30 ? AppColor.success : cpLoss < 60 ? .orange : AppColor.error)
            }

            if let mistakes = game.mistakes {
                let mistakeCount = mistakes.filter { $0.classification == .mistake }.count
                let blunderCount = mistakes.filter { $0.classification == .blunder }.count
                let inaccuracyCount = mistakes.filter { $0.classification == .inaccuracy }.count

                statItem(label: "Inaccuracies", value: "\(inaccuracyCount)", color: .yellow)
                statItem(label: "Mistakes", value: "\(mistakeCount)", color: .orange)
                statItem(label: "Blunders", value: "\(blunderCount)", color: AppColor.error)
            }
        }
        .padding(AppSpacing.cardPadding)
        .cardBackground(cornerRadius: AppRadius.lg)
    }

    private func statItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(AppColor.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Board

    private var boardSection: some View {
        let perspective: PieceColor = game.playerColor == "white" ? .white : .black
        return GameBoardView(gameState: boardState, perspective: perspective, allowInteraction: false)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
            .allowsHitTesting(false)
    }

    // MARK: - Move List

    private var moveListSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Moves")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.primaryText)

            // Wrap flow layout of move pairs
            let moves = game.sanMoves
            let moveCount = (moves.count + 1) / 2

            LazyVGrid(columns: [
                GridItem(.fixed(30), alignment: .trailing),
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
            ], spacing: 4) {
                ForEach(0..<moveCount, id: \.self) { moveNum in
                    let whitePly = moveNum * 2
                    let blackPly = moveNum * 2 + 1

                    // Move number
                    Text("\(moveNum + 1).")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppColor.tertiaryText)

                    // White move
                    moveButton(ply: whitePly)

                    // Black move
                    if blackPly < moves.count {
                        moveButton(ply: blackPly)
                    } else {
                        Text("")
                    }
                }
            }
        }
        .padding(AppSpacing.cardPadding)
        .cardBackground(cornerRadius: AppRadius.lg)
    }

    private func moveButton(ply: Int) -> some View {
        let san = game.sanMoves[ply]
        let classification = moveClassification(at: ply)
        let isSelected = selectedPly == ply

        return Button {
            selectedPly = ply
            navigateToPosition(ply: ply)
        } label: {
            HStack(spacing: 3) {
                if let cls = classification, cls != .good {
                    Circle()
                        .fill(classificationColor(cls))
                        .frame(width: 6, height: 6)
                }
                Text(san)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(isSelected ? AppColor.info : AppColor.primaryText)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isSelected ? AppColor.info.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func setupBoard() {
        boardState = GameState()
        // Show opening position (first 6 moves)
        let movesToShow = min(6, game.sanMoves.count)
        for i in 0..<movesToShow {
            boardState.makeSANMove(game.sanMoves[i])
        }
    }

    private func navigateToPosition(ply: Int) {
        boardState = GameState()
        for i in 0...ply {
            if i < game.sanMoves.count {
                boardState.makeSANMove(game.sanMoves[i])
            }
        }
    }

    private func moveClassification(at ply: Int) -> AnalyzedMove.MoveClass? {
        guard let mistakes = game.mistakes else { return nil }
        return mistakes.first { $0.id == ply }?.classification
    }

    private func classificationColor(_ cls: AnalyzedMove.MoveClass) -> Color {
        switch cls {
        case .good: return AppColor.success
        case .inaccuracy: return .yellow
        case .mistake: return .orange
        case .blunder: return AppColor.error
        }
    }
}
