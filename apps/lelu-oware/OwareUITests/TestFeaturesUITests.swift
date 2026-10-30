import XCTest

/// Settings ▸ Test features ▸ Nearby play (TestFlight and Xcode builds) shows Play nearby under
/// More while nearby play's own switch is still off.
final class TestFeaturesUITests: XCTestCase {
    @MainActor
    func testTheTestSwitchShowsPlayNearby() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reset-state", "--fast-animations"]
        app.launch()
        let more = app.buttons["btn-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        if !more.isHittable { app.swipeUp() }
        more.tap()
        let settings = app.buttons["btn-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["btn-nearby"].exists, "hidden until the test switch is on")
        if !settings.isHittable { app.swipeUp() }
        settings.tap()

        let toggle = app.switches["setting-test-nearby"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        for _ in 0..<5 where !toggle.isHittable { app.swipeUp() }
        // The switch itself, at the right: tapping the middle lands on the label.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")

        // Kept across launches, like any setting.
        app.terminate()
        app.launchArguments = ["--fast-animations"]
        app.launch()
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        if !more.isHittable { app.swipeUp() }
        more.tap()
        let nearby = app.buttons["btn-nearby"]
        XCTAssertTrue(nearby.waitForExistence(timeout: 10), "Play nearby is under More")
    }
}
