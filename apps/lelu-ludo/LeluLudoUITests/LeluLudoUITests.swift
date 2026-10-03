import XCTest

/// The app end to end with scripted dice (`--dice=`), so every run plays the same game.
final class LeluLudoUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-state", "--fast"] + extra
        app.launch()
        return app
    }

    @MainActor
    func testRollASixBringATokenOutAndMoveIt() throws {
        // You: 6 (out), 4 (moves it). Computer: 2 (nothing out: passes). You again.
        let app = launch(["--dice=6,4,2,3", "--start-game"])
        let roll = app.buttons["btn-roll"]
        XCTAssertTrue(roll.waitForExistence(timeout: 5))
        roll.tap()
        let token = app.descendants(matching: .any)["token-red-0"]
        XCTAssertTrue(token.waitForExistence(timeout: 3))
        XCTAssertTrue(token.label.contains("in the yard"))
        token.tap()
        XCTAssertTrue(token.label.contains("0 squares from start"), token.label)
        roll.tap()
        token.tap()
        let moved = NSPredicate(format: "label CONTAINS '4 squares from start'")
        expectation(for: moved, evaluatedWith: token)
        waitForExpectations(timeout: 5)
        // The computer had its turn; it is yours again.
        let status = app.staticTexts["status"]
        expectation(for: NSPredicate(format: "label == 'Your roll'"), evaluatedWith: status)
        waitForExpectations(timeout: 5)
    }

    @MainActor
    func testPassAndPlayFromTheMenu() throws {
        let app = launch(["--dice=3"])
        let play = app.buttons["btn-pass-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        let roll = app.buttons["btn-roll"]
        XCTAssertTrue(roll.waitForExistence(timeout: 5))
        roll.tap()   // red: 3, nothing out, passes
        expectation(for: NSPredicate(format: "label CONTAINS 'Black'"), evaluatedWith: app.staticTexts["status"])
        waitForExpectations(timeout: 5)
        XCTAssertTrue(roll.isEnabled, "black rolls for themselves")
    }

    @MainActor
    func testAccessibilityAuditOnTheMenuAndTheBoard() throws {
        // Contrast and Dynamic Type are left out, as in Lelu Oware: they misfire on painted boards.
        let checks = XCUIAccessibilityAuditType.all.subtracting([.contrast, .dynamicType, .textClipped])
        let app = launch([])
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: checks)
        app.terminate()
        let game = launch(["--start-game"])
        XCTAssertTrue(game.buttons["btn-roll"].waitForExistence(timeout: 5))
        try game.performAccessibilityAudit(for: checks)
    }
}
