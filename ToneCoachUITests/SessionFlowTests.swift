import XCTest

final class SessionFlowTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Skip onboarding for UI tests
        app.launchArguments += ["-hasCompletedOnboarding", "true"]
        app.launch()
    }

    func testStartAndStopSession() throws {
        // Verify we're on the Practice tab
        let startButton = app.buttons["Start Session"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5),
                      "Start Session button should exist on the Practice screen")

        // Start a session
        startButton.tap()

        // Verify recording state — End button should appear
        let endButton = app.buttons["End"]
        XCTAssertTrue(endButton.waitForExistence(timeout: 3),
                      "End button should appear after starting")

        // Wait a moment for some data to accumulate
        sleep(2)

        // Stop the session
        endButton.tap()

        // Verify summary appears
        let sessionComplete = app.staticTexts["Session Complete"]
        XCTAssertTrue(sessionComplete.waitForExistence(timeout: 5),
                      "Session summary should appear after stopping")

        // Verify share button exists
        let shareButton = app.buttons["Share Result"]
        XCTAssertTrue(shareButton.exists, "Share button should be visible in summary")

        // Verify done button returns to idle
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.exists, "Done button should be visible")
        doneButton.tap()

        // Should be back to idle state
        XCTAssertTrue(startButton.waitForExistence(timeout: 3),
                      "Should return to idle state with Start Session button")
    }

    func testTabNavigation() throws {
        // Practice tab should be selected by default
        let practiceTab = app.tabBars.buttons["Practice"]
        XCTAssertTrue(practiceTab.exists)

        // Navigate to History
        let historyTab = app.tabBars.buttons["History"]
        historyTab.tap()
        let historyTitle = app.navigationBars["History"]
        XCTAssertTrue(historyTitle.waitForExistence(timeout: 3))

        // Navigate to Settings
        let settingsTab = app.tabBars.buttons["Settings"]
        settingsTab.tap()
        let settingsTitle = app.navigationBars["Settings"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 3))
    }
}
