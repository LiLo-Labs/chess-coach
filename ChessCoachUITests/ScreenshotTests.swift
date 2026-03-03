import XCTest

@MainActor
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

    private func waitFor(_ element: XCUIElement, timeout: TimeInterval = 10) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "Timed out waiting for: \(element)")
    }

    private func launchFresh() {
        app.launchArguments += ["--reset-onboarding"]
        app.launch()
    }

    private func launchWithState(_ state: String) {
        app.launchArguments += ["--debug-state", state]
        app.launch()
    }

    /// Find element matching a predicate on label
    private func element(
        type: XCUIElement.ElementType = .button,
        labelContains text: String
    ) -> XCUIElement {
        let query: XCUIElementQuery
        switch type {
        case .button: query = app.buttons
        case .staticText: query = app.staticTexts
        default: query = app.descendants(matching: type)
        }
        return query.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    // MARK: - Screenshot Tests

    func test01_Onboarding() {
        launchFresh()
        // Wait for onboarding crown/title
        let title = app.staticTexts["ChessCoach"]
        waitFor(title)
        sleep(1)
        saveScreenshot(named: "01-onboarding-welcome")
    }

    func test02_HomeScreen() {
        launchWithState("proTrainerProgress")
        // Wait for home to load - look for the greeting or app title
        let greeting = element(type: .staticText, labelContains: "chess")
        waitFor(greeting, timeout: 15)
        sleep(1)
        saveScreenshot(named: "02-home-screen")
    }

    func test03_OpeningBrowser() {
        launchWithState("proMidway")
        sleep(2)
        let browseButton = element(labelContains: "Browse")
        waitFor(browseButton)
        browseButton.tap()
        sleep(1)
        saveScreenshot(named: "03-opening-browser")
    }

    func test04_OpeningDetail() {
        launchWithState("proMidway")
        sleep(2)
        let browseButton = element(labelContains: "Browse")
        waitFor(browseButton)
        browseButton.tap()
        sleep(1)
        // Search for Italian Game since it may not be visible in initial list
        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 3) {
            searchField.tap()
            searchField.typeText("Italian")
            sleep(1)
        } else {
            // Try scrolling to find it
            app.swipeUp()
            sleep(1)
        }
        let italian = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Italian'")).firstMatch
        waitFor(italian)
        italian.tap()
        sleep(1)
        saveScreenshot(named: "04-opening-detail-italian")
    }

    func test05_LearningPlan() {
        launchWithState("italianLayer1")
        sleep(2)
        // Hero card contains the opening name - tap it
        let heroCard = element(labelContains: "Italian")
        waitFor(heroCard)
        heroCard.tap()
        sleep(1)
        // Dismiss concept intro if it appears
        let gotIt = app.buttons["Got It"]
        if gotIt.waitForExistence(timeout: 2) {
            gotIt.tap()
            sleep(1)
        }
        // Scroll down to reveal the learning journey layers
        app.swipeUp()
        sleep(1)
        // Capture the opening detail with learning journey visible
        saveScreenshot(named: "05-learning-journey")
    }

    func test06_PuzzleMode() {
        launchWithState("proMidway")
        sleep(2)
        // Accessibility label is "Puzzles, Tactics training"
        let puzzleButton = element(labelContains: "Puzzles")
        waitFor(puzzleButton)
        puzzleButton.tap()
        sleep(3)
        saveScreenshot(named: "06-puzzle-mode")
    }

    func test07_TrainerSetup() {
        launchWithState("proTrainerProgress")
        sleep(2)
        // Accessibility label is "Trainer, Play a full game"
        let trainerButton = element(labelContains: "Trainer")
        waitFor(trainerButton)
        trainerButton.tap()
        sleep(1)
        saveScreenshot(named: "07-trainer-setup")
    }

    func test08_Settings() {
        launchWithState("proMidway")
        sleep(2)
        let settingsButton = app.buttons["Settings"]
        waitFor(settingsButton)
        settingsButton.tap()
        sleep(1)
        saveScreenshot(named: "08-settings")
    }

    func test09_SettingsAICoach() {
        launchWithState("proMidway")
        sleep(2)
        let settingsButton = app.buttons["Settings"]
        waitFor(settingsButton)
        settingsButton.tap()
        sleep(1)
        app.swipeUp()
        sleep(1)
        saveScreenshot(named: "09-settings-ai-coach")
    }

    func test10_TrainerBotGame() {
        launchWithState("proTrainerProgress")
        sleep(2)
        let trainerButton = element(labelContains: "Trainer")
        waitFor(trainerButton)
        trainerButton.tap()
        sleep(1)
        // Button is "Play vs [BotName]"
        let playButton = element(labelContains: "Play vs")
        waitFor(playButton)
        playButton.tap()
        sleep(3)
        saveScreenshot(named: "10-trainer-game")
    }
}
