# Screenshot Collection XCUITest Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an XCUITest target that collects 10 App Store screenshots in a single test run, independent of Claude API.

**Architecture:** Add a `ChessCoachUITests` target with launch argument handling. The app reads `ProcessInfo` arguments to load debug state presets and skip animations. Each test method captures one screen with `XCTAttachment`.

**Tech Stack:** XCUITest, XcodeGen (project.yml), Swift 6.0

---

### Task 1: Add UI Test Target to project.yml

**Files:**
- Modify: `project.yml:45-56`

**Step 1: Add the ChessCoachUITests target**

Add after the `ChessCoachTests` target definition:

```yaml
  ChessCoachUITests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - ChessCoachUITests
    dependencies:
      - target: ChessCoach
    settings:
      base:
        SWIFT_VERSION: "6.0"
        GENERATE_INFOPLIST_FILE: YES
        TEST_TARGET_NAME: ChessCoach
```

**Step 2: Create the source directory**

Run: `mkdir -p ChessCoachUITests`

**Step 3: Regenerate the Xcode project**

Run: `cd /Users/mark/dev/chess-coach && xcodegen generate`
Expected: "Generated project ChessCoach.xcodeproj"

**Step 4: Commit**

```bash
git add project.yml ChessCoachUITests
git commit -m "feat: add ChessCoachUITests target for screenshot collection"
```

---

### Task 2: Add Launch Argument Handling to the App

**Files:**
- Modify: `ChessCoach/App/ChessCoachApp.swift`
- Modify: `ChessCoach/App/ContentView.swift`

**Step 1: Add screenshot mode detection in ChessCoachApp.swift**

Add a static helper and apply it in `init()`:

```swift
import SwiftUI

@main
struct ChessCoachApp: App {
    @State private var subscriptionService = SubscriptionService()
    @State private var appSettings = AppSettings()
    @State private var appServices = AppServices()
    @State private var tokenService = TokenService()
    @State private var modelDownloadService = ModelDownloadService()

    static let isScreenshotMode = ProcessInfo.processInfo.arguments.contains("--screenshot-mode")

    init() {
        // One-time migration: clear review items saved with wrong FENs (pre-fix)
        let migrationKey = "reviewItemsFenFix_v1"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            PersistenceService.shared.saveReviewItems([])
            UserDefaults.standard.set(true, forKey: migrationKey)
        }

        if Self.isScreenshotMode {
            // Disable animations for fast, deterministic screenshots
            UIView.setAnimationsEnabled(false)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(subscriptionService)
                .environment(appSettings)
                .environment(appServices)
                .environment(tokenService)
                .environment(modelDownloadService)
        }
    }
}
```

**Step 2: Skip LLM/engine loading and beta welcome in screenshot mode**

In `ContentView.swift`, modify `performStartup()` to skip slow loading when in screenshot mode:

```swift
private func performStartup() async {
    let screenshotMode = ChessCoachApp.isScreenshotMode

    // Step 1: Data migration
    updateStep("Checking data...", progress: 0.05)
    _ = PersistenceService.shared
    await Task.yield()

    // Step 2: Load opening database
    updateStep("Loading openings...", progress: 0.1)
    _ = OpeningDatabase.shared
    await Task.yield()

    // Step 3: Check subscription
    updateStep("Checking subscription...", progress: 0.15)
    if !screenshotMode {
        do {
            try await subscriptionService.loadProduct()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    await Task.yield()

    // Step 4: Load user progress
    updateStep("Loading your progress...", progress: 0.2)
    _ = PersistenceService.shared.loadAllMastery()
    await Task.yield()

    // Step 5: Start chess engine (skip in screenshot mode)
    if !screenshotMode {
        updateStep("Starting chess engine...", progress: 0.3)
        await appServices.startStockfish()

        // Step 6: Load coaching model (skip for free tier users)
        if subscriptionService.hasAI {
            updateStep("Loading coaching model...", progress: 0.5)
            await appServices.startLLM()
        }
    }

    // Step 7: Ready
    updateStep("Ready!", progress: 1.0)

    if !screenshotMode {
        try? await Task.sleep(for: .milliseconds(300))
    }

    withAnimation {
        isReady = true
    }

    // Show beta welcome every launch after onboarding (skip in screenshot mode)
    if settings.hasSeenOnboarding && !screenshotMode {
        try? await Task.sleep(for: .milliseconds(600))
        showBetaWelcome = true
    }
}
```

