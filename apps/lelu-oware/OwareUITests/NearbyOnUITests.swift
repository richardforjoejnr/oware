import XCTest

/// Nearby play is on for everyone (2026-10-31): under More with no launch option, and no test
/// switch left in Settings.
final class NearbyOnUITests: XCTestCase {
    @MainActor
    func testPlayNearbyIsUnderMoreAndSettingsHasNoTestSwitch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reset-state", "--fast-animations"]
        app.launch()
        let more = app.buttons["btn-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        if !more.isHittable { app.swipeUp() }
        more.tap()
        XCTAssertTrue(app.buttons["btn-nearby"].waitForExistence(timeout: 10), "Play nearby is under More")
        let settings = app.buttons["btn-settings"]
        if !settings.isHittable { app.swipeUp() }
        settings.tap()
        XCTAssertTrue(app.switches["setting-usage-stats"].waitForExistence(timeout: 10))
        for _ in 0..<4 { app.swipeUp() }
        XCTAssertFalse(app.switches["setting-test-nearby"].exists)
        XCTAssertFalse(app.staticTexts["Test features"].exists)
    }
}
