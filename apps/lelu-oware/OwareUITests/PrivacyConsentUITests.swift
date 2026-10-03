import XCTest

/// App Review 5.1: usage stats are asked for once, after a finished game, and the privacy policy is
/// reachable inside the app.
final class PrivacyConsentUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor private func launch() {
        app = XCUIApplication()
        app.launchArguments = ["--reset-state", "--fast-animations", "--rules=abapa", "--ask-usage-stats"]
        app.launch()
    }

    @MainActor private func resignAGame() {
        let flag = app.buttons["btn-end-game"]
        XCTAssertTrue(flag.waitForExistence(timeout: 5))
        flag.tap()
        let resign = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Resign'")).firstMatch
        XCTAssertTrue(resign.waitForExistence(timeout: 3))
        resign.tap()
        XCTAssertTrue(app.staticTexts["game-over-title"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testUsageStatsAreAskedOnceAfterTheFirstGame() throws {
        launch()
        XCTAssertTrue(app.buttons["btn-play-ai"].waitForExistence(timeout: 10))
        app.buttons["btn-play-ai"].tap()
        resignAGame()
        let no = app.buttons["btn-usage-stats-no"]
        XCTAssertTrue(no.waitForExistence(timeout: 3), "asked after the first game")
        XCTAssertTrue(app.buttons["btn-usage-stats-yes"].exists)
        no.tap()
        XCTAssertFalse(no.waitForExistence(timeout: 1), "the question goes once answered")

        app.buttons["btn-play-again"].tap()
        resignAGame()
        XCTAssertFalse(app.buttons["btn-usage-stats-no"].waitForExistence(timeout: 1), "never asked twice")
    }

    @MainActor
    func testSettingsLinkThePrivacyPolicyAndSupport() throws {
        launch()
        let more = app.buttons["btn-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        if !more.isHittable { app.swipeUp() }
        more.tap()
        let settings = app.buttons["btn-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 6))
        settings.tap()
        let stats = app.switches["setting-usage-stats"]
        XCTAssertTrue(stats.waitForExistence(timeout: 5))
        XCTAssertEqual(stats.value as? String, "0", "off until the player agrees")
        // By identifier, whatever the type: SwiftUI's Link is a link on some iOS versions, a button on others.
        let privacy = app.descendants(matching: .any)["link-privacy"]
        for _ in 0..<4 where !(privacy.exists && privacy.isHittable) { app.swipeUp() }
        XCTAssertTrue(privacy.waitForExistence(timeout: 3), "privacy policy reachable in the app")
        XCTAssertTrue(app.descendants(matching: .any)["link-support"].exists)
    }
}
