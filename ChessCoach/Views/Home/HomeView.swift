import SwiftUI

struct HomeView: View {
    private let database = OpeningDatabase.shared
    @State private var selectedOpening: Opening?
    @State private var showResumePrompt = false
    @State private var resumeOpening: Opening?
    @State private var resumeLineID: String?
    @State private var streak = PersistenceService.shared.loadStreak()
    @State private var dueReviewCount = 0
    @State private var allMastery: [String: OpeningMastery] = [:]
    @State private var searchText = ""
    @State private var selectedColor: Opening.PlayerColor = .white
    @State private var showLockedOpening = false
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(AppSettings.self) private var settings
    @Environment(AppServices.self) private var appServices

    // MARK: - Computed

    private var inProgressOpenings: [Opening] {
        let allOpenings = database.openings(forColor: .white) + database.openings(forColor: .black)
        return allOpenings
            .filter { (allMastery[$0.id]?.sessionsPlayed ?? 0) > 0 }
            .sorted { (allMastery[$0.id]?.lastPlayed ?? .distantPast) > (allMastery[$1.id]?.lastPlayed ?? .distantPast) }
    }

    private func filteredOpenings(forColor color: Opening.PlayerColor) -> [Opening] {
        let all = database.openings(forColor: color)
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func groupedOpenings(forColor color: Opening.PlayerColor) -> [(title: String, openings: [Opening])] {
        let openings = filteredOpenings(forColor: color)
        let groups: [(String, ClosedRange<Int>)] = [
            ("Beginner", 1...1),
            ("Intermediate", 2...2),
            ("Advanced", 3...5)
        ]
        return groups.compactMap { title, range in
            let matching = openings.filter { range.contains($0.difficulty) }
            return matching.isEmpty ? nil : (title, matching)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // Resume session
                if showResumePrompt, let opening = resumeOpening {
                    resumeSection(opening: opening)
                }

                // Stats
                statsSection

                // Quick actions: modes
                modesSection

                // Continue Learning
                if !inProgressOpenings.isEmpty {
                    continueSection
                }

                // Review
                if dueReviewCount > 0 {
                    reviewSection
                }

                // Color picker
                pickerSection

                // Openings by difficulty
                let groups = groupedOpenings(forColor: selectedColor)
                ForEach(groups, id: \.title) { title, openings in
                    Section(title) {
                        ForEach(openings) { opening in
                            let accessible = subscriptionService.isOpeningAccessible(opening.id)
                            if accessible {
                                NavigationLink(value: opening) {
                                    openingRow(opening: opening, locked: false)
                                }
                                .listRowBackground(AppColor.cardBackground)
                            } else {
                                Button {
                                    showLockedOpening = true
                                } label: {
                                    openingRow(opening: opening, locked: true)
                                }
                                .listRowBackground(AppColor.cardBackground)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .background(AppColor.background)
            .scrollContentBackground(.hidden)
            .navigationTitle("ChessCoach")
            .preferredColorScheme(.dark)
            .searchable(text: $searchText, prompt: "Search game plans")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    FeedbackToolbarButton(screen: "Home")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: Opening.self) { opening in
                OpeningDetailView(opening: opening)
            }
            .onAppear {
                refreshData()
                checkForSavedSession()
            }
            .fullScreenCover(item: $selectedOpening) { opening in
                SessionView(opening: opening, lineID: resumeLineID, isPro: subscriptionService.isPro, stockfish: appServices.stockfish, llmService: appServices.llmService)
                    .environment(subscriptionService)
            }
            .sheet(isPresented: $showLockedOpening) {
                ProUpgradeView()
            }
        }
    }

    // MARK: - Data

    private func refreshData() {
        allMastery = PersistenceService.shared.loadAllMastery()
        dueReviewCount = SpacedRepScheduler().dueItems().count
        var s = PersistenceService.shared.loadStreak()
        s.applyStreakFreezeIfNeeded()
        PersistenceService.shared.saveStreak(s)
        streak = s
    }

    private func checkForSavedSession() {
        guard let info = SessionViewModel.savedSessionInfo() else { return }
        let allOpenings = database.openings(forColor: .white) + database.openings(forColor: .black)
        if let opening = allOpenings.first(where: { $0.id == info.openingID }) {
            resumeOpening = opening
            resumeLineID = info.lineID
            showResumePrompt = true
        }
    }

    // MARK: - Resume

    private func resumeSection(opening: Opening) -> some View {
        Section {
            Button {
                selectedOpening = opening
                showResumePrompt = false
            } label: {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppColor.success)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Resume Session")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColor.primaryText)
                        Text(opening.name)
                            .font(.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }

                    Spacer()
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    SessionViewModel.clearSavedSession()
                    showResumePrompt = false
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                }
            }
        }
        .listRowBackground(AppColor.cardBackground)
    }

    // MARK: - Stats

    private var statsSection: some View {
        Section {
            HStack {
                Label {
                    Text("\(streak.currentStreak)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppColor.primaryText)
                    + Text(" day streak")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.secondaryText)
                } icon: {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(streak.currentStreak > 0 ? .orange : AppColor.tertiaryText)
                }

                HelpButton(topic: .streak)

                Spacer()

                let goalTarget = settings.dailyGoalTarget
                let goalCompleted = settings.dailyGoalCompleted

                Text("\(goalCompleted)/\(goalTarget)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(AppColor.secondaryText)

                ProgressRing(
                    progress: goalTarget > 0 ? Double(goalCompleted) / Double(goalTarget) : 0,
                    color: goalCompleted >= goalTarget ? AppColor.success : AppColor.info,
                    lineWidth: 2.5,
                    size: 22
                )
            }
        }
        .listRowBackground(AppColor.cardBackground)
    }

    // MARK: - Continue Learning

    private var continueSection: some View {
        Section("Keep Practicing") {
            ForEach(inProgressOpenings.prefix(3)) { opening in
                NavigationLink(value: opening) {
                    openingRow(opening: opening)
                }
            }
        }
        .listRowBackground(AppColor.cardBackground)
    }

    // MARK: - Review

    private var reviewSection: some View {
        Section {
            NavigationLink {
                QuickReviewView()
            } label: {
                Label {
                    HStack {
                        Text("Review Due")
                            .foregroundStyle(AppColor.primaryText)
                        Spacer()
                        Text("\(dueReviewCount)")
                            .foregroundStyle(AppColor.info)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                } icon: {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(AppColor.info)
                }
            }
        }
        .listRowBackground(AppColor.cardBackground)
    }

    // MARK: - Modes

    private var modesSection: some View {
        Section {
            HStack(spacing: AppSpacing.md) {
                modeCard(
                    icon: "puzzlepiece.fill",
                    title: "Puzzles",
                    subtitle: "Tactics training",
                    color: .orange,
                    destination: { PuzzleModeView() }
                )

                modeCard(
                    icon: "figure.fencing",
                    title: "Trainer",
                    subtitle: "Play a full game",
                    color: .cyan,
                    destination: { TrainerModeView() }
                )
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
        .listRowBackground(Color.clear)
    }

    private func modeCard<Destination: View>(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.primaryText)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(AppColor.tertiaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Picker

    private var pickerSection: some View {
        Section {
            Picker("Color", selection: $selectedColor.animation(.easeInOut(duration: 0.15))) {
                Text("White").tag(Opening.PlayerColor.white)
                Text("Black").tag(Opening.PlayerColor.black)
            }
            .pickerStyle(.segmented)
        }
        .listRowBackground(AppColor.cardBackground)
    }

    // MARK: - Opening Row

    private func openingRow(opening: Opening, locked: Bool = false) -> some View {
        let mastery = allMastery[opening.id]
        let sessions = mastery?.sessionsPlayed ?? 0

        return HStack(spacing: AppSpacing.md) {
            // Color indicator
            Circle()
                .fill(opening.color == .white ? Color.white : Color(white: 0.3))
                .frame(width: 12, height: 12)
                .overlay {
                    if opening.color == .white {
                        Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(opening.name)
                    .font(.body)
                    .foregroundStyle(locked ? AppColor.tertiaryText : AppColor.primaryText)

                if locked {
                    Text(opening.description)
                        .font(.caption)
                        .foregroundStyle(AppColor.tertiaryText)
                        .lineLimit(1)
                } else if sessions > 0, let mastery {
                    Text(mastery.currentLayer.displayName)
                        .font(.caption)
                        .foregroundStyle(AppColor.layer(mastery.currentLayer))
                } else {
                    Text(opening.description)
                        .font(.caption)
                        .foregroundStyle(AppColor.tertiaryText)
                        .lineLimit(1)
                }
            }

            if locked {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(AppColor.gold)
            }
        }
        .opacity(locked ? 0.7 : 1.0)
        .accessibilityLabel("\(opening.name)\(locked ? ", locked" : ""), \(progressText(for: opening.id))")
    }

    private func progressText(for openingID: String) -> String {
        let mastery = allMastery[openingID]
        let sessions = mastery?.sessionsPlayed ?? 0
        if sessions == 0 { return "not started" }
        return "\(sessions) sessions played"
    }
}
