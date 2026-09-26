import XCTest

/// The board and the menu must work sideways too: rotate, check the pieces are there and
/// keep screenshots of both so a broken landscape layout is visible in the test report.
final class LandscapeUITests: XCTestCase {
    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testBoardInLandscapeHasAllHousesAndBothStores() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-state", "--fast-animations", "--start-game", "--demo-stores=12"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["house-A1"].waitForExistence(timeout: 5))
        for notation in ["A1", "A6", "B1", "B6"] {
            let house = app.buttons["house-\(notation)"]
            XCTAssertTrue(house.exists, "house \(notation) missing in landscape")
            XCTAssertGreaterThan(house.frame.width, 44, "house \(notation) too small to tap in landscape")
        }
        for store in ["store-A", "store-B"] {
            let element = app.otherElements[store]
            XCTAssertTrue(element.exists, "\(store) missing in landscape")
            XCTAssertGreaterThan(element.frame.height, 80, "\(store) collapsed in landscape")
        }
        // The two rows sit inside the screen, one above the other.
        let a1 = app.buttons["house-A1"].frame, b6 = app.buttons["house-B6"].frame
        XCTAssertGreaterThan(a1.midY, b6.midY, "south row should be below the north row in landscape")
        snap(app, "board-landscape")
    }

    func testMenuInLandscapeShowsTitleAndAllTiles() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-state", "--fast-animations"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["home-title"].isHittable, "title scrolled off screen in landscape")
        for id in ["btn-play-ai", "btn-journey", "btn-learn", "btn-more"] {
            let tile = app.buttons[id]
            XCTAssertTrue(tile.exists && tile.isHittable, "\(id) not visible in landscape")
            XCTAssertGreaterThanOrEqual(tile.frame.height, 56, "\(id) shorter than 56 pt")
        }
        snap(app, "menu-landscape")
    }
}