**Step 3: Verify the app still builds**

Run: `cd /Users/mark/dev/chess-coach && xcodebuild build -project ChessCoach.xcodeproj -scheme ChessCoach -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -quiet`

**Step 4: Commit**

```bash
git add ChessCoach/App/ChessCoachApp.swift ChessCoach/App/ContentView.swift
git commit -m "feat: add screenshot mode launch argument for fast UI test startup"
```

---

### Task 3: Write the Screenshot Test Class

**Files:**
- Create: `ChessCoachUITests/ScreenshotTests.swift`

**Step 1: Write the screenshot test file**

```swift
import XCTest

final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--screenshot-mode"]
    }

    // MARK: - Helpers

    private func saveScreenshot(named name: String) {
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    private func launchFresh() {
        app.launchArguments += ["--reset-onboarding"]
        app.launch()
    }

    private func launchWithState(_ state: String) {
        app.launchArguments += ["--debug-state", state]
        app.launch()
    }

    // MARK: - Screenshot Tests

    func test01_Onboarding() {
        launchFresh()
        // Wait for onboarding to appear
        let skipButton = app.buttons["Skip introduction"]
        _ = waitForElement(skipButton)
        sleep(1) // Let animations settle
        saveScreenshot(named: "01-onboarding-welcome")
    }

    func test02_HomeScreen() {
        launchWithState("proTrainerProgress")
        let home = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'chess'")).firstMatch
        _ = waitForElement(home, timeout: 15)
        sleep(1)
        saveScreenshot(named: "02-home-screen")
    }

    func test03_OpeningBrowser() {
        launchWithState("proMidway")
        sleep(2)
        // Tap "Browse Openings" chip or navigate to browser
        let browseButton = app.buttons["Browse Openings"]
        if waitForElement(browseButton, timeout: 10) {
            browseButton.tap()
            sleep(1)
            saveScreenshot(named: "03-opening-browser")
        }
    }

    func test04_OpeningDetail() {
        launchWithState("proMidway")
        sleep(2)
        let browseButton = app.buttons["Browse Openings"]
        if waitForElement(browseButton, timeout: 10) {
            browseButton.tap()
            sleep(1)
            // Tap Italian Game
            let italian = app.staticTexts["Italian Game"]
            if waitForElement(italian, timeout: 5) {
                italian.tap()
                sleep(1)
                saveScreenshot(named: "04-opening-detail-italian")
            }
        }
    }

    func test05_LearningPlan() {
        launchWithState("italianLayer1")
        sleep(2)
        // Navigate to active opening detail
        // The hero card should show Italian Game - tap it
        let heroCard = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Italian'")).firstMatch
        if waitForElement(heroCard, timeout: 10) {
            heroCard.tap()
            sleep(1)
            // Tap Layer 1 (Understand Plan)
            let layer1 = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Understand'")).firstMatch
            if waitForElement(layer1, timeout: 5) {
                layer1.tap()
                sleep(2)
                saveScreenshot(named: "05-learning-plan")
            }
        }
    }

    func test06_PuzzleMode() {
        launchWithState("proMidway")
        sleep(2)
        let puzzleButton = app.buttons["Puzzles"]
        if waitForElement(puzzleButton, timeout: 10) {
            puzzleButton.tap()
            sleep(3) // Wait for puzzle to load
            saveScreenshot(named: "06-puzzle-mode")
        }
    }

    func test07_TrainerSetup() {
        launchWithState("proTrainerProgress")
        sleep(2)
        let trainerButton = app.buttons["Trainer"]
        if waitForElement(trainerButton, timeout: 10) {
            trainerButton.tap()
            sleep(1)
            saveScreenshot(named: "07-trainer-setup")
        }
    }

    func test08_Settings() {
        launchWithState("proMidway")
        sleep(2)
        let settingsButton = app.buttons["Settings"]
        if waitForElement(settingsButton, timeout: 10) {
            settingsButton.tap()
            sleep(1)
            saveScreenshot(named: "08-settings")
        }
    }

    func test09_SettingsAICoach() {
        launchWithState("proMidway")
        sleep(2)
        let settingsButton = app.buttons["Settings"]
        if waitForElement(settingsButton, timeout: 10) {
            settingsButton.tap()
            sleep(1)
            // Scroll down to AI Coach section
            app.swipeUp()
            sleep(1)
            saveScreenshot(named: "09-settings-ai-coach")
        }
    }

    func test10_TrainerBotGame() {
        launchWithState("proTrainerProgress")
        sleep(2)
        let trainerButton = app.buttons["Trainer"]
        if waitForElement(trainerButton, timeout: 10) {
            trainerButton.tap()
            sleep(1)
            // Tap Play button to start a game
            let playButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Play'")).firstMatch
            if waitForElement(playButton, timeout: 5) {
                playButton.tap()
                sleep(3) // Wait for game to set up
                saveScreenshot(named: "10-trainer-game")
            }
        }
    }
}
```

