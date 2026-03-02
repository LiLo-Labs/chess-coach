import SwiftUI

struct GameImportView: View {
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(AppServices.self) private var appServices

    @State private var username = ""
    @State private var source: GameImportService.ImportSource = .lichess
    @State private var importService = GameImportService()
    @State private var fetchedGames: [ImportedGame] = []
    @State private var selectedGameIDs: Set<String> = []
    @State private var phase: ImportPhase = .input
    @State private var error: String?
    @State private var importedCount = 0
    @State private var analysisService: GameAnalysisService?
    @State private var importedGames: [ImportedGame] = []

    private enum ImportPhase {
        case input
        case review
        case done
    }

    var body: some View {
        Group {
            switch phase {
            case .input:
                inputPhase
            case .review:
                reviewPhase
            case .done:
                donePhase
            }
        }
        .navigationTitle("Import Games")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Phase 1: Input

    private var inputPhase: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if !subscriptionService.isPro {
                    ProGateBanner(feature: "Game import")
                        .padding(.horizontal, AppSpacing.screenPadding)
                }

                if subscriptionService.isPro {
                    VStack(spacing: AppSpacing.md) {
                        // Source picker
                        Picker("Source", selection: $source) {
                            ForEach(GameImportService.ImportSource.allCases, id: \.self) { src in
                                Text(src.rawValue).tag(src)
                            }
                        }
                        .pickerStyle(.segmented)

                        // Username field
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundStyle(AppColor.secondaryText)
                            TextField("Username", text: $username)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .padding(AppSpacing.md)
                        .background(AppColor.elevatedBackground, in: RoundedRectangle(cornerRadius: AppRadius.md))

                        // Hint
                        Text(source == .lichess
                             ? "Enter your Lichess username (e.g., DrNykterstein)"
                             : "Enter your Chess.com username (e.g., MagnusCarlsen)")
                            .font(.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    .padding(.horizontal, AppSpacing.screenPadding)

                    // Fetch button
                    Button {
                        Task { await fetchGames() }
                    } label: {
                        HStack {
                            if importService.isFetching {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(importService.isFetching ? "Fetching..." : "Fetch Games")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(AppSpacing.md)
                        .background(username.isEmpty ? AppColor.tertiaryText : AppColor.info, in: RoundedRectangle(cornerRadius: AppRadius.md))
                        .foregroundStyle(.white)
                    }
                    .disabled(username.isEmpty || importService.isFetching)
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.horizontal, AppSpacing.screenPadding)

                    if importService.isFetching {
                        ProgressView(value: importService.fetchProgress)
                            .tint(AppColor.info)
                            .padding(.horizontal, AppSpacing.screenPadding)
                    }

                    if let error {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(AppColor.error)
                            .padding(.horizontal, AppSpacing.screenPadding)
                    }
                }
            }
            .padding(.vertical, AppSpacing.lg)
        }
        .background(AppColor.background)
    }

    // MARK: - Phase 2: Review

    private var reviewPhase: some View {
        VStack(spacing: 0) {
            // Select/deselect toggle
            HStack {
                Text("\(selectedGameIDs.count) of \(fetchedGames.count) selected")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.secondaryText)
                Spacer()
                Button(selectedGameIDs.count == fetchedGames.count ? "Deselect All" : "Select All") {
                    if selectedGameIDs.count == fetchedGames.count {
                        selectedGameIDs.removeAll()
                    } else {
                        selectedGameIDs = Set(fetchedGames.map(\.id))
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColor.info)
            }
            .padding(.horizontal, AppSpacing.screenPadding)
            .padding(.vertical, AppSpacing.sm)

            // Game list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(fetchedGames) { game in
                        Button {
                            if selectedGameIDs.contains(game.id) {
                                selectedGameIDs.remove(game.id)
                            } else {
                                selectedGameIDs.insert(game.id)
                            }
                        } label: {
                            fetchedGameRow(game, selected: selectedGameIDs.contains(game.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Import button
            Button {
                importSelected()
            } label: {
                Text("Import \(selectedGameIDs.count) Game\(selectedGameIDs.count == 1 ? "" : "s")")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.md)
                    .background(selectedGameIDs.isEmpty ? AppColor.tertiaryText : AppColor.info, in: RoundedRectangle(cornerRadius: AppRadius.md))
                    .foregroundStyle(.white)
            }
            .disabled(selectedGameIDs.isEmpty)
            .buttonStyle(ScaleButtonStyle())
            .padding(AppSpacing.screenPadding)
        }
        .background(AppColor.background)
    }

    private func fetchedGameRow(_ game: ImportedGame, selected: Bool) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? AppColor.info : AppColor.tertiaryText)
                .font(.title3)

            // Outcome indicator
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
                    if let tc = game.timeClass {
                        Text(tc.capitalized)
                            .font(.caption2)
                            .foregroundStyle(AppColor.tertiaryText)
                    }
                }
            }

            Spacer()

            Text(game.datePlayed, style: .date)
                .font(.caption2)
                .foregroundStyle(AppColor.tertiaryText)
        }
        .padding(.horizontal, AppSpacing.screenPadding)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColor.cardBackground)
    }

    // MARK: - Phase 3: Done

    private var donePhase: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Success icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppColor.success)

                Text("Imported \(importedCount) game\(importedCount == 1 ? "" : "s")")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColor.primaryText)

                // Analysis progress
                if let analysisService, analysisService.isAnalyzing {
                    VStack(spacing: AppSpacing.sm) {
                        Text("Analyzing game \(analysisService.currentGameIndex) of \(analysisService.totalGames)...")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.secondaryText)
                        ProgressView(value: analysisService.analysisProgress)
                            .tint(AppColor.info)
                    }
                    .padding(.horizontal, AppSpacing.screenPadding)
                }

                NavigationLink {
                    ImportedGamesListView()
                } label: {
                    Text("View Games")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(AppSpacing.md)
                        .background(AppColor.info, in: RoundedRectangle(cornerRadius: AppRadius.md))
                        .foregroundStyle(.white)
                }
                .buttonStyle(ScaleButtonStyle())
                .padding(.horizontal, AppSpacing.screenPadding)
            }
            .padding(.vertical, AppSpacing.xxl)
        }
        .background(AppColor.background)
    }

    // MARK: - Actions

    private func fetchGames() async {
        error = nil
        do {
            let games = try await importService.fetchGames(username: username, source: source)
            fetchedGames = games
            selectedGameIDs = Set(games.map(\.id))
            phase = .review
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func importSelected() {
        let selected = fetchedGames.filter { selectedGameIDs.contains($0.id) }
        PersistenceService.shared.appendImportedGames(selected)
        importedCount = selected.count
        phase = .done

        // Start background analysis
        let allGames = PersistenceService.shared.loadImportedGames()
        importedGames = allGames
        let service = GameAnalysisService(stockfish: appServices.stockfish)
        analysisService = service
        Task {
            await service.analyzeGames(allGames)
        }
    }

    // MARK: - Helpers

    private func outcomeIcon(_ outcome: ImportedGame.Outcome) -> some View {
        Group {
            switch outcome {
            case .win:
                Image(systemName: "crown.fill")
                    .foregroundStyle(AppColor.gold)
            case .loss:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppColor.error)
            case .draw:
                Image(systemName: "equal.circle.fill")
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
        .font(.subheadline)
    }
}
