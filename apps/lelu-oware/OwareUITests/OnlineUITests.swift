import XCTest

/// Play online against the demo player (`--online-demo`): a relay and a second phone inside the
/// app, over the same transport, room messages and relay messages as two real phones through AWS
/// (docs/ONLINE_PLAY.md §10). Nothing leaves the simulator.
final class OnlineUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset-state", "--fast-animations", "--rules=abapa", "--online-demo"]
    }

    private func openOnline() {
        app.launch()
        let more = app.buttons["btn-more"]
        let online = app.buttons["btn-online"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        for _ in 0..<2 where !online.exists {
            if !more.isHittable { app.swipeUp() }
            more.tap()
            if online.waitForExistence(timeout: 6) { break }
        }
        if !online.isHittable { app.swipeUp() }
        online.tap()
        XCTAssertTrue(app.staticTexts["nearby-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["nearby-title"].label, "Play online")
    }

    /// Start online game: a code to share, Ama joins with it, both press Ready, and a move is
    /// answered.
    func testStartAGameShareTheCodeAndPlay() {
        openOnline()
        XCTAssertFalse(app.buttons["btn-look-nearby"].exists, "no games nearby to look for online")
        XCTAssertTrue(app.textFields["online-code-field"].exists, "a friend's code can be entered")
        app.buttons["btn-start-online"].tap()

        // The code and Share show until Ama's phone joins (a second and a half; a slow run can miss them).
        let code = app.staticTexts["online-code"]
        let ready = app.buttons["btn-ready"]
        if code.waitForExistence(timeout: 5) {
            XCTAssertEqual(code.label, "Your code: K 7 M 2 Q D", "read out letter by letter")
            XCTAssertTrue(app.buttons["btn-share-code"].exists || ready.exists)
        }
        XCTAssertTrue(ready.waitForExistence(timeout: 10), "Ama joins: Ready to play")
        let ama = app.descendants(matching: .any)["nearby-player-other"]
        XCTAssertTrue(ama.label.hasPrefix("Ama, red side"), ama.label)
        let amaReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Ama, red side, Ready'"), object: ama)
        XCTAssertEqual(XCTWaiter().wait(for: [amaReady], timeout: 10), .completed, "Ama's Ready shows here: \(ama.label)")
        ready.tap()

        let turn = app.staticTexts["turn-indicator"]
        XCTAssertTrue(turn.waitForExistence(timeout: 10))
        let yours = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Your turn'"), object: turn)
        XCTAssertEqual(XCTWaiter().wait(for: [yours], timeout: 15), .completed, turn.label)

        let houses = (1...6).map { app.buttons["house-A\($0)"] }
        guard let house = houses.first(where: { $0.value as? String != "0 seeds" }) else { return XCTFail("no seeds to sow") }
        house.tap()
        // Her move comes back through the relay: the turn passes to her, then returns.
        let passed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != 'Your turn'"), object: turn)
        XCTAssertEqual(XCTWaiter().wait(for: [passed], timeout: 15), .completed, "the turn never passed to Ama")
        let yoursAgain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Your turn'"), object: turn)
        XCTAssertEqual(XCTWaiter().wait(for: [yoursAgain], timeout: 20), .completed, "Ama never answered: \(turn.label)")
    }

    /// A code that is not six of the letters and numbers used cannot be sent.
    func testJoinIsOfferedOnlyForSomethingThatCouldBeACode() {
        openOnline()
        let field = app.textFields["online-code-field"]
        let join = app.buttons["btn-join-online"]
        XCTAssertFalse(join.isEnabled)
        field.tap()
        field.typeText("K7M2Q")
        XCTAssertFalse(join.isEnabled, "five characters")
        field.typeText("D")
        XCTAssertTrue(join.isEnabled)
    }

    /// A code nobody has: a plain message, and Back to try again.
    func testAWrongCodeSaysSo() {
        openOnline()
        let field = app.textFields["online-code-field"]
        field.tap()
        field.typeText("ZZZZZZ")
        app.buttons["btn-join-online"].tap()
        let refused = app.staticTexts["nearby-refused"]
        XCTAssertTrue(refused.waitForExistence(timeout: 10))
        XCTAssertTrue(refused.label.hasPrefix("No game has that code"), refused.label)
        app.buttons["btn-cancel"].tap()
        XCTAssertTrue(app.buttons["btn-start-online"].waitForExistence(timeout: 5))
    }

    /// Play online is hidden until its switch is on.
    func testPlayOnlineIsNotOnHomeWithoutTheSwitch() {
        app.launchArguments = ["--reset-state", "--fast-animations"]
        app.launch()
        let more = app.buttons["btn-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        if !more.isHittable { app.swipeUp() }
        more.tap()
        XCTAssertTrue(app.buttons["btn-pass-play"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["btn-online"].exists)
    }
}
