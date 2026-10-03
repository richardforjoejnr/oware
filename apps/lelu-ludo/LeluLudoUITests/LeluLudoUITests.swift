import XCTest

final class LeluLudoUITests: XCTestCase {
    func testHomeShowsTitle() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
    }
}
