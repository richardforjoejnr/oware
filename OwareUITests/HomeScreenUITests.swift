import XCTest

/// XCUITest suite — developer-owned UI regression tests run by `xcodebuild test` and CI.
/// Black-box end-to-end flows live in `.maestro/flows` (Maestro) and `e2e/` (TypeScript).
final class HomeScreenUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset-state", "--fast-animations"]
        app.launch()
    }

    @MainActor
    func testHomeScreenShowsTitleAndModes() throws {
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["btn-play-ai"].exists)
        XCTAssertTrue(app.buttons["btn-pass-play"].exists)
        XCTAssertFalse(app.buttons["btn-continue"].exists, "no saved game after --reset-state")
    }

    @MainActor
    func testPassAndPlaySowsSeedsCounterClockwise() throws {
        app.buttons["btn-pass-play"].tap()
        let a1 = app.buttons["house-A1"]
        XCTAssertTrue(a1.waitForExistence(timeout: 5))
        XCTAssertEqual(a1.value as? String, "4 seeds")
        XCTAssertEqual(app.staticTexts["turn-indicator"].label, "A to move")

        a1.tap()

        let a2 = app.buttons["house-A2"]
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "5 seeds"), object: a2)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed)
        XCTAssertEqual(a1.value as? String, "0 seeds")
        XCTAssertEqual(app.buttons["house-A5"].value as? String, "5 seeds")
        XCTAssertEqual(app.buttons["house-A6"].value as? String, "4 seeds")
        XCTAssertEqual(app.staticTexts["turn-indicator"].label, "B to move")
    }

    @MainActor
    func testUndoRestoresThePreviousPosition() throws {
        app.buttons["btn-pass-play"].tap()
        let a1 = app.buttons["house-A1"]
        XCTAssertTrue(a1.waitForExistence(timeout: 5))
        a1.tap()
        let undo = app.buttons["btn-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: undo)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 5), .completed)
        undo.tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "4 seeds"), object: a1)
        XCTAssertEqual(XCTWaiter().wait(for: [restored], timeout: 5), .completed)
        XCTAssertEqual(app.staticTexts["turn-indicator"].label, "A to move")
    }

    @MainActor
    func testPlayingAgainstTheAIGetsAReply() throws {
        app.buttons["level-beginner"].tap()
        app.buttons["btn-play-ai"].tap()
        let a3 = app.buttons["house-A3"]
        XCTAssertTrue(a3.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["turn-indicator"].label, "Your move")
        a3.tap()
        // The AI replies within its think time; afterwards it is our move again and north has moved.
        let yourMove = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Your move"), object: app.staticTexts["turn-indicator"])
        XCTAssertEqual(XCTWaiter().wait(for: [yourMove], timeout: 10), .completed)
        let northEmptied = (1...6).contains { app.buttons["house-B\($0)"].value as? String == "0 seeds" }
        XCTAssertTrue(northEmptied, "the AI should have scooped one of its houses")
    }
}
