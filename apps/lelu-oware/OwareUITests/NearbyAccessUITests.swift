import XCTest

/// Opening Play nearby with Local Network off, or Wi-Fi seemingly off: a message saying what to
/// do, and Start and Look for games greyed out (`--nearby-local-network-off`, `--nearby-wifi-off`
/// stand in for the phone's settings).
final class NearbyAccessUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func openNearby(_ extra: [String]) {
        app.launchArguments = ["--reset-state", "--fast-animations", "--rules=abapa"] + extra
        app.launch()
        let more = app.buttons["btn-more"]
        let nearby = app.buttons["btn-nearby"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        for _ in 0..<2 where !nearby.exists {
            if !more.isHittable { app.swipeUp() }
            more.tap()
            if nearby.waitForExistence(timeout: 6) { break }
        }
        if !nearby.isHittable { app.swipeUp() }
        nearby.tap()
        XCTAssertTrue(app.buttons["btn-start-nearby"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testLocalNetworkOffSaysHowToTurnItOnAndGreysOutTheButtons() throws {
        openNearby(["--nearby-local-network-off"])
        XCTAssertTrue(app.otherElements["nearby-local-network-off"].waitForExistence(timeout: 5)
                      || app.staticTexts["nearby-local-network-off"].exists)
        XCTAssertTrue(app.buttons["btn-open-settings"].exists)
        XCTAssertFalse(app.buttons["btn-start-nearby"].isEnabled)
        XCTAssertFalse(app.buttons["btn-look-nearby"].isEnabled)
        XCTAssertFalse(app.buttons["btn-try-anyway"].exists, "Local Network has to be turned on")
        XCTAssertFalse(app.buttons["btn-try-nearby"].exists, "no pretend player on offer")
    }

    @MainActor
    func testWiFiOffSaysToTurnItOnAndCanBeTriedAnyway() throws {
        openNearby(["--nearby-wifi-off"])
        XCTAssertTrue(app.otherElements["nearby-wifi-off"].waitForExistence(timeout: 5)
                      || app.staticTexts["nearby-wifi-off"].exists)
        XCTAssertFalse(app.buttons["btn-start-nearby"].isEnabled)
        XCTAssertFalse(app.buttons["btn-look-nearby"].isEnabled)
        let anyway = app.buttons["btn-try-anyway"]
        XCTAssertTrue(anyway.exists)
        anyway.tap()
        XCTAssertTrue(app.buttons["btn-start-nearby"].isEnabled)
        XCTAssertTrue(app.buttons["btn-look-nearby"].isEnabled)
        XCTAssertFalse(app.buttons["btn-try-anyway"].exists)
    }

    /// The pretend player (Ama) is only for the app's own tests: Play nearby does not offer it.
    @MainActor
    func testThereIsNoPretendPlayerToTry() throws {
        openNearby([])
        XCTAssertTrue(app.buttons["btn-nearby-help"].exists)
        XCTAssertFalse(app.buttons["btn-try-nearby"].exists)
        XCTAssertFalse(app.buttons["Try it with a pretend player"].exists)
    }

    @MainActor
    func testNothingIsGreyedOutWhenAllIsWell() throws {
        openNearby(["--nearby-demo"])
        XCTAssertTrue(app.buttons["btn-start-nearby"].isEnabled)
        XCTAssertTrue(app.buttons["btn-look-nearby"].isEnabled)
        XCTAssertFalse(app.buttons["btn-try-anyway"].exists)
    }
}
