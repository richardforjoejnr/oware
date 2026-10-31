import XCTest

/// Nearby play against the demo player (`--nearby-demo`): a pretend second phone inside the app,
/// over the same rooms and messages as two real phones (docs/NEARBY_PLAY.md step 5, NEARBY_PLAY_REDESIGN.md step 2). The demo is
/// called Ama; she plays the first move she can, two seconds after her turn comes, and the launch
/// arguments tell her when to resign (first game only) or go quiet.
final class NearbyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset-state", "--fast-animations", "--rules=abapa", "--nearby-demo"]
    }

    private func openNearby() {
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
    }

    private func wait(for element: XCUIElement, label: String, timeout: TimeInterval = 15) {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: timeout), .completed,
                       "\(element) never read \"\(label)\" (it reads \"\(element.label)\")")
    }

    /// Start nearby game, Ama comes, both press Ready: the game starts with you to move.
    private func startAndPressReady() {
        openNearby()
        let start = app.buttons["btn-start-nearby"]
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: start)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 5), .completed)
        start.tap()
        // Your game is ready, until Ama's phone turns up (a second and a half; a slow run can miss it).
        let ready = app.buttons["btn-ready"]
        XCTAssertTrue(app.staticTexts["nearby-waiting"].waitForExistence(timeout: 5) || ready.exists, "Your game is ready")
        XCTAssertTrue(ready.waitForExistence(timeout: 10), "Ama comes: Ready to play")
        XCTAssertTrue(app.staticTexts["Ama"].exists)
        XCTAssertTrue(app.buttons["btn-not-now"].exists, "the creator can turn her away")
        ready.tap()
        let turn = app.staticTexts["turn-indicator"]
        XCTAssertTrue(turn.waitForExistence(timeout: 10))
        wait(for: turn, label: "Your turn")
    }

    /// Plays the first house of yours with seeds in it, then waits until the turn has passed: to
    /// Ama, or (if she resigns at once) to the result. On a slow machine her two-second turn can be
    /// over before the label is read, so "Ama's turn" itself is not waited for.
    private func playAndWaitForReply() {
        let houses = (1...6).map { app.buttons["house-A\($0)"] }
        guard let house = houses.first(where: { $0.value as? String != "0 seeds" }) else { return XCTFail("no seeds to sow") }
        house.tap()
        let turn = app.staticTexts["turn-indicator"]
        let passed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", "Your turn"), object: turn)
        XCTAssertEqual(XCTWaiter().wait(for: [passed], timeout: 15), .completed, "the turn never passed to Ama")
    }

    @MainActor
    func testHostPlaysAmaToAWinThenRematch() throws {
        app.launchArguments += ["--demo-resign-after=1"]
        startAndPressReady()
        XCTAssertFalse(app.buttons["btn-undo"].exists, "no undo on two phones")
        XCTAssertFalse(app.buttons["btn-hint"].exists, "no hints on two phones")
        XCTAssertEqual(app.buttons["btn-mode-title"].exists, false, "no level to change")

        playAndWaitForReply()
        wait(for: app.staticTexts["turn-indicator"], label: "Your turn")
        playAndWaitForReply()

        // Ama resigns on her second turn.
        let title = app.staticTexts["game-over-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertTrue(title.label.hasPrefix("You win"), title.label)
        app.buttons["btn-rematch"].tap()

        // Ama always agrees, and she starts the rematch: the starter swaps.
        XCTAssertTrue(title.waitForNonExistence(timeout: 10), "the rematch starts once both have asked")
        // A new game: nothing in the stores (Ama's opening move, if already made, captures nothing).
        XCTAssertEqual(app.otherElements["store-A"].value as? String, "0 seeds")
        XCTAssertEqual(app.otherElements["store-B"].value as? String, "0 seeds")
        let turn = app.staticTexts["turn-indicator"]
        if turn.label != "Your turn" { wait(for: turn, label: "Your turn") }
    }

    /// One screen: no Host or Join. Look for games finds Ama's; join it, press Ready.
    @MainActor
    func testTheGuestsBoardIsTurnedRound() throws {
        openNearby()
        XCTAssertFalse(app.buttons["btn-host"].exists)
        XCTAssertFalse(app.buttons["btn-join"].exists)
        XCTAssertFalse(app.buttons["nearby-starter"].exists, "whoever starts the game moves first")
        let game = app.buttons["nearby-game-Ama's game"]
        XCTAssertFalse(game.exists, "nothing is looked for until asked")
        app.buttons["btn-look-nearby"].tap()
        XCTAssertTrue(game.waitForExistence(timeout: 10), "the demo's game is listed")
        game.tap()
        let ready = app.buttons["btn-ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["btn-not-now"].exists, "only the creator turns someone away")
        let canPress = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: ready)
        XCTAssertEqual(XCTWaiter().wait(for: [canPress], timeout: 10), .completed)
        ready.tap()

        let turn = app.staticTexts["turn-indicator"]
        XCTAssertTrue(turn.waitForExistence(timeout: 10))
        // Ama made the game, so she plays South and moves first; you play North, nearest you.
        let a1 = app.buttons["house-A1"].frame, b1 = app.buttons["house-B1"].frame
        XCTAssertGreaterThan(b1.midY, a1.midY, "your row (B) is the near one")
        wait(for: turn, label: "Your turn")
        XCTAssertEqual(app.otherElements["plaque-B"].label.hasPrefix("You"), true)
    }

    /// Looking for games can be stopped, and started again.
    @MainActor
    func testLookingCanBeStopped() throws {
        openNearby()
        app.buttons["btn-look-nearby"].tap()
        let game = app.buttons["nearby-game-Ama's game"]
        XCTAssertTrue(game.waitForExistence(timeout: 10))
        app.buttons["btn-stop-looking"].tap()
        XCTAssertTrue(game.waitForNonExistence(timeout: 5), "the list goes")
        XCTAssertTrue(app.buttons["btn-look-nearby"].waitForExistence(timeout: 5), "and Look for games is back")
    }

    /// How nearby play works: three steps, and help with connecting.
    @MainActor
    func testTheHelpSaysItInThreeSteps() throws {
        openNearby()
        app.buttons["btn-nearby-help"].tap()
        XCTAssertTrue(app.staticTexts["Keep both phones close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Start on one phone"].exists)
        XCTAssertTrue(app.staticTexts["Join on the other"].exists)
        XCTAssertTrue(app.buttons["btn-trouble-connecting"].exists)
    }

    /// Ama's connection drops (as when her app goes to the background): a banner at once, and it
    /// goes when her phone connects again, with the game carrying on.
    @MainActor
    func testABannerShowsWhileAmaReconnects() throws {
        app.launchArguments += ["--demo-drop-after=1", "--demo-away=3"]
        startAndPressReady()
        playAndWaitForReply()
        let banner = app.staticTexts["reconnect-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "the game says it is waiting")
        XCTAssertEqual(banner.label, "Reconnecting to Ama…")
        XCTAssertTrue(banner.waitForNonExistence(timeout: 10), "Ama comes back by herself")
        XCTAssertFalse(app.staticTexts["nearby-gone"].exists)
        wait(for: app.staticTexts["turn-indicator"], label: "Your turn", timeout: 15)
        playAndWaitForReply()
    }

    /// The joining phone loses Ama's game (her phone dropped the connection): it finds the game
    /// again by itself and carries on.
    @MainActor
    func testTheJoiningPhoneReconnectsByItself() throws {
        app.launchArguments += ["--demo-drop-after=1", "--demo-away=0"]
        openNearby()
        app.buttons["btn-look-nearby"].tap()
        let game = app.buttons["nearby-game-Ama's game"]
        XCTAssertTrue(game.waitForExistence(timeout: 10))
        game.tap()
        let ready = app.buttons["btn-ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 5))
        ready.tap()
        let turn = app.staticTexts["turn-indicator"]
        XCTAssertTrue(turn.waitForExistence(timeout: 10))
        wait(for: turn, label: "Your turn")   // Ama has moved, and then dropped
        let banner = app.staticTexts["reconnect-banner"]
        _ = banner.waitForExistence(timeout: 3)   // it may come and go before it is seen
        XCTAssertTrue(banner.waitForNonExistence(timeout: 10), "back by itself")
        XCTAssertFalse(app.staticTexts["nearby-gone"].exists)
        playAndWaitForReply()
    }

    /// Gone ten seconds: the game offers to carry on against the computer, in a few words.
    @MainActor
    func testAPhoneGoneTenSecondsOffersTheComputer() throws {
        app.launchArguments += ["--demo-drop-after=1", "--demo-away=60"]
        startAndPressReady()
        playAndWaitForReply()
        XCTAssertTrue(app.staticTexts["reconnect-banner"].waitForExistence(timeout: 10))
        let gone = app.staticTexts["nearby-gone"]
        XCTAssertTrue(gone.waitForExistence(timeout: 20), "after ten seconds")
        let finish = app.buttons["btn-finish-computer"]
        XCTAssertTrue(finish.exists)
        XCTAssertEqual(finish.label, "Play the computer")
        finish.tap()
        XCTAssertTrue(gone.waitForNonExistence(timeout: 5))
        wait(for: app.staticTexts["turn-indicator"], label: "Your turn", timeout: 15)
        playAndWaitForReply()
    }
}
