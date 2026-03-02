import SwiftUI

struct ImportedGamesListView: View {
    @State private var games: [ImportedGame] = []
    @State private var filter: OutcomeFilter = .all

    private enum OutcomeFilter: String, CaseIterable {
        case all = "All"
        case wins = "Wins"
        case losses = "Losses"
        case draws = "Draws"
    }

    private var filteredGames: [ImportedGame] {
        switch filter {
        case .all: return games
        case .wins: return games.filter { $0.outcome == .win }
        case .losses: return games.filter { $0.outcome == .loss }
        case .draws: return games.filter { $0.outcome == .draw }
        }
    }

    private var groupedGames: [(String, [ImportedGame])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let grouped = Dictionary(grouping: filteredGames) { formatter.string(from: $0.datePlayed) }
        return grouped.sorted { $0.value.first!.datePlayed > $1.value.first!.datePlayed }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(OutcomeFilter.allCases, id: \.self) { f in
                        Button {
                            filter = f
                        } label: {
                            Text(f.rawValue)
                                .font(.subheadline.weight(filter == f ? .semibold : .regular))
                                .foregroundStyle(filter == f ? .white : AppColor.primaryText)
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.vertical, AppSpacing.xs)
                                .background(filter == f ? AppColor.info : AppColor.elevatedBackground, in: Capsule())
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.horizontal, AppSpacing.screenPadding)
                .padding(.vertical, AppSpacing.sm)
            }

            if filteredGames.isEmpty {
                ContentUnavailableView(
                    "No Games",
                    systemImage: "tray",
                    description: Text(games.isEmpty ? "Import games to see them here" : "No games match this filter")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groupedGames, id: \.0) { month, monthGames in
                            Section {
                                ForEach(monthGames) { game in
                                    NavigationLink {
                                        ImportedGameDetailView(game: game)
                                    } label: {
                                        gameRow(game)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                HStack {
                                    Text(month)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppColor.secondaryText)
                                    Spacer()
                                }
                                .padding(.horizontal, AppSpacing.screenPadding)
                                .padding(.vertical, AppSpacing.xs)
                                .background(AppColor.background)
                            }
                        }
                    }
                }
            }
        }
        .background(AppColor.background)
        .navigationTitle("Imported Games")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            games = PersistenceService.shared.loadImportedGames()
        }
    }

    private func gameRow(_ game: ImportedGame) -> some View {
        HStack(spacing: AppSpacing.sm) {
            // Outcome accent strip
            RoundedRectangle(cornerRadius: 2)
                .fill(outcomeColor(game.outcome))
                .frame(width: 3, height: 28)

            // Outcome icon
            outcomeIcon(game.outcome)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppSpacing.xs) {
                    Text("vs \(game.opponentUsername)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColor.primaryText)
                    if let elo = game.opponentELO {
                        Text("(\(elo))")
                            .font(.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
                HStack(spacing: AppSpacing.xs) {
                    if let opening = game.detectedOpening {
                        Text(opening)
                            .font(.caption)
                            .foregroundStyle(AppColor.secondaryText)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Analysis status
            if game.analysisComplete {
                if let cpLoss = game.averageCentipawnLoss {
                    Text("\(Int(cpLoss)) acpl")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(cpLoss < 30 ? AppColor.success : cpLoss < 60 ? .orange : AppColor.error)
                }
            } else {
                Image(systemName: "hourglass")
                    .font(.caption)
                    .foregroundStyle(AppColor.tertiaryText)
            }

            Text(game.datePlayed, style: .date)
                .font(.caption2)
                .foregroundStyle(AppColor.tertiaryText)
        }
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColor.cardBackground)
    }

    private func outcomeIcon(_ outcome: ImportedGame.Outcome) -> some View {
        Group {
            switch outcome {
            case .win:
                Image(systemName: "crown.fill").foregroundStyle(AppColor.gold)
            case .loss:
                Image(systemName: "xmark.circle.fill").foregroundStyle(AppColor.error)
            case .draw:
                Image(systemName: "equal.circle.fill").foregroundStyle(AppColor.secondaryText)
            }
        }
        .font(.subheadline)
    }

    private func outcomeColor(_ outcome: ImportedGame.Outcome) -> Color {
        switch outcome {
        case .win: return AppColor.gold
        case .loss: return AppColor.error
        case .draw: return AppColor.secondaryText
        }
    }
}