**Step 2: Verify it compiles**

Run: `cd /Users/mark/dev/chess-coach && xcodebuild build-for-testing -project ChessCoach.xcodeproj -scheme ChessCoach -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -quiet`

**Step 3: Commit**

```bash
git add ChessCoachUITests/ScreenshotTests.swift
git commit -m "feat: add screenshot collection UI tests for 10 app screens"
```

---

### Task 4: Add Debug State Launch Argument Handling

The UI tests pass `--debug-state <stateName>` to configure the app. We need to handle this in the app.

**Files:**
- Modify: `ChessCoach/App/ChessCoachApp.swift`

**Step 1: Add debug state argument parsing**

Add to `ChessCoachApp.init()`, after the migration block and inside the screenshot mode check:

```swift
#if DEBUG
if Self.isScreenshotMode {
    let args = ProcessInfo.processInfo.arguments
    if let stateIndex = args.firstIndex(of: "--debug-state"),
       stateIndex + 1 < args.count {
        let stateName = args[stateIndex + 1]
        ScreenshotStateLoader.loadState(stateName)
    }
    if args.contains("--reset-onboarding") {
        UserDefaults.standard.set(false, forKey: AppSettings.Key.hasSeenOnboarding)
    }
}
#endif
```

**Step 2: Create ScreenshotStateLoader**

**Files:**
- Create: `ChessCoachUITests/ScreenshotStateLoader.swift`

Wait — this code needs to run in the app target, not the test target. Create it in the app under a DEBUG guard.

**Files:**
- Create: `ChessCoach/App/ScreenshotStateLoader.swift`

```swift
#if DEBUG
import Foundation

/// Loads debug states from launch arguments for screenshot UI tests.
/// Reuses the same state setup logic as DebugStateView presets.
enum ScreenshotStateLoader {
    static func loadState(_ name: String) {
        // Nuclear reset first
        nuclearReset()

        let settings = UserDefaults.standard
        settings.set(true, forKey: AppSettings.Key.hasSeenOnboarding)
        settings.set(true, forKey: AppSettings.Key.hasPickedFreeOpening)
        settings.set("italian", forKey: AppSettings.Key.pickedFreeOpeningID)
        settings.set(true, forKey: "has_seen_home_tour")
        settings.set(true, forKey: "has_seen_beta_welcome")

        switch name {
        case "proMidway":
            settings.set(SubscriptionTier.pro.rawValue, forKey: AppSettings.Key.debugTierOverride)
            settings.set(1200, forKey: AppSettings.Key.userELO)
            loadProMidwayMastery()

        case "proTrainerProgress":
            settings.set(SubscriptionTier.pro.rawValue, forKey: AppSettings.Key.debugTierOverride)
            settings.set(1200, forKey: AppSettings.Key.userELO)
            loadProTrainerProgress()

        case "italianLayer1":
            settings.set(600, forKey: AppSettings.Key.userELO)
            let mastery = OpeningMastery(openingID: "italian")
            PersistenceService.shared.saveMastery(mastery)

        case "freshInstall":
            settings.set(false, forKey: AppSettings.Key.hasSeenOnboarding)

        default:
            break
        }
    }

    private static func nuclearReset() {
        let defaults = UserDefaults.standard
        let allKeys = [
            "chess_coach_mastery", "chess_coach_progress", "chess_coach_streak",
            "chess_coach_review_items", "chess_coach_mistakes", "chess_coach_speed_runs",
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
}
#endif
```

