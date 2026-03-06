import SwiftUI

/// Debug menu for loading preset app states and exporting/importing snapshots.
/// Available in DEBUG and TestFlight builds for beta testing.
struct DebugStateView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(TokenService.self) private var tokenService
    @State private var showExportSheet = false
    @State private var showImportSheet = false
    @State private var statusMessage: String?
    @State private var exportedURL: URL?
    @State private var unlockedPaths: Set<String> = []

    @Environment(\.dismiss) private var dismiss

    private let freeIDs = AppConfig.pro.freeOpeningIDs
    private let allOpenings = OpeningDatabase.shared.openings

    var body: some View {
        List {
            tokenSection
            freeSection
            onDeviceAISection
            cloudAISection
            proSection
            toolsSection

            if let msg = statusMessage {
                Section {
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("Debug States")
        .onAppear {
            let paths = UserDefaults.standard.stringArray(forKey: "chess_coach_unlocked_paths") ?? []
            unlockedPaths = Set(paths)
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = exportedURL {
                ShareLink(item: url)
            }
        }
        .fileImporter(isPresented: $showImportSheet, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                importState(from: url)
            case .failure(let error):
                statusMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Sections

    private var tokenSection: some View {
        Section {
            HStack(spacing: 12) {
                ForEach([0, 50, 200, 500], id: \.self) { amount in
                    Button {
                        tokenService.setDebugBalance(amount)
                        statusMessage = "Token balance set to \(amount)"
                    } label: {
                        Text("\(amount)")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)

            Text("Current balance: \(tokenService.balance.balance) tokens")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Token Balance")
        }
    }

    private var freeSection: some View {
        Section {
            Button("Fresh Install (FTU)", systemImage: "sparkles") {
                loadFreshInstall()
            }

            Button("Italian — Learning (10%)", systemImage: "lightbulb") {
                loadItalianLayer1()
            }

            Button("Italian — Practicing (45%)", systemImage: "target") {
                loadItalianLayer2()
            }

            Button("Italian — Familiar (80%)", systemImage: "checkmark.seal") {
                loadItalianLayer3()
            }

            Button("London — Learning (10%)", systemImage: "lightbulb") {
                loadLondonLayer1()
            }

            Button("Multiple Openings — Mixed Progress", systemImage: "square.grid.2x2") {
                loadMixedProgress()
            }

            Button("Everything Complete (free)", systemImage: "checkmark.seal.fill") {
                loadFullyComplete()
            }

            // Path unlock toggles
            DisclosureGroup("Path Unlocks") {
                ForEach(allOpenings, id: \.id) { opening in
                    let isFree = freeIDs.contains(opening.id)
                    Toggle(isOn: Binding(
                        get: { isFree || unlockedPaths.contains(opening.id) },
                        set: { newValue in
                            togglePathUnlock(opening.id, enabled: newValue)
                        }
                    )) {
                        Text(opening.name)
                            .foregroundStyle(isFree ? .secondary : .primary)
                    }
                    .disabled(isFree)
                }
            }
        } header: {
            Text("Free")
        }
    }

    private var onDeviceAISection: some View {
        Section("On-Device AI") {
            Button("Fresh", systemImage: "cpu") {
                loadTierFresh(.onDeviceAI)
            }

            Button("Italian — Practicing (45%)", systemImage: "cpu.fill") {
                loadOnDeviceAIMidway()
            }
        }
    }

    private var cloudAISection: some View {
        Section("Cloud AI") {
            Button("Fresh", systemImage: "cloud") {
                loadTierFresh(.cloudAI)
            }

            Button("Mixed Progress", systemImage: "cloud.fill") {
                loadCloudAIMidway()
            }
        }
    }

    private var proSection: some View {
        Section("Pro (Full Unlock)") {
            Button("Fresh", systemImage: "crown") {
                loadTierFresh(.pro)
            }

            Button("Italian — Familiar (80%) + All Openings", systemImage: "crown.fill") {
                loadProMidway()
            }

            Button("Fully Loaded", systemImage: "star.fill") {
                loadProComplete()
            }

            Button("Trainer Progress", systemImage: "figure.fencing") {
                loadProWithTrainerProgress()
            }
        }
    }

    private var toolsSection: some View {
        Section("Tools") {
            Button("Export Current State", systemImage: "square.and.arrow.up") {
                exportState()
            }

            Button("Import State from File", systemImage: "square.and.arrow.down") {
                showImportSheet = true
            }

            Button("Reset Onboarding (show FTU on next launch)", systemImage: "arrow.counterclockwise") {
                settings.hasSeenOnboarding = false
                statusMessage = "Onboarding reset — go back to see it"
            }

            Button("Clear All Position Mastery", systemImage: "trash") {
                UserDefaults.standard.removeObject(forKey: "chess_coach_position_mastery")
                statusMessage = "Position mastery data cleared"
            }
            .foregroundStyle(.red)

            Button("Nuclear Reset (everything)", systemImage: "exclamationmark.triangle") {
                nuclearReset()
                statusMessage = "All data cleared"
            }
            .foregroundStyle(.red)
        }
    }

    // MARK: - Path Unlock Toggle

    private func togglePathUnlock(_ openingID: String, enabled: Bool) {
        if enabled {
            unlockedPaths.insert(openingID)
        } else {
            unlockedPaths.remove(openingID)
        }
        UserDefaults.standard.set(Array(unlockedPaths), forKey: "chess_coach_unlocked_paths")
        NotificationCenter.default.post(name: .debugStateDidChange, object: nil)
    }

    // MARK: - Apply & Dismiss

    private func applyAndDismiss(_ message: String) {
        statusMessage = message
        NotificationCenter.default.post(name: .debugStateDidChange, object: nil)
        dismiss()
    }

    // MARK: - Tier Helpers

    private func enableTier(_ tier: SubscriptionTier) {
        UserDefaults.standard.set(tier.rawValue, forKey: AppSettings.Key.debugTierOverride)
        UserDefaults.standard.removeObject(forKey: AppSettings.Key.debugProOverride)
    }

    // MARK: - Preset: Fresh Install

    private func loadFreshInstall() {
        nuclearReset()
        settings.hasSeenOnboarding = false
        applyAndDismiss("Reset to fresh install")
    }

    // MARK: - Preset: Tier Fresh (any tier, no progress)

    private func loadTierFresh(_ tier: SubscriptionTier) {
        nuclearReset()
        enableTier(tier)
        settings.hasSeenOnboarding = true
        settings.userELO = 1000
        applyAndDismiss("Loaded: \(tier.displayName) user, fresh start")
    }

    // MARK: - Free Tier Presets

    private func loadItalianLayer1() {
        nuclearReset()
        settings.hasSeenOnboarding = true
        settings.userELO = 600
        saveDebugPositions(openingID: "italian", positionCount: 10, masteredFraction: 0.0)
        applyAndDismiss("Loaded: Italian — Learning (0%)")
    }

    private func loadItalianLayer2() {
        nuclearReset()
        settings.hasSeenOnboarding = true
        settings.userELO = 800
        saveDebugPositions(openingID: "italian", positionCount: 10, masteredFraction: 0.2)

        var streak = StreakTracker()
        streak.recordPractice()
        PersistenceService.shared.saveStreak(streak)

        applyAndDismiss("Loaded: Italian — Learning (20%)")
    }

    private func loadItalianLayer3() {
        nuclearReset()
        settings.hasSeenOnboarding = true
        settings.userELO = 1000
        saveDebugPositions(openingID: "italian", positionCount: 12, masteredFraction: 0.4)
        applyAndDismiss("Loaded: Italian — Practicing (40%)")
    }

    private func loadLondonLayer1() {
        nuclearReset()
        settings.hasSeenOnboarding = true
        settings.userELO = 600
        saveDebugPositions(openingID: "london", positionCount: 8, masteredFraction: 0.0)
        applyAndDismiss("Loaded: London — Learning (0%)")
    }

    private func loadMixedProgress() {
        nuclearReset()
        settings.hasSeenOnboarding = true
        settings.userELO = 1000

        saveDebugPositions(openingID: "italian", positionCount: 12, masteredFraction: 0.4)
        saveDebugPositions(openingID: "london", positionCount: 8, masteredFraction: 0.1)
        saveDebugPositions(openingID: "sicilian", positionCount: 10, masteredFraction: 0.2)

        var streak = StreakTracker()
        streak.recordPractice()
        PersistenceService.shared.saveStreak(streak)

        settings.openingViewCounts = ["italian": 12, "london": 3, "sicilian": 6]

        applyAndDismiss("Loaded: 3 openings at mixed familiarity")
    }

    private func loadFullyComplete() {
        nuclearReset()
        settings.hasSeenOnboarding = true
        settings.userELO = 1400

        saveDebugPositions(openingID: "italian", positionCount: 15, masteredFraction: 0.9)
        saveDebugPositions(openingID: "london", positionCount: 12, masteredFraction: 0.85)

        var streak = StreakTracker()
        for _ in 0..<7 { streak.recordPractice() }
        PersistenceService.shared.saveStreak(streak)

        settings.openingViewCounts = ["italian": 30, "london": 25]

        applyAndDismiss("Loaded: Both openings — Familiar (85-90%)")
    }

    // MARK: - On-Device AI Tier Presets

    private func loadOnDeviceAIMidway() {
        nuclearReset()
        enableTier(.onDeviceAI)
        settings.hasSeenOnboarding = true
        settings.userELO = 800
        saveDebugPositions(openingID: "italian", positionCount: 10, masteredFraction: 0.2)
        applyAndDismiss("Loaded: On-Device AI, Italian — Learning (20%)")
    }

    // MARK: - Cloud AI Tier Presets

    private func loadCloudAIMidway() {
        nuclearReset()
        enableTier(.cloudAI)
        settings.hasSeenOnboarding = true
        settings.userELO = 1000
        saveDebugPositions(openingID: "italian", positionCount: 12, masteredFraction: 0.4)
        saveDebugPositions(openingID: "london", positionCount: 8, masteredFraction: 0.15)
        applyAndDismiss("Loaded: Cloud AI, 2 openings in progress")
    }

    // MARK: - Pro Tier Presets

    private func loadProMidway() {
        nuclearReset()
        enableTier(.pro)
        settings.hasSeenOnboarding = true
        settings.userELO = 1200

        saveDebugPositions(openingID: "italian", positionCount: 14, masteredFraction: 0.6)
        saveDebugPositions(openingID: "london", positionCount: 10, masteredFraction: 0.2)
        saveDebugPositions(openingID: "french", positionCount: 6, masteredFraction: 0.0)
        saveDebugPositions(openingID: "caro-kann", positionCount: 10, masteredFraction: 0.35)

        var streak = StreakTracker()
        streak.recordPractice()
        PersistenceService.shared.saveStreak(streak)

        settings.openingViewCounts = [
            "italian": 20, "london": 8, "french": 2, "caro-kann": 10,
            "sicilian": 4, "queens-gambit": 3
        ]

        applyAndDismiss("Loaded: Pro user, 4 openings in progress")
    }

    private func loadProComplete() {
        nuclearReset()
        enableTier(.pro)
        settings.hasSeenOnboarding = true
        settings.userELO = 1500

        let openingConfigs: [(String, Double)] = [
            ("italian", 0.85), ("london", 0.85),
            ("sicilian", 0.65), ("french", 0.45),
            ("caro-kann", 0.85), ("queens-gambit", 0.25),
            ("kings-indian", 0.65), ("ruy-lopez", 0.25),
        ]

        for (id, famFraction) in openingConfigs {
            saveDebugPositions(openingID: id, positionCount: 12, masteredFraction: famFraction)
        }

        var streak = StreakTracker()
        for _ in 0..<14 { streak.recordPractice() }
        PersistenceService.shared.saveStreak(streak)

        settings.openingViewCounts = [
            "italian": 35, "london": 30, "sicilian": 18, "french": 12,
            "caro-kann": 25, "queens-gambit": 8, "kings-indian": 15, "ruy-lopez": 10
        ]

        applyAndDismiss("Loaded: Pro power user, 8 openings")
    }

    // MARK: - Pro + Trainer Progress

    private func loadProWithTrainerProgress() {
        nuclearReset()
        enableTier(.pro)
        settings.hasSeenOnboarding = true
        settings.userELO = 1200

        saveDebugPositions(openingID: "italian", positionCount: 12, masteredFraction: 0.4)

        // Player progress — simulated ELO history
        var humanELO = ELOEstimate()
        humanELO.rating = 1050
        humanELO.gamesPlayed = 18
        humanELO.peak = 1100
        humanELO.lastGameDate = Date().addingTimeInterval(-1800)
        humanELO.recentResults = [1.0, 0.0, 1.0, 1.0, 0.5, 0.0, 1.0, 1.0, 0.0, 1.0]

        var engineELO = ELOEstimate()
        engineELO.rating = 850
        engineELO.gamesPlayed = 12
        engineELO.peak = 900
        engineELO.lastGameDate = Date().addingTimeInterval(-7200)
        engineELO.recentResults = [0.0, 1.0, 0.0, 0.0, 1.0, 0.5, 0.0, 1.0]

        if let data = try? JSONEncoder().encode(humanELO) {
            UserDefaults.standard.set(data, forKey: "player_elo_human")
        }
        if let data = try? JSONEncoder().encode(engineELO) {
            UserDefaults.standard.set(data, forKey: "player_elo_engine")
        }

        // Opening accuracy
        let accuracy: [String: OpeningAccuracy] = [
            "italian": OpeningAccuracy(openingID: "italian", totalGames: 12, wins: 7, losses: 4, draws: 1, lastPlayed: Date()),
            "london": OpeningAccuracy(openingID: "london", totalGames: 6, wins: 2, losses: 3, draws: 1, lastPlayed: Date().addingTimeInterval(-86400)),
        ]
        if let data = try? JSONEncoder().encode(accuracy) {
            UserDefaults.standard.set(data, forKey: "player_opening_accuracy")
        }

        // Weekly snapshots
        let calendar = Calendar.current
        let now = Date()
        var snapshots: [WeeklySnapshot] = []
        for weeksAgo in stride(from: 4, through: 0, by: -1) {
            let date = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: now)!
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-ww"
            snapshots.append(WeeklySnapshot(
                weekKey: fmt.string(from: date),
                date: date,
                humanELO: 800 + (4 - weeksAgo) * 60,
                engineELO: 700 + (4 - weeksAgo) * 35,
                gamesPlayed: Int.random(in: 3...8)
            ))
        }
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: "player_weekly_history")
        }

        var streak = StreakTracker()
        streak.recordPractice()
        PersistenceService.shared.saveStreak(streak)

        applyAndDismiss("Loaded: Pro user with trainer progress + ELO history")
    }

    // MARK: - Export / Import

    private func exportState() {
        let defaults = UserDefaults.standard
        let keysToExport = [
            "chess_coach_position_mastery",
            "chess_coach_streak",
            "chess_coach_mistakes",
            "chess_coach_speed_runs",
            "chess_coach_unlocked_paths",
            "has_seen_onboarding",
            "user_elo",
            "opponent_elo",
            "opening_view_counts",
            "daily_goal_target",
            "daily_goal_count",
            "daily_goal_progress_date",
            "chess_coach_consecutive_correct",
            "chess_coach_schema_version",
            // PlayerProgressService keys
            "player_elo_human",
            "player_elo_engine",
            "player_opening_accuracy",
            "player_weekly_history",
            // Trainer stats keys
            "chess_coach_trainer_stats_humanLike",
            "chess_coach_trainer_stats_engine",
            "chess_coach_trainer_games_v2",
            AppSettings.Key.debugTierOverride,
            AppSettings.Key.debugProOverride,
        ]

        var snapshot: [String: Any] = [:]
        snapshot["_exportDate"] = ISO8601DateFormatter().string(from: Date())
        snapshot["_exportVersion"] = 2

        for key in keysToExport {
            if let value = defaults.object(forKey: key) {
                if let data = value as? Data {
                    snapshot[key] = ["_type": "data", "_value": data.base64EncodedString()]
                } else {
                    snapshot[key] = value
                }
            }
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
            let tempDir = FileManager.default.temporaryDirectory
            let filename = "chesscoach-state-\(formattedDate()).json"
            let url = tempDir.appendingPathComponent(filename)
            try data.write(to: url)
            exportedURL = url
            showExportSheet = true
            statusMessage = "State exported to \(filename)"
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importState(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            statusMessage = "Couldn't access file"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            guard let snapshot = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                statusMessage = "Invalid snapshot format"
                return
            }

            let defaults = UserDefaults.standard
            for (key, value) in snapshot {
                if key.hasPrefix("_") { continue }

                if let dict = value as? [String: String],
                   dict["_type"] == "data",
                   let b64 = dict["_value"],
                   let decoded = Data(base64Encoded: b64) {
                    defaults.set(decoded, forKey: key)
                } else {
                    defaults.set(value, forKey: key)
                }
            }

            statusMessage = "State imported successfully — restart or navigate back"
        } catch {
            statusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Nuclear Reset

    private func nuclearReset() {
        let defaults = UserDefaults.standard
        let allKeys = [
            "chess_coach_position_mastery",
            "chess_coach_streak",
            "chess_coach_mistakes",
            "chess_coach_speed_runs",
            "chess_coach_saved_session",
            "chess_coach_consecutive_correct",
            "chess_coach_unlocked_paths",
            "has_seen_onboarding",
            "user_elo",
            "opponent_elo",
            "opening_view_counts",
            "daily_goal_target",
            "daily_goal_count",
            "daily_goal_progress_date",
            "gesture_hint_shown",
            "best_review_streak",
            // PlayerProgressService keys
            "player_elo_human",
            "player_elo_engine",
            "player_opening_accuracy",
            "player_weekly_history",
            // Trainer stats keys
            "chess_coach_trainer_stats_humanLike",
            "chess_coach_trainer_stats_engine",
            "chess_coach_trainer_games_v2",
            AppSettings.Key.debugTierOverride,
            AppSettings.Key.debugProOverride,
        ]
        for key in allKeys {
            defaults.removeObject(forKey: key)
        }
        unlockedPaths = []
        statusMessage = nil
    }

    // MARK: - Helpers

    private func formattedDate() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        return fmt.string(from: Date())
    }

    /// Generate fake PositionMastery data for debug presets.
    /// `positionCount` total positions, `masteredFraction` of them fully mastered.
    private func saveDebugPositions(openingID: String, positionCount: Int, masteredFraction: Double) {
        let masteredCount = Int(Double(positionCount) * masteredFraction)
        var positions: [PositionMastery] = []
        for i in 0..<positionCount {
            var pm = PositionMastery(
                openingID: openingID,
                fen: "debug/\(openingID)/\(i)",
                ply: i * 2 + 1,
                lineID: "\(openingID)/main"
            )
            if i < masteredCount {
                // Mastered: repetitions >= 3, accuracy >= 0.8
                pm.repetitions = 4
                pm.totalAttempts = 10
                pm.correctAttempts = 9
                pm.interval = 30
                pm.nextReviewDate = Date().addingTimeInterval(86400 * 30)
            } else {
                // Not yet mastered
                pm.repetitions = 1
                pm.totalAttempts = 3
                pm.correctAttempts = 1
                pm.interval = 1
                pm.nextReviewDate = Date()
            }
            positions.append(pm)
        }
        var all = PersistenceService.shared.loadAllPositionMastery().filter { $0.openingID != openingID }
        all.append(contentsOf: positions)
        PersistenceService.shared.savePositionMastery(all)
    }
}
