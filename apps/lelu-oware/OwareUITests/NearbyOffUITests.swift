import XCTest

/// Nearby play is switched off for players for now (2026-11-11): not under More with no launch
/// option, and no test switch in Settings. Tests and Debug builds open it with `--nearby`.
final class NearbyOffUITests: XCTestCase {
    @MainActor
    func testPlayNearbyIsNotUnderMoreAndSettingsHasNoTestSwitch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reset-state", "--fast-animations"]
        app.launch()
        let more = app.buttons["btn-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        if !more.isHittable { app.swipeUp() }
        more.tap()
        XCTAssertTrue(app.buttons["btn-pass-play"].waitForExistence(timeout: 10), "the More rows are open")
        XCTAssertFalse(app.buttons["btn-nearby"].exists, "Play nearby is not on offer")
        let settings = app.buttons["btn-settings"]
        if !settings.isHittable { app.swipeUp() }
        settings.tap()
        XCTAssertTrue(app.switches["setting-usage-stats"].waitForExistence(timeout: 10))
        for _ in 0..<4 { app.swipeUp() }
        XCTAssertFalse(app.switches["setting-test-nearby"].exists)
        XCTAssertFalse(app.staticTexts["Test features"].exists)
    }
}
