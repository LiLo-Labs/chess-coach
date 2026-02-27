import SwiftUI

/// Centralized, type-safe settings service replacing scattered UserDefaults access.
/// Inject into environment via `.environment(appSettings)` on the root view.
///
/// All properties are **stored** so the @Observable macro can track mutations.
/// Each setter syncs the new value to UserDefaults for persistence across launches.
@Observable
@MainActor
final class AppSettings {
    // MARK: - Keys (centralized, no more magic strings)

    enum Key {
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
        static let debugTierOverride = "debug_tier_override"
        static let dailyGoalTarget = "daily_goal_target"
        static let dailyGoalProgress = "daily_goal_progress_date"
        static let dailyGoalCount = "daily_goal_count"
        static let autoPlaySpeed = "auto_play_speed"
        static let showLegalMoves = "show_legal_moves_immediately"
        static let confettiEnabled = "confetti_enabled"
        static let notificationsEnabled = "notifications_enabled"
        static let gestureHintShown = "gesture_hint_shown"
        static let bestReviewStreak = "best_review_streak"
        static let boardTheme = "board_theme"
        static let pieceStyle = "piece_style"
        static let hasPickedFreeOpening = "has_picked_free_opening"
        static let pickedFreeOpeningID = "picked_free_opening_id"
    }

    @ObservationIgnored private let defaults = UserDefaults.standard

    // MARK: - Player

    var userELO: Int {
        didSet { defaults.set(userELO, forKey: Key.userELO) }
    }

    var opponentELO: Int {
        didSet { defaults.set(opponentELO, forKey: Key.opponentELO) }
    }

