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
        // You: 6 (out), 4 (moves it by itself: Novice, and its only move is forward). Computer: 2
        // (nothing out: passes). You again.
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
        try audit(app, XCUIAccessibilityAuditType.all.subtracting([.contrast, .dynamicType, .textClipped]))
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

    /// The audit on every screen, not just the menu and the board: each panel, Custom settings, a
    /// lesson, and a game with a kick to choose. Contrast, Dynamic Type and text clipping are left
    /// out, as in Lelu Oware: on painted wood, gradients and engraved lettering they misfire. Contrast
    /// was measured from screenshot pixels instead (2026-10-04): panel titles 5.7:1, body text 8:1,
    /// and the lesson heading, which was 3.7:1, now uses the light brass.
    @MainActor
    func testAccessibilityAuditOnEveryScreen() throws {
        let checks = XCUIAccessibilityAuditType.all.subtracting([.contrast, .dynamicType, .textClipped])
        let app = launch([])
        XCTAssertTrue(app.images["home-title"].waitForExistence(timeout: 20))
        for tile in ["tile-start", "tile-friends", "tile-learn", "btn-settings"] {
            app.buttons[tile].tap()
            try audit(app, checks)
        }
        app.buttons["rules-custom"].tap()
        try audit(app, checks)
        app.terminate()

        let lesson = launch(["--tutorial"])
        XCTAssertTrue(lesson.buttons["btn-roll"].waitForExistence(timeout: 20))
        try audit(lesson, checks)
        lesson.terminate()

        let game = launch(["--scenario=kick", "--dice=5"])
        let roll = game.buttons["btn-roll"]
        XCTAssertTrue(roll.waitForExistence(timeout: 20))
        roll.tap()
        try audit(game, checks)
    }

    @MainActor
    func testTheSplashOpensOntoTheMenu() throws {
        let app = launch(["--splash"])
        let splash = app.descendants(matching: .any)["splash"]
        XCTAssertTrue(splash.waitForExistence(timeout: 20), "the opening card")
        XCTAssertTrue(splash.label.contains("Play Ghana. Play Together."), splash.label)
        splash.tap()   // a tap goes straight on
        XCTAssertTrue(app.images["home-title"].waitForExistence(timeout: 10), "then the menu")
    }

    @MainActor
    func testYouChooseYourColourAgainstTheComputer() throws {
        let app = launch([])
        XCTAssertTrue(app.buttons["tile-start"].waitForExistence(timeout: 20))
        app.buttons["tile-start"].tap()
        let green = app.buttons["colour-green"]
        XCTAssertTrue(green.waitForExistence(timeout: 10))
        green.tap()
        XCTAssertTrue(green.isSelected)
        let play = app.buttons["btn-play-computer"]
        XCTAssertEqual(play.label, "Play as Green")
        play.tap()
        XCTAssertTrue(app.buttons["btn-roll"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["token-green-0"].exists, "you are green")
        XCTAssertTrue(app.descendants(matching: .any)["token-yellow-0"].exists, "the computer sits opposite")
        XCTAssertFalse(app.descendants(matching: .any)["token-red-0"].exists)
        XCTAssertEqual(app.staticTexts["status"].label, "Your roll")
    }

    @MainActor
    func testFriendsPickColours() throws {
        let app = launch(["--dice=3"])
        XCTAssertTrue(app.buttons["tile-friends"].waitForExistence(timeout: 20))
        app.buttons["tile-friends"].tap()
        // Red and Black to start; take Black out, and Play is off until there are two again.
        let black = app.buttons["colour-black"]
        XCTAssertTrue(black.waitForExistence(timeout: 10))
        black.tap()
        XCTAssertFalse(app.buttons["btn-pass-play"].isEnabled, "one player is not a game")
        app.buttons["add-yellow"].tap()
        let play = app.buttons["btn-pass-play"]
        XCTAssertTrue(play.isEnabled)
        play.tap()
        let roll = app.buttons["btn-roll"]
        XCTAssertTrue(roll.waitForExistence(timeout: 20))
        roll.tap()   // Red: a 3, nobody out: passes to Yellow (Black was taken out)
        expectation(for: NSPredicate(format: "label CONTAINS 'Yellow'"), evaluatedWith: app.staticTexts["status"])
        waitForExpectations(timeout: 20)
    }

    /// The Support tile opens the tip jar.
    @MainActor
    func testTheSupportTileOpensTheTipJar() throws {
        let app = launch([])
        let support = app.buttons["tile-support"]
        XCTAssertTrue(support.waitForExistence(timeout: 20))
        for _ in 0..<4 where !support.isHittable { app.swipeUp() }
        support.tap()
        XCTAssertTrue(app.staticTexts["tip-jar-title"].waitForExistence(timeout: 15))
        // The tips themselves come from the App Store. A command-line test run often doesn't load the
        // local test store, so the jar shows its status line instead; buying is tested in SupportKit's
        // own tests (StoreKitTest), as for Lelu Oware.
        let loaded = app.buttons["tip-0"].waitForExistence(timeout: 10)
        XCTAssertTrue(loaded || app.staticTexts["tip-jar-status"].exists, "the jar shows its tips or why not")
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
        try audit(app, checks)
        app.terminate()
        let game = launch(["--start-game"])
        XCTAssertTrue(game.buttons["btn-roll"].waitForExistence(timeout: 20))
        try audit(game, checks)
    }
}

/// The accessibility audit, made steady for slow CI simulators: the screen settles first, and if
/// Apple's audit gives up on time (XCTest error -56, "Audit failed to complete in time") it is run
/// once more. A real accessibility issue still fails the test, as before.
@MainActor
func audit(_ app: XCUIApplication, _ types: XCUIAccessibilityAuditType) throws {
    sleep(1)
    do {
        try app.performAccessibilityAudit(for: types)
    } catch let error as NSError where error.code == -56 {
        sleep(2)
        try app.performAccessibilityAudit(for: types)
    }
}
