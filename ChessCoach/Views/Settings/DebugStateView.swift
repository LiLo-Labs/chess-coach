import SwiftUI

#if DEBUG
/// Debug menu for loading preset app states and exporting/importing snapshots.
/// Only available in DEBUG builds.
struct DebugStateView: View {
    @Environment(AppSettings.self) private var settings
    @State private var showExportSheet = false
    @State private var showImportSheet = false
    @State private var statusMessage: String?
    @State private var exportedURL: URL?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Text("Load a preset and the app resets to Home with that state applied.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Free Tier Presets") {
                Button("Fresh Install (FTU)", systemImage: "sparkles") {
                    loadFreshInstall()
                }

                Button("Italian Layer 1 — Learn the Plan", systemImage: "lightbulb") {
                    loadItalianLayer1()
                }

                Button("Italian Layer 2 — Practice the Plan", systemImage: "target") {
                    loadItalianLayer2()
                }

                Button("Italian Layer 3 — The Story", systemImage: "book.closed") {
                    loadItalianLayer3()
                }

                Button("London Layer 1 — Learn the Plan", systemImage: "lightbulb") {
                    loadLondonLayer1()
                }

                Button("Multiple Openings — Mixed Progress", systemImage: "square.grid.2x2") {
                    loadMixedProgress()
                }

                Button("Everything Complete (free)", systemImage: "checkmark.seal.fill") {
                    loadFullyComplete()
                }
            }

            Section("On-Device AI Tier") {
                Button("On-Device AI — Fresh", systemImage: "cpu") {
                    loadTierFresh(.onDeviceAI)
                }

                Button("On-Device AI — Italian Layer 2", systemImage: "cpu.fill") {
                    loadOnDeviceAIMidway()
                }
            }

            Section("Cloud AI Tier") {
                Button("Cloud AI — Fresh", systemImage: "cloud") {
                    loadTierFresh(.cloudAI)
                }

                Button("Cloud AI — Mixed Progress", systemImage: "cloud.fill") {
                    loadCloudAIMidway()
                }
            }

            Section("Pro Tier") {
                Button("Pro — Fresh (no progress)", systemImage: "crown") {
                    loadTierFresh(.pro)
                }

                Button("Pro — Italian Layer 4 + All Openings", systemImage: "crown.fill") {
                    loadProMidway()
                }

                Button("Pro — Fully Loaded (all layers, puzzles)", systemImage: "star.fill") {
                    loadProComplete()
                }

                Button("Pro — With Trainer Progress", systemImage: "figure.fencing") {
                    loadProWithTrainerProgress()
                }
            }

            Section("Per-Path Unlock") {
                Button("Free + Italian Unlocked", systemImage: "lock.open") {
                    loadPerPathUnlock(["italian"])
                }

                Button("Free + Italian & London Unlocked", systemImage: "lock.open.fill") {
                    loadPerPathUnlock(["italian", "london"])
                }
            }

            Section("Snapshots") {
                Button("Export Current State", systemImage: "square.and.arrow.up") {
                    exportState()
                }

                Button("Import State from File", systemImage: "square.and.arrow.down") {
                    showImportSheet = true
                }
            }

            Section("Quick Toggles") {
                // Tier picker
                let currentTier = currentDebugTier()
                Picker("Active Tier", selection: Binding(
                    get: { currentTier },
                    set: { setDebugTier($0) }
                )) {
                    ForEach(SubscriptionTier.allCases, id: \.rawValue) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }

                Button("Reset Onboarding (show FTU on next launch)", systemImage: "arrow.counterclockwise") {
                    settings.hasSeenOnboarding = false
                    statusMessage = "Onboarding reset — go back to see it"
                }

                Button("Clear All Mastery Data", systemImage: "trash") {
                    UserDefaults.standard.removeObject(forKey: "chess_coach_mastery")
                    statusMessage = "Mastery data cleared"
                }
                .foregroundStyle(.red)

                Button("Nuclear Reset (everything)", systemImage: "exclamationmark.triangle") {
                    nuclearReset()
                    statusMessage = "All data cleared"
                }
                .foregroundStyle(.red)
            }

