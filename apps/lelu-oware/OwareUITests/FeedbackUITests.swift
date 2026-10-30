import XCTest

/// While tips are off (no Paid Apps Agreement yet), the home screen offers Feedback instead of
/// Support me, and Settings has no tip jar: nothing in the app can be bought.
final class FeedbackUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset-state", "--fast-animations"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testHomeOffersFeedbackNotSupportMe() throws {
        XCTAssertTrue(app.buttons["btn-feedback"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["btn-support"].exists, "no tip jar on the home screen")
    }

    @MainActor
    func testSettingsHasNoTipJar() throws {
        let more = app.buttons["btn-more"]
        let settings = app.buttons["btn-settings"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        for _ in 0..<2 where !settings.exists {
            if !more.isHittable { app.swipeUp() }
            more.tap()
            if settings.waitForExistence(timeout: 6) { break }
        }
        settings.tap()
        XCTAssertTrue(app.buttons["btn-game-center"].waitForExistence(timeout: 10))
        for _ in 0..<4 { app.swipeUp() }
        XCTAssertTrue(app.links["link-support"].exists || app.buttons["link-support"].exists, "scrolled to the end of Settings")
        XCTAssertFalse(app.buttons["btn-tip-jar"].exists, "no tip jar in Settings")
    }
}
