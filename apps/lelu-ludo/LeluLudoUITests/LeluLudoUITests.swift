import XCTest

/// The app end to end with scripted dice (`--dice=`), so every run plays the same game.
/// Waits for the first screen are long (20 s): a launch on a busy machine (CI, or several simulators
/// at once) can take that long, and a wait returns as soon as the element is there.
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
        XCTAssertTrue(roll.waitForExistence(timeout: 20))
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
        waitForExpectations(timeout: 20)
        // The computer had its turn; it is yours again.
        let status = app.staticTexts["status"]
        expectation(for: NSPredicate(format: "label == 'Your roll'"), evaluatedWith: status)
        waitForExpectations(timeout: 20)
    }

    @MainActor
    func testABackKickIsOfferedAndChosen() throws {
        let app = launch(["--scenario=back-kick", "--dice=5,2"])
        let roll = app.buttons["btn-roll"]
        XCTAssertTrue(roll.waitForExistence(timeout: 20))
        roll.tap()
        let token = app.descendants(matching: .any)["token-red-0"]
        XCTAssertTrue(token.waitForExistence(timeout: 3))
        XCTAssertEqual(token.value as? String, "Can kick", "the token shows it has a kick")
        token.tap()
        let back = app.descendants(matching: .any)["choice-backKick"]
        XCTAssertTrue(back.waitForExistence(timeout: 3), "the back kick is offered")
        XCTAssertTrue(app.descendants(matching: .any)["choice-forward"].exists, "and so is the plain move")
        back.tap()
        expectation(for: NSPredicate(format: "label CONTAINS 'back-kicked'"), evaluatedWith: app.staticTexts["commentary"])
        waitForExpectations(timeout: 10)
    }

    @MainActor
    func testRulesAreChosenInSettings() throws {
        let app = launch([])
        let settings = app.buttons["btn-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        XCTAssertTrue(settings.label.contains("Ghana Classic"), settings.label)
        settings.tap()
        XCTAssertTrue(app.buttons["rules-ghanaClassic"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["rules-ghanaClassic"].isSelected, "Ghana Classic is the default")
        XCTAssertFalse(app.switches["rule-home-kick"].exists, "switches only for Custom")
        app.buttons["rules-custom"].tap()
        XCTAssertTrue(app.switches["rule-home-kick"].waitForExistence(timeout: 3))
        try app.performAccessibilityAudit(for: XCUIAccessibilityAuditType.all.subtracting([.contrast, .dynamicType, .textClipped]))
        app.buttons["rules-classic"].tap()
        // Settings opens under the tiles; scroll back up to the tile, whose label names the rules.
        app.swipeDown()
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        expectation(for: NSPredicate(format: "label CONTAINS 'Classic' AND NOT (label CONTAINS 'Ghana')"), evaluatedWith: settings)
        waitForExpectations(timeout: 20)
        // The privacy policy and support, reachable inside the app (App Review 5.1.1(i)).
        XCTAssertTrue(app.descendants(matching: .any)["link-privacy"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["link-support"].exists)
    }

    @MainActor
    func testPassAndPlayFromTheMenu() throws {
        let app = launch(["--dice=3"])
        let friends = app.buttons["tile-friends"]
        XCTAssertTrue(friends.waitForExistence(timeout: 20))
        friends.tap()
        let play = app.buttons["btn-pass-play"]
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        play.tap()
        let roll = app.buttons["btn-roll"]
        XCTAssertTrue(roll.waitForExistence(timeout: 20))
        roll.tap()   // red: 3, nothing out, passes
        expectation(for: NSPredicate(format: "label CONTAINS 'Black'"), evaluatedWith: app.staticTexts["status"])
        waitForExpectations(timeout: 20)
        XCTAssertTrue(roll.isEnabled, "black rolls for themselves")
    }

    @MainActor
    func testLearnTheGameFromTheMenu() throws {
        let app = launch([])
        let learn = app.buttons["tile-learn"]
        XCTAssertTrue(learn.waitForExistence(timeout: 20))
        learn.tap()
        let start = app.buttons["btn-start-tutorial"]
        XCTAssertTrue(start.waitForExistence(timeout: 20))
        start.tap()
        let title = app.staticTexts["lesson-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertEqual(title.label, "Your yard")
        // Lesson 1: roll the scripted 6 and bring a token out.
        app.buttons["btn-roll"].tap()
        let token = app.descendants(matching: .any)["token-red-0"]
        XCTAssertTrue(token.waitForExistence(timeout: 20))
        token.tap()
        let next = app.buttons["btn-lesson-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 20))
        next.tap()
        expectation(for: NSPredicate(format: "label == 'Home is the centre'"), evaluatedWith: title)
        waitForExpectations(timeout: 20)
        // Home gives the menu back (TutorialTests prove the saved game is untouched).
        app.buttons["btn-home"].tap()
        XCTAssertTrue(app.buttons["tile-learn"].waitForExistence(timeout: 20))
    }

    @MainActor
    func testAccessibilityAuditOnTheMenuAndTheBoard() throws {
        // Contrast and Dynamic Type are left out, as in Lelu Oware: they misfire on painted boards.
        let checks = XCUIAccessibilityAuditType.all.subtracting([.contrast, .dynamicType, .textClipped])
        let app = launch([])
        XCTAssertTrue(app.images["home-title"].waitForExistence(timeout: 20))
        try app.performAccessibilityAudit(for: checks)
        app.terminate()
        let game = launch(["--start-game"])
        XCTAssertTrue(game.buttons["btn-roll"].waitForExistence(timeout: 20))
        try game.performAccessibilityAudit(for: checks)
    }
}
