import XCTest

/// Nearby play against the demo player (`--nearby-demo`): a pretend second phone inside the app,
/// over the same rooms and messages as two real phones (docs/NEARBY_PLAY.md step 5). The demo is
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

    /// The first time: "What should nearby players call you?" A name saved by the test before can
    /// outlive `--reset-state` when tests run back to back, so it is typed only when asked;
    /// `NearbyLobbyTests.testTheNameIsKept` and the Maestro flow (a cleared app) check the asking.
    /// Waits for whichever comes first: the name prompt, or `next` (the screen after it).
    private func giveName(_ name: String, orSee next: XCUIElement) {
        let field = app.textFields["nearby-name-field"]
        let end = Date().addingTimeInterval(10)
        while !field.exists && !next.exists && Date() < end { _ = field.waitForExistence(timeout: 0.5) }
        guard field.exists else { return }
        field.tap()
        field.typeText(name)
        app.buttons["btn-name-done"].tap()
    }

    private func wait(for element: XCUIElement, label: String, timeout: TimeInterval = 15) {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: timeout), .completed,
                       "\(element) never read \"\(label)\" (it reads \"\(element.label)\")")
    }

    /// Host, Ama asks to join, accept: the game starts with you to move.
    private func hostAndAccept() {
        openNearby()
        app.buttons["btn-host"].tap()
        giveName("Kofi", orSee: app.staticTexts["nearby-waiting"])
        XCTAssertTrue(app.staticTexts["nearby-waiting"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ama wants to play"].waitForExistence(timeout: 10))
        app.buttons["btn-accept"].tap()
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
        hostAndAccept()
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

    @MainActor
    func testTheGuestsBoardIsTurnedRound() throws {
        openNearby()
        app.buttons["btn-join"].tap()
        giveName("Esi", orSee: app.buttons["nearby-game-Ama's game"])
        let game = app.buttons["nearby-game-Ama's game"]
        XCTAssertTrue(game.waitForExistence(timeout: 10), "the demo host's game is listed")
        game.tap()

        let turn = app.staticTexts["turn-indicator"]
        XCTAssertTrue(turn.waitForExistence(timeout: 10))
        // Ama hosts, so she plays South and moves first; you play North, nearest you.
        let a1 = app.buttons["house-A1"].frame, b1 = app.buttons["house-B1"].frame
        XCTAssertGreaterThan(b1.midY, a1.midY, "your row (B) is the near one")
        wait(for: turn, label: "Your turn")
        XCTAssertEqual(app.otherElements["plaque-B"].label.hasPrefix("You"), true)
    }

    @MainActor
    func testABannerShowsWhileAmasPhoneIsQuiet() throws {
        app.launchArguments += ["--demo-quiet-after=1"]
        hostAndAccept()
        playAndWaitForReply()
        let banner = app.staticTexts["reconnect-banner"]
        // Six seconds of silence makes a seat "reconnecting"; the heartbeat checks every two.
        XCTAssertTrue(banner.waitForExistence(timeout: 15), "the game says it is waiting")
        XCTAssertEqual(banner.label, "Reconnecting to Ama…")
        // The demo comes back after twelve seconds.
        XCTAssertTrue(banner.waitForNonExistence(timeout: 20))
    }
}