            if let msg = statusMessage {
                Section {
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("Debug States")
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

    // MARK: - Apply & Dismiss

    private func applyAndDismiss(_ message: String) {
        statusMessage = message
        NotificationCenter.default.post(name: .debugStateDidChange, object: nil)
        dismiss()
    }

    // MARK: - Tier Helpers

    private func currentDebugTier() -> SubscriptionTier {
        if let raw = UserDefaults.standard.string(forKey: AppSettings.Key.debugTierOverride),
           let tier = SubscriptionTier(rawValue: raw) {
            return tier
        }
        if UserDefaults.standard.bool(forKey: AppSettings.Key.debugProOverride) {
            return .pro
        }
        return .free
    }

    private func setDebugTier(_ tier: SubscriptionTier) {
        UserDefaults.standard.set(tier.rawValue, forKey: AppSettings.Key.debugTierOverride)
        // Clear legacy bool
        UserDefaults.standard.removeObject(forKey: AppSettings.Key.debugProOverride)
        statusMessage = "Tier set to \(tier.displayName) — restart app"
        NotificationCenter.default.post(name: .debugStateDidChange, object: nil)
    }

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

        let mastery = OpeningMastery(openingID: "italian")
        PersistenceService.shared.saveMastery(mastery)

        applyAndDismiss("Loaded: Italian at Layer 1 (Learn the Plan)")
    }

    private func loadItalianLayer2() {
        nuclearReset()
        settings.hasSeenOnboarding = true
        settings.userELO = 800

        var mastery = OpeningMastery(openingID: "italian")
        mastery.planUnderstanding = true
        mastery.currentLayer = .executePlan
        mastery.executionScores = [62, 68, 71, 65, 74]
        mastery.sessionsPlayed = 5
        mastery.lastPlayed = Date().addingTimeInterval(-3600)
        mastery.averagePES = 68
        PersistenceService.shared.saveMastery(mastery)

        var streak = StreakTracker()
        streak.recordPractice()
        PersistenceService.shared.saveStreak(streak)

        applyAndDismiss("Loaded: Italian at Layer 2 (Practice the Plan)")
    }

    private func loadItalianLayer3() {
        nuclearReset()
        settings.hasSeenOnboarding = true
        settings.userELO = 1000

        var mastery = OpeningMastery(openingID: "italian")
        mastery.planUnderstanding = true
        mastery.planQuizScore = 1.0
        mastery.currentLayer = .discoverTheory
        mastery.executionScores = [65, 72, 78, 74, 80]
        mastery.sessionsPlayed = 8
        mastery.lastPlayed = Date().addingTimeInterval(-3600)
        mastery.averagePES = 74
        PersistenceService.shared.saveMastery(mastery)

        applyAndDismiss("Loaded: Italian at Layer 3 (The Story)")
    }

    private func loadLondonLayer1() {
        nuclearReset()
        settings.hasSeenOnboarding = true
        settings.userELO = 600

        let mastery = OpeningMastery(openingID: "london")
        PersistenceService.shared.saveMastery(mastery)

        applyAndDismiss("Loaded: London at Layer 1 (Learn the Plan)")
    }

    private func loadMixedProgress() {
        nuclearReset()
        settings.hasSeenOnboarding = true
        settings.userELO = 1000

        var italian = OpeningMastery(openingID: "italian")
        italian.planUnderstanding = true
        italian.currentLayer = .discoverTheory
        italian.executionScores = [65, 72, 78, 74, 80]
        italian.theoryCompleted = false
        italian.sessionsPlayed = 8
        italian.lastPlayed = Date().addingTimeInterval(-86400)
        italian.averagePES = 74
        PersistenceService.shared.saveMastery(italian)

        var london = OpeningMastery(openingID: "london")
        london.currentLayer = .understandPlan
        london.sessionsPlayed = 1
        london.lastPlayed = Date().addingTimeInterval(-3600)
        PersistenceService.shared.saveMastery(london)

        var sicilian = OpeningMastery(openingID: "sicilian")
        sicilian.planUnderstanding = true
        sicilian.currentLayer = .executePlan
        sicilian.executionScores = [45, 52, 58]
        sicilian.sessionsPlayed = 4
        sicilian.lastPlayed = Date().addingTimeInterval(-172800)
        sicilian.averagePES = 52
        PersistenceService.shared.saveMastery(sicilian)

        var streak = StreakTracker()
        streak.recordPractice()
        PersistenceService.shared.saveStreak(streak)

        settings.openingViewCounts = ["italian": 12, "london": 3, "sicilian": 6]

        applyAndDismiss("Loaded: 3 openings at different layers")
    }

    private func loadFullyComplete() {
        nuclearReset()
        settings.hasSeenOnboarding = true
        settings.userELO = 1400

        var italian = OpeningMastery(openingID: "italian")
        italian.planUnderstanding = true
        italian.currentLayer = .realConditions
        italian.executionScores = [72, 78, 82, 85, 88, 86, 90, 87, 91, 89]
        italian.theoryCompleted = true
        italian.responsesHandled = ["giuoco_piano", "two_knights", "hungarian"]
        italian.realConditionScores = [82, 85, 79, 88]
        italian.sessionsPlayed = 28
        italian.lastPlayed = Date().addingTimeInterval(-1800)
        italian.averagePES = 86
        PersistenceService.shared.saveMastery(italian)

        var london = OpeningMastery(openingID: "london")
        london.planUnderstanding = true
        london.currentLayer = .realConditions
        london.executionScores = [68, 74, 78, 80, 83, 85, 82, 87]
        london.theoryCompleted = true
        london.responsesHandled = ["kings_indian_setup", "queens_gambit_declined", "slav_setup"]
        london.realConditionScores = [78, 80, 82]
        london.sessionsPlayed = 22
        london.lastPlayed = Date().addingTimeInterval(-43200)
        london.averagePES = 81
        PersistenceService.shared.saveMastery(london)

        var streak = StreakTracker()
        for _ in 0..<7 { streak.recordPractice() }
        PersistenceService.shared.saveStreak(streak)

        settings.openingViewCounts = ["italian": 30, "london": 25]

        applyAndDismiss("Loaded: Both openings fully mastered")
    }

    // MARK: - On-Device AI Tier Presets

    private func loadOnDeviceAIMidway() {
        nuclearReset()
        enableTier(.onDeviceAI)
        settings.hasSeenOnboarding = true
        settings.userELO = 800

        var mastery = OpeningMastery(openingID: "italian")
        mastery.planUnderstanding = true
        mastery.currentLayer = .executePlan
        mastery.executionScores = [55, 62, 68, 72]
        mastery.sessionsPlayed = 6
        mastery.lastPlayed = Date().addingTimeInterval(-3600)
        mastery.averagePES = 64
        PersistenceService.shared.saveMastery(mastery)

        applyAndDismiss("Loaded: On-Device AI, Italian Layer 2")
    }

    // MARK: - Cloud AI Tier Presets

    private func loadCloudAIMidway() {
        nuclearReset()
        enableTier(.cloudAI)
        settings.hasSeenOnboarding = true
        settings.userELO = 1000

        var italian = OpeningMastery(openingID: "italian")
        italian.planUnderstanding = true
        italian.currentLayer = .discoverTheory
        italian.executionScores = [65, 72, 78, 74, 80]
        italian.sessionsPlayed = 8
        italian.lastPlayed = Date().addingTimeInterval(-3600)
        italian.averagePES = 74
        PersistenceService.shared.saveMastery(italian)

        var london = OpeningMastery(openingID: "london")
        london.planUnderstanding = true
        london.currentLayer = .executePlan
        london.executionScores = [50, 58, 65]
        london.sessionsPlayed = 4
        london.lastPlayed = Date().addingTimeInterval(-7200)
        london.averagePES = 58
        PersistenceService.shared.saveMastery(london)

        applyAndDismiss("Loaded: Cloud AI, 2 openings in progress")
    }

    // MARK: - Pro Tier Presets

    private func loadProMidway() {
        nuclearReset()
        enableTier(.pro)
        settings.hasSeenOnboarding = true
        settings.userELO = 1200

        var italian = OpeningMastery(openingID: "italian")
        italian.planUnderstanding = true
        italian.currentLayer = .handleVariety
        italian.executionScores = [65, 72, 78, 80, 83, 76, 85, 81]
        italian.theoryCompleted = true
        italian.responsesHandled = ["giuoco_piano", "two_knights"]
        italian.sessionsPlayed = 16
        italian.lastPlayed = Date().addingTimeInterval(-3600)
        italian.averagePES = 78
        PersistenceService.shared.saveMastery(italian)

        var london = OpeningMastery(openingID: "london")
        london.planUnderstanding = true
        london.currentLayer = .executePlan
        london.executionScores = [55, 62, 68]
        london.sessionsPlayed = 5
        london.lastPlayed = Date().addingTimeInterval(-7200)
        london.averagePES = 62
        PersistenceService.shared.saveMastery(london)

        var french = OpeningMastery(openingID: "french")
        french.currentLayer = .understandPlan
        french.sessionsPlayed = 0
        PersistenceService.shared.saveMastery(french)

        var caroKann = OpeningMastery(openingID: "caro-kann")
        caroKann.planUnderstanding = true
        caroKann.currentLayer = .discoverTheory
        caroKann.executionScores = [60, 68, 72, 75, 78]
        caroKann.theoryCompleted = false
        caroKann.sessionsPlayed = 7
        caroKann.lastPlayed = Date().addingTimeInterval(-172800)
        caroKann.averagePES = 71
        PersistenceService.shared.saveMastery(caroKann)

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

        let openingConfigs: [(String, LearningLayer, [Double], [Double], Set<String>, Double)] = [
            ("italian", .realConditions,
             [72, 78, 82, 85, 88, 86, 90, 87, 91, 89],
             [82, 85, 88, 90],
             ["giuoco_piano", "two_knights", "hungarian"], 87),
            ("london", .realConditions,
             [68, 74, 78, 80, 83, 85, 82, 87, 84],
             [78, 80, 82, 85],
             ["kings_indian_setup", "queens_gambit_declined", "slav_setup"], 82),
            ("sicilian", .handleVariety,
             [55, 62, 68, 72, 75, 78, 80, 76],
             [],
             ["open_sicilian", "alapin"], 73),
            ("french", .discoverTheory,
             [58, 65, 70, 74, 72],
             [],
             [], 68),
            ("caro-kann", .realConditions,
             [65, 72, 78, 82, 85, 80, 83, 86],
             [80, 83, 78],
             ["advance", "classical", "exchange"], 80),
            ("queens-gambit", .executePlan,
             [52, 58, 64],
             [],
             [], 58),
            ("kings-indian", .handleVariety,
             [60, 68, 72, 75, 78, 80],
             [],
             ["classical", "samisch", "four_pawns"], 72),
            ("ruy-lopez", .executePlan,
             [48, 55, 62, 66],
             [],
             [], 58),
        ]

        for (id, layer, execScores, realScores, responses, avgPES) in openingConfigs {
            var mastery = OpeningMastery(openingID: id)
            mastery.planUnderstanding = true
            mastery.currentLayer = layer
            mastery.executionScores = execScores
            mastery.theoryCompleted = layer.rawValue >= LearningLayer.handleVariety.rawValue
            mastery.responsesHandled = responses
            mastery.realConditionScores = realScores
            mastery.sessionsPlayed = execScores.count + realScores.count + 2
            mastery.lastPlayed = Date().addingTimeInterval(Double.random(in: -259200...(-1800)))
            mastery.averagePES = avgPES
            PersistenceService.shared.saveMastery(mastery)
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

        // Opening mastery
        var italian = OpeningMastery(openingID: "italian")
        italian.planUnderstanding = true
        italian.currentLayer = .discoverTheory
        italian.executionScores = [65, 72, 78, 74, 80]
        italian.sessionsPlayed = 8
        italian.lastPlayed = Date().addingTimeInterval(-3600)
        italian.averagePES = 74
        PersistenceService.shared.saveMastery(italian)

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

    // MARK: - Per-Path Unlock Presets

    private func loadPerPathUnlock(_ paths: [String]) {
        nuclearReset()
        // Stay on free tier but unlock specific paths
        settings.hasSeenOnboarding = true
        settings.userELO = 800
        UserDefaults.standard.set(paths, forKey: "chess_coach_unlocked_paths")

        for pathID in paths {
            var mastery = OpeningMastery(openingID: pathID)
            mastery.currentLayer = .understandPlan
            mastery.sessionsPlayed = 0
            PersistenceService.shared.saveMastery(mastery)
        }

        applyAndDismiss("Loaded: Free + \(paths.joined(separator: ", ")) unlocked")
    }

    // MARK: - Export / Import

    private func exportState() {
        let defaults = UserDefaults.standard
        let keysToExport = [
            "chess_coach_mastery",
            "chess_coach_progress",
            "chess_coach_streak",
            "chess_coach_review_items",
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
            "chess_coach_mastery",
            "chess_coach_progress",
            "chess_coach_streak",
            "chess_coach_review_items",
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
        statusMessage = nil
    }

    // MARK: - Helpers

    private func formattedDate() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd-HHmmss"
        return fmt.string(from: Date())
    }
}
#endif
