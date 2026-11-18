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
        XCTAssertEqual(app.buttons["btn-start-online"].label, "Invite a friend")
        // The link is the way in; a code is the fallback, one tap away.
        XCTAssertFalse(app.textFields["online-code-field"].exists, "the code box stays out of the way")
        app.buttons["btn-join-with-code"].tap()
        XCTAssertTrue(app.textFields["online-code-field"].waitForExistence(timeout: 3), "a friend's code can be entered")
        XCTAssertTrue(app.buttons["btn-paste-code"].exists, "a pasted invitation is taken too")
        app.buttons["btn-start-online"].tap()

        // The code and Share show until Ama's phone joins (a second and a half; a slow run can miss them).
        let code = app.staticTexts["online-code"]
        let ready = app.buttons["btn-ready"]
        if code.waitForExistence(timeout: 5) {
            XCTAssertEqual(code.label, "Your code: K 7 M 2 Q D", "read out letter by letter")
            XCTAssertTrue(app.buttons["btn-share-code"].exists || ready.exists, "the invitation can be sent")
            XCTAssertFalse(app.images["online-qr"].exists, "no QR code: the link does the job")
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

    /// Nam-Nam online, on the real board at real speed: the first move (A1) lands its last seed in
    /// a house with seeds, so it is scooped up and sown on, four times, before the turn passes.
    /// The board must end where the rules say, not where the first lap stopped.
    func testNamNamRelaySowingIsPlayedOutOnline() {
        app.launchArguments = ["--reset-state", "--fast-animations", "--real-speed", "--rules=namnam", "--online-demo"]
        openOnline()
        app.buttons["btn-start-online"].tap()
        let ready = app.buttons["btn-ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 10), "Ama joins: Ready to play")
        let note = app.staticTexts["nearby-game-note"]
        XCTAssertTrue(note.label.hasPrefix("Nam-Nam"), note.label)
        XCTAssertTrue(app.staticTexts["nearby-rules-hint"].label.contains("sow on"), "the Ready screen says what Nam-Nam does")
        let ama = app.descendants(matching: .any)["nearby-player-other"]
        let amaReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Ama, red side, Ready'"), object: ama)
        XCTAssertEqual(XCTWaiter().wait(for: [amaReady], timeout: 10), .completed)
        ready.tap()
        let turn = app.staticTexts["turn-indicator"]
        XCTAssertTrue(turn.waitForExistence(timeout: 10))
        let yours = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Your turn'"), object: turn)
        XCTAssertEqual(XCTWaiter().wait(for: [yours], timeout: 15), .completed, turn.label)

        app.buttons["house-A1"].tap()
        // Four seeds, then four relay laps: the turn passes only when the last lap ends.
        let passed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != 'Your turn'"), object: turn)
        XCTAssertEqual(XCTWaiter().wait(for: [passed], timeout: 60), .completed, "the turn never passed")
        // Where Nam-Nam leaves the board after A1 from the opening (the engine's own answer; a
        // single lap, as in Abapa, would leave A1 empty and A2 to A5 with five each).
        let expected = ["A1": 2, "A2": 7, "A3": 1, "A4": 6, "A5": 1, "A6": 6, "B1": 6, "B2": 6, "B3": 0]
        for (house, seeds) in expected.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(app.buttons["house-\(house)"].value as? String, "\(seeds) seeds", "house \(house)")
        }
    }

    /// A code that is not six of the letters and numbers used cannot be sent.
    func testJoinIsOfferedOnlyForSomethingThatCouldBeACode() {
        openOnline()
        app.buttons["btn-join-with-code"].tap()
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
        app.buttons["btn-join-with-code"].tap()
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

    /// Play online is on Home for everyone, first under More, with nothing passed in at launch.
    /// A test build's switch in Settings takes it off, and that is remembered.
    func testPlayOnlineLeadsMoreAndATestBuildsSwitchTakesItOff() {
        app.launchArguments = ["--reset-state", "--fast-animations"]
        app.launch()
        let more = app.buttons["btn-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        let online = app.buttons["btn-online"], passPlay = app.buttons["btn-pass-play"]
        if !online.waitForExistence(timeout: 5) { more.tap() }
        XCTAssertTrue(online.waitForExistence(timeout: 6))
        XCTAssertTrue(passPlay.waitForExistence(timeout: 6))
        XCTAssertLessThan(online.frame.minY, passPlay.frame.minY, "Play online comes first")

        let settings = app.buttons["btn-settings"]
        for _ in 0..<3 where !settings.isHittable { app.swipeUp() }
        settings.tap()
        let toggle = app.switches["setting-online-play"]
        for _ in 0..<4 where !toggle.exists || !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1", "on until a tester turns it off")
        // A SwiftUI Toggle is one element with its label: tap the switch itself, at its right end.
        if toggle.switches.firstMatch.exists {
            toggle.switches.firstMatch.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, "0")
        app.terminate()

        // Still off on the next launch, from the icon.
        app.launchArguments = ["--fast-animations"]
        app.launch()
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        if !passPlay.waitForExistence(timeout: 5) { more.tap() }
        XCTAssertTrue(passPlay.waitForExistence(timeout: 6))
        XCTAssertFalse(online.exists)
    }

    /// The relay cannot be reached as the app opens: Play online is still listed, says so, and
    /// does not open.
    func testPlayOnlineSaysWhenTheRelayIsDown() {
        app.launchArguments = ["--reset-state", "--fast-animations", "--relay-down"]
        app.launch()
        let more = app.buttons["btn-more"], online = app.buttons["btn-online"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        if !online.waitForExistence(timeout: 5) { more.tap() }
        XCTAssertTrue(online.waitForExistence(timeout: 6))
        XCTAssertTrue(online.label.contains("can't be reached"), online.label)
        online.tap()
        XCTAssertFalse(app.staticTexts["nearby-title"].waitForExistence(timeout: 3), "it does not open")
        XCTAssertTrue(online.exists)
    }

    // MARK: A game that survives the app closing, and Not now to a rematch

    private func wait(for element: XCUIElement, label: String, timeout: TimeInterval = 20) {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [shown], timeout: timeout), .completed,
                       "\(element) never read \"\(label)\" (it reads \"\(element.label)\")")
    }

    /// Invite, Ama joins, both Ready: the game is on and it is your turn.
    private func startAGameWithAma() {
        openOnline()
        app.buttons["btn-start-online"].tap()
        let ready = app.buttons["btn-ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 10), "Ama joins: Ready to play")
        let ama = app.descendants(matching: .any)["nearby-player-other"]
        let amaReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Ama, red side, Ready'"), object: ama)
        XCTAssertEqual(XCTWaiter().wait(for: [amaReady], timeout: 10), .completed)
        ready.tap()
        let turn = app.staticTexts["turn-indicator"]
        XCTAssertTrue(turn.waitForExistence(timeout: 10))
        wait(for: turn, label: "Your turn")
    }

    /// Sows your first house with seeds and waits until the turn has passed.
    private func play() {
        let houses = (1...6).map { app.buttons["house-A\($0)"] }
        guard let house = houses.first(where: { $0.value as? String != "0 seeds" }) else { return XCTFail("no seeds to sow") }
        house.tap()
        let turn = app.staticTexts["turn-indicator"]
        let passed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", "Your turn"), object: turn)
        XCTAssertEqual(XCTWaiter().wait(for: [passed], timeout: 15), .completed, "the turn never passed to Ama")
    }

    /// The app is closed in the middle of a game and opened again: Home offers the game, Rejoin
    /// goes back to the same board, and play carries on. Then Leave game takes the card away.
    func testAGameIsStillThereAfterTheAppIsClosed() {
        startAGameWithAma()
        play()
        let turn = app.staticTexts["turn-indicator"]
        wait(for: turn, label: "Your turn")
        XCTAssertEqual(app.buttons["house-A1"].value as? String, "0 seeds", "A1 was sown")
        app.terminate()

        // Opened again from the icon: nothing is reset.
        app.launchArguments = ["--fast-animations", "--rules=abapa", "--online-demo"]
        app.launch()
        let rejoin = app.buttons["btn-rejoin"]
        XCTAssertTrue(rejoin.waitForExistence(timeout: 10), "Home offers the game")
        XCTAssertTrue(rejoin.label.contains("Your game with Ama"), rejoin.label)
        XCTAssertTrue(app.buttons["btn-leave-saved"].exists)
        rejoin.tap()

        XCTAssertTrue(turn.waitForExistence(timeout: 15), "the board opens")
        XCTAssertEqual(app.buttons["house-A1"].value as? String, "0 seeds", "the game as it was, not a new one")
        wait(for: turn, label: "Your turn")
        play()
        wait(for: turn, label: "Your turn")   // Ama is there and answers

        // Closed again, and this time the game is left for good.
        app.terminate()
        app.launch()
        XCTAssertTrue(rejoin.waitForExistence(timeout: 10))
        app.buttons["btn-leave-saved"].tap()
        // Asked first: the dialog's own Leave game, not the one on the card.
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Leave game' AND identifier != 'btn-leave-saved'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "leaving for good is confirmed")
        confirm.tap()
        XCTAssertTrue(rejoin.waitForNonExistence(timeout: 5), "nothing to rejoin")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["btn-more"].waitForExistence(timeout: 10))
        XCTAssertFalse(rejoin.exists, "and it stays gone")
    }

    /// After a game with Ama she is under Recent players, and Play again asks her to a new game
    /// with no link sent. Remove takes her off the list.
    func testSomeonePlayedIsListedAndPlayAgainAsksThem() {
        openOnline()
        XCTAssertTrue(app.staticTexts["recent-empty"].exists, "nobody played yet")
        XCTAssertTrue(app.buttons["btn-invitations-on"].exists, "invitations are off until asked for")
        app.buttons["btn-start-online"].tap()
        let ready = app.buttons["btn-ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 10), "Ama joins: Ready to play")
        ready.tap()
        let turn = app.staticTexts["turn-indicator"]
        XCTAssertTrue(turn.waitForExistence(timeout: 15))
        wait(for: turn, label: "Your turn")
        app.terminate()

        // Opened again: the game is left, and Ama is remembered.
        app.launchArguments = ["--fast-animations", "--rules=abapa", "--online-demo"]
        app.launch()
        let leave = app.buttons["btn-leave-saved"]
        XCTAssertTrue(leave.waitForExistence(timeout: 10))
        leave.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Leave game' AND identifier != 'btn-leave-saved'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(leave.waitForNonExistence(timeout: 5))

        let more = app.buttons["btn-more"], online = app.buttons["btn-online"]
        for _ in 0..<2 where !online.exists {
            if !more.isHittable { app.swipeUp() }
            more.tap()
            if online.waitForExistence(timeout: 6) { break }
        }
        if !online.isHittable { app.swipeUp() }
        online.tap()
        let again = app.buttons["btn-play-again-Ama"]
        XCTAssertTrue(again.waitForExistence(timeout: 5), "Ama is under Recent players")
        XCTAssertEqual(again.label, "Play Ama again")
        XCTAssertFalse(app.staticTexts["recent-empty"].exists)
        again.tap()
        XCTAssertTrue(ready.waitForExistence(timeout: 15), "she was asked and joined: Ready to play")
        let ama = app.descendants(matching: .any)["nearby-player-other"]
        XCTAssertTrue(ama.label.hasPrefix("Ama, red side"), ama.label)

        // Back out, and take her off the list.
        app.buttons["btn-cancel"].firstMatch.tap()
        let menu = app.buttons["btn-recent-more-Ama"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["Remove from list"].tap()
        XCTAssertTrue(again.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["recent-empty"].exists)
    }

    /// Ama asks for a rematch: you see who asked, and can say Not now. She does not ask again;
    /// you may ask later, and then the next game starts.
    func testNotNowToARematchAndAskingLater() {
        app.launchArguments += ["--demo-resign-after=1"]
        startAGameWithAma()
        play()
        let turn = app.staticTexts["turn-indicator"]
        wait(for: turn, label: "Your turn")
        play()   // Ama resigns on her second turn

        let title = app.staticTexts["game-over-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        let request = app.staticTexts["rematch-request"]
        XCTAssertTrue(request.waitForExistence(timeout: 10), "Ama asks")
        XCTAssertEqual(request.label, "Ama wants a rematch")
        XCTAssertTrue(app.buttons["btn-rematch"].exists)
        let notNow = app.buttons["btn-rematch-not-now"]
        XCTAssertEqual(notNow.label, "Not now")
        notNow.tap()

        XCTAssertTrue(request.waitForNonExistence(timeout: 5), "the request is gone")
        XCTAssertFalse(notNow.exists, "nothing left to answer")
        // Longer than she takes to think: she does not ask again, and no game starts by itself.
        XCTAssertFalse(request.waitForExistence(timeout: 4), "Ama asked again after Not now")
        XCTAssertTrue(title.exists, "the finished game is still showing")

        let rematch = app.buttons["btn-rematch"]
        XCTAssertTrue(rematch.exists, "you may ask later")
        rematch.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10), "Ama agrees, and the next game starts")
    }
}