    // MARK: - Sound & Haptics

    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) }
    }

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) }
    }

    // MARK: - Display

    var notationStyle: String {
        didSet { defaults.set(notationStyle, forKey: Key.notationStyle) }
    }

    var colorblindMode: Bool {
        didSet { defaults.set(colorblindMode, forKey: Key.colorblindMode) }
    }

    var confettiEnabled: Bool {
        didSet { defaults.set(confettiEnabled, forKey: Key.confettiEnabled) }
    }

    var showLegalMovesImmediately: Bool {
        didSet { defaults.set(showLegalMovesImmediately, forKey: Key.showLegalMoves) }
    }

    var boardTheme: BoardTheme {
        didSet { defaults.set(boardTheme.rawValue, forKey: Key.boardTheme) }
    }

    var pieceStyle: PieceStyle {
        didSet { defaults.set(pieceStyle.rawValue, forKey: Key.pieceStyle) }
    }

    // MARK: - Free Opening Pick

    var hasPickedFreeOpening: Bool {
        didSet { defaults.set(hasPickedFreeOpening, forKey: Key.hasPickedFreeOpening) }
    }

    var pickedFreeOpeningID: String? {
        didSet { defaults.set(pickedFreeOpeningID, forKey: Key.pickedFreeOpeningID) }
    }

    // MARK: - LLM

    var llmProvider: String {
        didSet { defaults.set(llmProvider, forKey: Key.llmProvider) }
    }

    var claudeAPIKey: String {
        didSet { defaults.set(claudeAPIKey, forKey: Key.claudeAPIKey) }
    }

    var ollamaHost: String {
        didSet { defaults.set(ollamaHost, forKey: Key.ollamaHost) }
    }

    var ollamaModel: String {
        didSet { defaults.set(ollamaModel, forKey: Key.ollamaModel) }
    }

    // MARK: - Onboarding

    var hasSeenOnboarding: Bool {
        didSet { defaults.set(hasSeenOnboarding, forKey: Key.hasSeenOnboarding) }
    }

    // MARK: - Daily Goal

    var dailyGoalTarget: Int {
        didSet { defaults.set(dailyGoalTarget, forKey: Key.dailyGoalTarget) }
    }

    var dailyGoalCompleted: Int {
        didSet {
            defaults.set(Self.todayString, forKey: Key.dailyGoalProgress)
            defaults.set(dailyGoalCompleted, forKey: Key.dailyGoalCount)
        }
    }

    func incrementDailyGoal() {
        dailyGoalCompleted += 1
    }

    // MARK: - Line Study

    var autoPlaySpeed: Double {
        didSet { defaults.set(autoPlaySpeed, forKey: Key.autoPlaySpeed) }
    }

    // MARK: - Notifications

    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }

    // MARK: - UX hints

    var gestureHintShown: Bool {
        didSet { defaults.set(gestureHintShown, forKey: Key.gestureHintShown) }
    }

    // MARK: - View counts

    var openingViewCounts: [String: Int] {
        didSet { defaults.set(openingViewCounts, forKey: Key.openingViewCounts) }
    }

    func incrementViewCount(for openingID: String) {
        var counts = openingViewCounts
        counts[openingID, default: 0] += 1
        openingViewCounts = counts
    }

    // MARK: - "I Know This" Tracking

    var consecutiveCorrectPlays: [String: Int] {
        didSet {
            defaults.set(consecutiveCorrectPlays, forKey: Key.consecutiveCorrect)
        }
    }

    // MARK: - Review Streak

    var bestReviewStreak: Int {
        didSet { defaults.set(bestReviewStreak, forKey: Key.bestReviewStreak) }
    }

    // MARK: - Initialization

    init() {
        let d = UserDefaults.standard

        // Load all values from UserDefaults (or use defaults)
        self.userELO = d.object(forKey: Key.userELO) as? Int ?? 600
        self.opponentELO = d.object(forKey: Key.opponentELO) as? Int ?? 1200
        self.soundEnabled = d.object(forKey: Key.soundEnabled) as? Bool ?? true
        self.hapticsEnabled = d.object(forKey: Key.hapticsEnabled) as? Bool ?? true
        self.notationStyle = d.string(forKey: Key.notationStyle) ?? "san"
        self.colorblindMode = d.bool(forKey: Key.colorblindMode)
        self.confettiEnabled = d.object(forKey: Key.confettiEnabled) as? Bool ?? true
        self.showLegalMovesImmediately = d.object(forKey: Key.showLegalMoves) as? Bool ?? true
        self.llmProvider = d.string(forKey: Key.llmProvider) ?? "onDevice"
        self.claudeAPIKey = d.string(forKey: Key.claudeAPIKey) ?? ""
        self.ollamaHost = d.string(forKey: Key.ollamaHost) ?? AppConfig.llm.defaultOllamaHost
        self.ollamaModel = d.string(forKey: Key.ollamaModel) ?? AppConfig.llm.defaultOllamaModel
        self.hasSeenOnboarding = d.bool(forKey: Key.hasSeenOnboarding)
        self.dailyGoalTarget = d.object(forKey: Key.dailyGoalTarget) as? Int ?? 3
        self.autoPlaySpeed = d.object(forKey: Key.autoPlaySpeed) as? Double ?? 3.0
        self.notificationsEnabled = d.object(forKey: Key.notificationsEnabled) as? Bool ?? false
        self.gestureHintShown = d.bool(forKey: Key.gestureHintShown)
        self.openingViewCounts = d.dictionary(forKey: Key.openingViewCounts) as? [String: Int] ?? [:]
        self.bestReviewStreak = d.integer(forKey: Key.bestReviewStreak)
        self.boardTheme = d.string(forKey: Key.boardTheme).flatMap { BoardTheme(rawValue: $0) } ?? .chessCom
        self.pieceStyle = d.string(forKey: Key.pieceStyle).flatMap { PieceStyle(rawValue: $0) } ?? .classic
        self.hasPickedFreeOpening = d.bool(forKey: Key.hasPickedFreeOpening)
        self.pickedFreeOpeningID = d.string(forKey: Key.pickedFreeOpeningID)

        // Daily goal: reset if date changed
        let today = Self.todayString
        if d.string(forKey: Key.dailyGoalProgress) != today {
            d.set(today, forKey: Key.dailyGoalProgress)
            d.set(0, forKey: Key.dailyGoalCount)
            self.dailyGoalCompleted = 0
        } else {
            self.dailyGoalCompleted = d.integer(forKey: Key.dailyGoalCount)
        }

        // Consecutive correct plays (stored as raw dictionary, same as SessionViewModel)
        self.consecutiveCorrectPlays = d.dictionary(forKey: Key.consecutiveCorrect) as? [String: Int] ?? [:]
    }

    // MARK: - Helpers

    private static var todayString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = .current
        return fmt.string(from: Date())
    }
}
