import XCTest

/// XCUITest suite — developer-owned UI regression tests run by `xcodebuild test` and CI.
/// Black-box end-to-end flows live in `.maestro/flows` (Maestro).
final class HomeScreenUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeScreenShowsTitleAndInitialSeedCount() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["home-seed-count"].label, "Seeds on board: 48")
    }
}
