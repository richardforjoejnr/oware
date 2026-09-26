import XCTest

final class __NAME__UITests: XCTestCase {
    func testHomeShowsTitle() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
    }
}
