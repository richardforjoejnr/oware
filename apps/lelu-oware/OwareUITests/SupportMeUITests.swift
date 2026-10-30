import XCTest

/// "Support me" (the tip jar) from the home screen. App Review (30 Oct 2026) found tips that never
/// loaded; the jar must show the tips, or a plain message with Try again, never an empty sheet.
final class SupportMeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ extra: [String] = []) {
        app.launchArguments = ["--reset-state", "--fast-animations"] + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 10))
    }

    /// Scrolls the home menu until Support me can be tapped, then opens the jar.
    private func openSupportFromHome() {
        let support = app.buttons["btn-support"]
        XCTAssertTrue(support.waitForExistence(timeout: 10), "Support me is on the home screen, not only in Settings")
        for _ in 0..<6 where !support.isHittable { app.swipeUp() }
        XCTAssertTrue(support.isHittable)
        support.tap()
        XCTAssertTrue(app.staticTexts["tip-jar-title"].waitForExistence(timeout: 15))
    }

    @MainActor
    func testSupportMeIsOnTheHomeScreenWithoutOpeningMore() throws {
        launch()
        XCTAssertTrue(app.buttons["btn-support"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["btn-settings"].exists, "More is still closed")
    }

    @MainActor
    func testSupportMeShowsTheTipsFromHome() throws {
        launch()
        openSupportFromHome()
        // Products come from Tips.storekit, the scheme's local store.
        XCTAssertTrue(app.buttons["tip-0"].waitForExistence(timeout: 20), "the tips load")
        XCTAssertTrue(app.buttons["tip-1"].exists)
        XCTAssertTrue(app.buttons["tip-2"].exists)
        XCTAssertFalse(app.buttons["tip-3"].exists, "only the three tips are offered")
        XCTAssertFalse(app.buttons["tip-jar-retry"].exists)
    }

    @MainActor
    func testTipsThatCannotLoadSayWhyAndOfferTryAgain() throws {
        launch(["--tips-unavailable"])
        openSupportFromHome()
        let retry = app.buttons["tip-jar-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 20), "a failed load offers Try again")
        let status = app.staticTexts["tip-jar-status"]
        XCTAssertTrue(status.exists)
        XCTAssertFalse(status.label.isEmpty)
        XCTAssertFalse(status.label.lowercased().contains("not available"))
        retry.tap()
        XCTAssertTrue(retry.waitForExistence(timeout: 20), "still offered after another failed try")
        XCTAssertFalse(app.buttons["tip-0"].exists)
    }
}