**Step 3: Verify build**

Run: `cd /Users/mark/dev/chess-coach && xcodebuild build -project ChessCoach.xcodeproj -scheme ChessCoach -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -quiet`

**Step 4: Commit**

```bash
git add ChessCoach/App/ScreenshotStateLoader.swift ChessCoach/App/ChessCoachApp.swift
git commit -m "feat: add ScreenshotStateLoader for debug state via launch arguments"
```

---

### Task 5: Run the Tests and Extract Screenshots

**Step 1: Boot iPhone 16 Pro Max simulator**

Run: `xcrun simctl boot "iPhone 16 Pro Max" 2>/dev/null; xcrun simctl list devices booted`

**Step 2: Regenerate Xcode project (to pick up new files)**

Run: `cd /Users/mark/dev/chess-coach && xcodegen generate`

**Step 3: Run the screenshot tests**

Run: `cd /Users/mark/dev/chess-coach && xcodebuild test -project ChessCoach.xcodeproj -scheme ChessCoach -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:ChessCoachUITests -resultBundlePath /tmp/screenshots.xcresult 2>&1 | tail -30`

**Step 4: Extract screenshots from xcresult**

Run:
```bash
cd /Users/mark/dev/chess-coach/screenshots/appstore
xcresulttool get test-results attachments --path /tmp/screenshots.xcresult --output-path .
```

Or manually: open `/tmp/screenshots.xcresult` in Xcode, find each attachment, and export.

**Step 5: Verify screenshots are correct resolution**

Run: `for f in /Users/mark/dev/chess-coach/screenshots/appstore/*.png; do echo "$(basename "$f"): $(sips -g pixelWidth -g pixelHeight "$f" 2>/dev/null | grep pixel | awk '{print $2}' | tr '\n' 'x' | sed 's/x$//')"; done`

Expected: All should be 1320x2868 (iPhone 16 Pro Max)

**Step 6: Commit final screenshots**

```bash
git add screenshots/appstore/
git commit -m "feat: add App Store screenshots from automated UI tests"
```

---

### Task 6: Fix and Iterate

This task is intentionally open-ended. After the first run:

1. Some tests may fail if accessibility labels don't match — fix by inspecting `app.debugDescription` in failing tests
2. Some screenshots may not show the ideal state — adjust `ScreenshotStateLoader` presets
3. Some navigation paths may need adjustment — update element queries

**Debugging tips:**
- Add `print(app.debugDescription)` before a failing tap to see the element tree
- Use `app.buttons.allElementsBoundByIndex.forEach { print($0.label) }` to list all buttons
- Increase `sleep()` durations if the UI hasn't settled

---

## Post-Screenshots: TestFlight

Once screenshots are collected, follow the existing `screenshots/TESTFLIGHT_GUIDE.md` step by step. Key steps that need Xcode interaction:

1. Verify signing (Xcode > target > Signing & Capabilities)
2. Archive (Product > Archive with "Any iOS Device" selected)
3. Upload to App Store Connect (Organizer > Distribute App)
4. Create app record in App Store Connect
5. Set up TestFlight groups and invite testers
