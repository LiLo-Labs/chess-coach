#if DEBUG
import Foundation

/// Loads debug states from launch arguments for screenshot UI tests.
/// Reuses the same state setup logic as DebugStateView presets.
enum ScreenshotStateLoader {
    static func loadState(_ name: String) {
        nuclearReset()

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: AppSettings.Key.hasSeenOnboarding)
        defaults.set(true, forKey: AppSettings.Key.hasPickedFreeOpening)
        defaults.set("italian", forKey: AppSettings.Key.pickedFreeOpeningID)
        defaults.set(true, forKey: AppSettings.Key.hasSeenHomeTour)
        defaults.set(true, forKey: AppSettings.Key.hasSeenBetaWelcome)

        // Mark all concept intros as seen to avoid popups blocking navigation
        for concept in ConceptIntro.allCases {
            concept.markSeen()
        }

        switch name {
        case "proMidway":
            defaults.set(SubscriptionTier.pro.rawValue, forKey: AppSettings.Key.debugTierOverride)
            defaults.set(1200, forKey: AppSettings.Key.userELO)
            loadProMidwayMastery()

        case "proTrainerProgress":
            defaults.set(SubscriptionTier.pro.rawValue, forKey: AppSettings.Key.debugTierOverride)
            defaults.set(1200, forKey: AppSettings.Key.userELO)
            loadProTrainerProgress()

        case "italianLayer1":
            defaults.set(600, forKey: AppSettings.Key.userELO)
            saveDebugPositions(openingID: "italian", positionCount: 10, masteredFraction: 0.0)

        case "freshInstall":
            defaults.set(false, forKey: AppSettings.Key.hasSeenOnboarding)

        default:
            break
        }
    }

    private static func nuclearReset() {
        let defaults = UserDefaults.standard
        let allKeys = [
            "chess_coach_position_mastery",
            "chess_coach_streak", "chess_coach_mistakes", "chess_coach_speed_runs",
            "chess_coach_saved_session", "chess_coach_consecutive_correct",
            "chess_coach_unlocked_paths", "has_seen_onboarding", "user_elo",
            "opponent_elo", "opening_view_counts", "daily_goal_target",
            "daily_goal_count", "daily_goal_progress_date", "gesture_hint_shown",
            "best_review_streak", "player_elo_human", "player_elo_engine",
            "player_opening_accuracy", "player_weekly_history",
            "chess_coach_trainer_stats_humanLike", "chess_coach_trainer_stats_engine",
            "chess_coach_trainer_games_v2",
            AppSettings.Key.debugTierOverride, AppSettings.Key.debugProOverride,
        ]
        for key in allKeys {
            defaults.removeObject(forKey: key)
        }
    }

    private static func loadProMidwayMastery() {
        saveDebugPositions(openingID: "italian", positionCount: 14, masteredFraction: 0.6)
        saveDebugPositions(openingID: "london", positionCount: 10, masteredFraction: 0.2)

        var streak = StreakTracker()
        streak.recordPractice()
        PersistenceService.shared.saveStreak(streak)

        UserDefaults.standard.set(
            ["italian": 20, "london": 8, "french": 2, "caro-kann": 10],
            forKey: AppSettings.Key.openingViewCounts
        )
    }

    private static func loadProTrainerProgress() {
        loadProMidwayMastery()

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
    }

    private static func saveDebugPositions(openingID: String, positionCount: Int, masteredFraction: Double) {
        let masteredCount = Int(Double(positionCount) * masteredFraction)
        var positions: [PositionMastery] = []
        for i in 0..<positionCount {
            var pm = PositionMastery(openingID: openingID, fen: "debug/\(openingID)/\(i)", ply: i * 2 + 1, lineID: "\(openingID)/main")
            if i < masteredCount {
                pm.repetitions = 4; pm.totalAttempts = 10; pm.correctAttempts = 9
                pm.interval = 30; pm.nextReviewDate = Date().addingTimeInterval(86400 * 30)
            } else {
                pm.repetitions = 1; pm.totalAttempts = 3; pm.correctAttempts = 1
                pm.interval = 1; pm.nextReviewDate = Date()
            }
            positions.append(pm)
        }
        var all = PersistenceService.shared.loadAllPositionMastery().filter { $0.openingID != openingID }
        all.append(contentsOf: positions)
        PersistenceService.shared.savePositionMastery(all)
    }
}
#endif
