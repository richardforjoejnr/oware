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

    /// The home screen shows one primary action; the rest is behind "More".
    private func openMore() {
        let more = app.buttons["btn-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        if !app.buttons["btn-settings"].exists { more.tap() }
        XCTAssertTrue(app.buttons["btn-settings"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testHomeScreenShowsOnePrimaryActionAndHidesTheRest() throws {
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["btn-play-ai"].exists)
        XCTAssertTrue(app.buttons["btn-journey"].exists)
        XCTAssertTrue(app.buttons["btn-learn"].exists, "first launch offers the lesson")
        XCTAssertFalse(app.buttons["btn-pass-play"].exists, "secondary modes are hidden until More is opened")
        XCTAssertFalse(app.buttons["btn-continue"].exists, "no saved game after --reset-state")
        openMore()
        XCTAssertTrue(app.buttons["btn-pass-play"].exists)
        XCTAssertTrue(app.buttons["btn-puzzles"].exists)
        XCTAssertTrue(app.buttons["btn-heritage"].exists)
    }

    @MainActor
    func testPassAndPlaySowsSeedsCounterClockwise() throws {
        openMore()
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
        openMore()
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
    func testTutorialFirstMoveStepAdvances() throws {
        app.buttons["btn-learn"].tap()
        XCTAssertTrue(app.staticTexts["turn-indicator"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["turn-indicator"].label.hasPrefix("Welcome"))
        app.buttons["btn-next-step"].tap()
        // Step 2 asks for A3; a different house is refused with a hint.
        app.buttons["house-A1"].tap()
        XCTAssertTrue(app.staticTexts["hint"].waitForExistence(timeout: 3))
        app.buttons["house-A3"].tap()
        XCTAssertTrue(app.staticTexts["tutorial-after"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["btn-next-step"].exists)
    }

    @MainActor
    func testSolvingTheDailyRiddleMarksItSolved() throws {
        openMore()
        app.buttons["btn-puzzles"].tap()
        XCTAssertTrue(app.staticTexts["puzzles-title"].waitForExistence(timeout: 5))
        // Open the first capture-in-one riddle and read its answer from the goal text position:
        // we brute-force by tapping houses until the solved state appears (wrong taps do not change the board).
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'puzzle-captureInOne-'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        XCTAssertTrue(app.staticTexts["puzzle-goal"].waitForExistence(timeout: 5))
        var solved = false
        for house in 1...6 where !solved {
            let button = app.buttons["house-A\(house)"]
            if button.exists, button.value as? String != "0 seeds" {
                button.tap()
                let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "Ayekoo"), object: app.staticTexts["turn-indicator"])
                solved = XCTWaiter().wait(for: [done], timeout: 6) == .completed
            }
        }
        XCTAssertTrue(solved, "one of the six houses must be the solution")
        XCTAssertTrue(app.buttons["btn-all-puzzles"].waitForExistence(timeout: 5))
        app.buttons["btn-all-puzzles"].tap()
        XCTAssertTrue(app.staticTexts["puzzles-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label ENDSWITH 'solved'")).firstMatch.exists)
    }

    @MainActor
    func testJourneyOpensAndFirstMatchStarts() throws {
        app.buttons["btn-journey"].tap()
        XCTAssertTrue(app.staticTexts["journey-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["journey-stars"].label, "0 ★")
        let kofi = app.buttons["opponent-kumasi-1"]
        XCTAssertTrue(kofi.exists)
        XCTAssertFalse(app.buttons["opponent-bonwire-1"].exists, "chapter 2 is locked until Kumasi is beaten")
        kofi.tap()
        XCTAssertTrue(app.buttons["house-A1"].waitForExistence(timeout: 5))
        // The opponent's greeting shows briefly, then it is our move.
        let yourMove = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Your move"), object: app.staticTexts["turn-indicator"])
        XCTAssertEqual(XCTWaiter().wait(for: [yourMove], timeout: 10), .completed)
    }

    @MainActor
    func testDifficultyCanBeChangedMidGame() throws {
        app.buttons["btn-play-ai"].tap()
        XCTAssertTrue(app.buttons["house-A1"].waitForExistence(timeout: 5))
        let title = app.buttons["btn-mode-title"]
        XCTAssertTrue(title.exists)
        XCTAssertTrue(title.label.contains("Learner"))
        title.tap()
        XCTAssertTrue(app.buttons["game-level-strong"].waitForExistence(timeout: 3))
        app.buttons["game-level-strong"].tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Strong"), object: title)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 5), .completed)
        XCTAssertEqual(app.buttons["house-A1"].value as? String, "4 seeds", "the position is kept")
    }

    @MainActor
    func testPlayingAgainstTheAIGetsAReply() throws {
        app.buttons["btn-level"].tap()
        XCTAssertTrue(app.buttons["level-beginner"].waitForExistence(timeout: 3))
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
