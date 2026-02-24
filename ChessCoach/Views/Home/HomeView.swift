import SwiftUI

struct HomeView: View {
    private let database = OpeningDatabase()
    @State private var selectedOpening: Opening?
    @State private var showResumePrompt = false
    @State private var resumeOpening: Opening?
    @State private var resumeLineID: String?
    @State private var streak = PersistenceService.shared.loadStreak()
    @State private var dueReviewCount = 0
    @State private var allProgress: [String: OpeningProgress] = [:]
    @State private var searchText = ""
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(AppSettings.self) private var settings

    // MARK: - Computed: Opening Recommender

    // Only surfaces a recommendation after real progress to avoid overwhelming beginners.
    private var recommendedOpening: Opening? {
        let progress = allProgress
        let advancedIDs = progress.filter {
            $0.value.currentPhase != .learningMainLine && $0.value.gamesPlayed >= 5
        }
        guard !advancedIDs.isEmpty else { return nil }

        let allOpenings = database.openings(forColor: .white) + database.openings(forColor: .black)
        let notStarted = allOpenings.filter { progress[$0.id] == nil || progress[$0.id]!.gamesPlayed == 0 }
        guard !notStarted.isEmpty else { return nil }

        let advancedOpenings = allOpenings.filter { advancedIDs[$0.id] != nil }
        let preferredColor = advancedOpenings.first?.color
        let preferredDifficulty = advancedOpenings.map(\.difficulty).max() ?? 1

        return notStarted
            .sorted { abs($0.difficulty - preferredDifficulty) < abs($1.difficulty - preferredDifficulty) }
            .first { $0.color == preferredColor }
            ?? notStarted.first
    }

    // MARK: - Computed: Search Filtering

    private func openings(forColor color: Opening.PlayerColor) -> [Opening] {
        let all = database.openings(forColor: color)
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    if showResumePrompt, let opening = resumeOpening {
                        resumeSessionCard(opening: opening)
                    }

                    streakBar

                    if let recommended = recommendedOpening {
                        recommendedCard(opening: recommended)
                    }

                    sectionHeader("Play as White")
                    ForEach(openings(forColor: .white)) { opening in
                        NavigationLink(value: opening) {
                            OpeningCard(opening: opening)
                                .overlay(alignment: .topTrailing) {
                                    badgeView(for: opening.id)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(opening.name), \(progressText(for: opening.id))")
                        .onAppear { settings.incrementViewCount(for: opening.id) }
                    }

                    sectionHeader("Play as Black")
                    ForEach(openings(forColor: .black)) { opening in
                        NavigationLink(value: opening) {
                            OpeningCard(opening: opening)
                                .overlay(alignment: .topTrailing) {
                                    badgeView(for: opening.id)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(opening.name), \(progressText(for: opening.id))")
                        .onAppear { settings.incrementViewCount(for: opening.id) }
                    }
                }
                .padding(AppSpacing.screenPadding)
            }
            .background(AppColor.background)
            .navigationTitle("ChessCoach")
            .preferredColorScheme(.dark)
            .searchable(text: $searchText, prompt: "Search openings...")
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
                SessionView(opening: opening, lineID: resumeLineID, isPro: subscriptionService.isPro)
                    .environment(subscriptionService)
            }
        }
    }

    // MARK: - Data

    private func refreshData() {
        allProgress = PersistenceService.shared.loadAllProgress()
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

    // MARK: - Subviews

    private func resumeSessionCard(opening: Opening) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(AppColor.success)

            VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                Text("Resume Session?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.primaryText)
                Text(opening.name)
                    .font(.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }

            Spacer()

            Button("Resume") {
                selectedOpening = opening
                showResumePrompt = false
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(AppColor.success)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColor.success.opacity(0.12), in: Capsule())

            Button {
                SessionViewModel.clearSavedSession()
                showResumePrompt = false
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColor.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(AppSpacing.cardPadding)
        .background(AppColor.success.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.md))
    }

    private func progressText(for openingID: String) -> String {
        let gamesPlayed = allProgress[openingID]?.gamesPlayed ?? 0
        if gamesPlayed == 0 { return "not started" }
        return "\(gamesPlayed) games played"
    }

    private var streakBar: some View {
        HStack(spacing: AppSpacing.sm) {
            // Streak flame and count
            Image(systemName: "flame.fill")
                .foregroundStyle(streak.currentStreak > 0 ? AppColor.unguided : AppColor.tertiaryText)

            Text("\(streak.currentStreak) day streak")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColor.primaryText)

            // Streak freeze indicator
            if streak.streakFreezes > 0 {
                HStack(spacing: AppSpacing.xxxs) {
                    Image(systemName: "snowflake")
                        .font(.caption2)
                        .foregroundStyle(AppColor.info)
                    Text("\(streak.streakFreezes)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AppColor.info)
                }
            }

            Spacer()

            // Daily goal progress ring with label
            let goalTarget = settings.dailyGoalTarget
            let goalCompleted = settings.dailyGoalCompleted
            let goalProgress = goalTarget > 0 ? Double(goalCompleted) / Double(goalTarget) : 0

            HStack(spacing: AppSpacing.xs) {
                ProgressRing(
                    progress: goalProgress,
                    color: goalProgress >= 1.0 ? AppColor.success : AppColor.info,
                    lineWidth: 3,
                    size: 24
                )

                Text("\(goalCompleted)/\(goalTarget) today")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(AppColor.secondaryText)
            }

            // Due reviews link
            if dueReviewCount > 0 {
                NavigationLink {
                    QuickReviewView()
                } label: {
                    Label("\(dueReviewCount) to review", systemImage: "arrow.counterclockwise.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.info)
                }
            }
        }
        .accessibilityLabel("Daily streak: \(streak.currentStreak) days")
    }

    private func recommendedCard(opening: Opening) -> some View {
        NavigationLink(value: opening) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "sparkle")
                    .font(.title3)
                    .foregroundStyle(AppColor.warning)

                VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                    Text("Recommended Next")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.warning)
                    Text(opening.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColor.primaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppColor.tertiaryText)
            }
            .padding(AppSpacing.cardPadding)
            .background(AppColor.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.md))
        }
        .buttonStyle(.plain)
    }

    // Badge decays from "New" -> "Try this!" as view count grows, disappears once played.
    @ViewBuilder
    private func badgeView(for openingID: String) -> some View {
        let count = settings.openingViewCounts[openingID] ?? 0
        let hasPlayed = (allProgress[openingID]?.gamesPlayed ?? 0) > 0

        if !hasPlayed {
            if count < 3 {
                PillBadge(text: "New", color: AppColor.success)
                    .padding(AppSpacing.sm)
            } else if count < 7 {
                PillBadge(text: "Try this!", color: AppColor.guided)
                    .padding(AppSpacing.sm)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColor.primaryText)
            Spacer()
        }
        .padding(.top, AppSpacing.sm)
    }
}
