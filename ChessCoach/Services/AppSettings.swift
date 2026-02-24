import SwiftUI

/// Centralized, type-safe settings service replacing scattered UserDefaults access.
/// Inject into environment via `.environment(appSettings)` on the root view.
@Observable
@MainActor
final class AppSettings {
    // MARK: - Keys (centralized, no more magic strings)

    private enum Key {
        static let hasSeenOnboarding = "has_seen_onboarding"
        static let userELO = "user_elo"
        static let opponentELO = "opponent_elo"
        static let soundEnabled = "sound_enabled"
        static let hapticsEnabled = "haptics_enabled"
        static let notationStyle = "notation_style"
        static let colorblindMode = "colorblind_mode"
        static let llmProvider = "llm_provider_preference"
        static let claudeAPIKey = "claude_api_key"
        static let ollamaHost = "ollama_host"
        static let ollamaModel = "ollama_model"
        static let openingViewCounts = "opening_view_counts"
        static let consecutiveCorrect = "chess_coach_consecutive_correct"
        static let debugProOverride = "debug_pro_override"
        static let dailyGoalTarget = "daily_goal_target"
        static let dailyGoalProgress = "daily_goal_progress_date"
        static let dailyGoalCount = "daily_goal_count"
        static let autoPlaySpeed = "auto_play_speed"
        static let showLegalMoves = "show_legal_moves_immediately"
        static let confettiEnabled = "confetti_enabled"
        static let notificationsEnabled = "notifications_enabled"
        static let gestureHintShown = "gesture_hint_shown"
    }

    private let defaults = UserDefaults.standard

    // MARK: - Player

    var userELO: Int {
        get { defaults.object(forKey: Key.userELO) as? Int ?? 600 }
        set { defaults.set(newValue, forKey: Key.userELO) }
    }

    var opponentELO: Int {
        get { defaults.object(forKey: Key.opponentELO) as? Int ?? 1200 }
        set { defaults.set(newValue, forKey: Key.opponentELO) }
    }

    // MARK: - Sound & Haptics

    var soundEnabled: Bool {
        get { defaults.object(forKey: Key.soundEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.soundEnabled) }
    }

    var hapticsEnabled: Bool {
        get { defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.hapticsEnabled) }
    }

    // MARK: - Display

    var notationStyle: String {
        get { defaults.string(forKey: Key.notationStyle) ?? "san" }
        set { defaults.set(newValue, forKey: Key.notationStyle) }
    }

    var colorblindMode: Bool {
        get { defaults.bool(forKey: Key.colorblindMode) }
        set { defaults.set(newValue, forKey: Key.colorblindMode) }
    }

    var confettiEnabled: Bool {
        get { defaults.object(forKey: Key.confettiEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.confettiEnabled) }
    }

    var showLegalMovesImmediately: Bool {
        get { defaults.object(forKey: Key.showLegalMoves) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showLegalMoves) }
    }

    // MARK: - LLM

    var llmProvider: String {
        get { defaults.string(forKey: Key.llmProvider) ?? "auto" }
        set { defaults.set(newValue, forKey: Key.llmProvider) }
    }

    var claudeAPIKey: String {
        get { defaults.string(forKey: Key.claudeAPIKey) ?? "" }
        set { defaults.set(newValue, forKey: Key.claudeAPIKey) }
    }

    var ollamaHost: String {
        get { defaults.string(forKey: Key.ollamaHost) ?? "192.168.4.62:11434" }
        set { defaults.set(newValue, forKey: Key.ollamaHost) }
    }

    var ollamaModel: String {
        get { defaults.string(forKey: Key.ollamaModel) ?? "qwen2.5:7b" }
        set { defaults.set(newValue, forKey: Key.ollamaModel) }
    }

    // MARK: - Onboarding

    var hasSeenOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasSeenOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasSeenOnboarding) }
    }

    // MARK: - Daily Goal

    var dailyGoalTarget: Int {
        get { defaults.object(forKey: Key.dailyGoalTarget) as? Int ?? 3 }
        set { defaults.set(newValue, forKey: Key.dailyGoalTarget) }
    }

    var dailyGoalCompleted: Int {
        get {
            // Reset if date changed
            let today = Self.todayString
            if defaults.string(forKey: Key.dailyGoalProgress) != today {
                defaults.set(today, forKey: Key.dailyGoalProgress)
                defaults.set(0, forKey: Key.dailyGoalCount)
                return 0
            }
            return defaults.integer(forKey: Key.dailyGoalCount)
        }
        set {
            defaults.set(Self.todayString, forKey: Key.dailyGoalProgress)
            defaults.set(newValue, forKey: Key.dailyGoalCount)
        }
    }

    func incrementDailyGoal() {
        dailyGoalCompleted += 1
    }

    // MARK: - Line Study

    var autoPlaySpeed: Double {
        get { defaults.object(forKey: Key.autoPlaySpeed) as? Double ?? 3.0 }
        set { defaults.set(newValue, forKey: Key.autoPlaySpeed) }
    }

    // MARK: - Notifications

    var notificationsEnabled: Bool {
        get { defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.notificationsEnabled) }
    }

    // MARK: - UX hints

    var gestureHintShown: Bool {
        get { defaults.bool(forKey: Key.gestureHintShown) }
        set { defaults.set(newValue, forKey: Key.gestureHintShown) }
    }

    // MARK: - View counts

    var openingViewCounts: [String: Int] {
        get { defaults.dictionary(forKey: Key.openingViewCounts) as? [String: Int] ?? [:] }
        set { defaults.set(newValue, forKey: Key.openingViewCounts) }
    }

    func incrementViewCount(for openingID: String) {
        var counts = openingViewCounts
        counts[openingID, default: 0] += 1
        openingViewCounts = counts
    }

    // MARK: - "I Know This" Tracking

    var consecutiveCorrectPlays: [String: Int] {
        get {
            if let data = defaults.data(forKey: Key.consecutiveCorrect),
               let dict = try? JSONDecoder().decode([String: Int].self, from: data) {
                return dict
            }
            return [:]
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.consecutiveCorrect)
            }
        }
    }

    // MARK: - Review Streak

    var bestReviewStreak: Int {
        get { defaults.integer(forKey: "best_review_streak") }
        set { defaults.set(newValue, forKey: "best_review_streak") }
    }

    // MARK: - Helpers

    private static var todayString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt.string(from: Date())
    }
}
