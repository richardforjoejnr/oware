import XCTest

/// XCUITest suite — developer-owned UI regression tests run by `xcodebuild test` and CI.
/// Black-box end-to-end flows live in `.maestro/flows` (Maestro) and `e2e/` (TypeScript).
final class HomeScreenUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset-state", "--fast-animations", "--rules=abapa"]
        app.launch()
    }

    /// The home screen shows one primary action; the rest is behind "More".
    /// Patient on slow CI machines: waits for the menu, scrolls it into view, and retries the tap once.
    private func openMore() {
        let more = app.buttons["btn-more"]
        let settings = app.buttons["btn-settings"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        for _ in 0..<2 where !settings.exists {
            if !more.isHittable { app.swipeUp() }
            more.tap()
            if settings.waitForExistence(timeout: 6) { break }
        }
        XCTAssertTrue(settings.exists, "More did not open")
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
        XCTAssertTrue(app.staticTexts["turn-indicator"].label.hasPrefix("Step 1 of"))
        XCTAssertTrue(app.staticTexts["lesson-prompt"].label.hasPrefix("Welcome"), "the lesson text is shown in full")
        app.buttons["btn-next-step"].tap()
        // Wait for step 2 before tapping: on a slow machine a tap could land on step 1 instead.
        let stepTwo = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "Step 2 of"),
                                                object: app.staticTexts["turn-indicator"])
        XCTAssertEqual(XCTWaiter().wait(for: [stepTwo], timeout: 5), .completed)
        // Step 2 asks for A3; a different house is refused with a hint.
        app.buttons["house-A1"].tap()
        XCTAssertTrue(app.staticTexts["hint"].waitForExistence(timeout: 5))
        app.buttons["house-A3"].tap()
        XCTAssertTrue(app.staticTexts["tutorial-after"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["btn-next-step"].exists)
    }

    @MainActor
    func testTappingTheLessonLineShowsTheWholeStep() throws {
        app.buttons["btn-learn"].tap()
        let info = app.buttons["btn-lesson-info"]
        XCTAssertTrue(info.waitForExistence(timeout: 5))
        info.tap()
        XCTAssertTrue(app.staticTexts["lesson-card-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["lesson-card-prompt"].label.count > 40)
        app.buttons["btn-lesson-done"].tap()
        XCTAssertTrue(app.buttons["house-A1"].waitForExistence(timeout: 5))
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
    func testTappingTheRiddleLineShowsTheWholeRiddle() throws {
        openMore()
        app.buttons["btn-puzzles"].tap()
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'puzzle-captureInTwo-'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        let info = app.buttons["btn-riddle-info"]
        XCTAssertTrue(info.waitForExistence(timeout: 5))
        info.tap()
        XCTAssertTrue(app.staticTexts["riddle-card-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'whatever the other player replies' OR label CONTAINS 'Whatever the other player replies'")).firstMatch.exists)
        app.buttons["btn-riddle-done"].tap()
        XCTAssertTrue(app.buttons["house-A1"].waitForExistence(timeout: 5))
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
    func testTipJarOpensFromSettingsAndUnlocksNothing() throws {
        let more = app.buttons["btn-more"]
        if !app.buttons["btn-settings"].waitForExistence(timeout: 5) { more.tap() }
        let settings = app.buttons["btn-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        // Waits sized for a slow CI simulator (this failed once there with 5 s and 4 swipes): wait for
        // Settings to be up, then scroll until the row can be tapped.
        let row = app.buttons["btn-tip-jar"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the tip jar row is in Settings")
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable, "scrolled to the tip jar row")
        row.tap()
        XCTAssertTrue(app.staticTexts["tip-jar-title"].waitForExistence(timeout: 15))
        // Every look is still selectable regardless of tips.
        XCTAssertFalse(app.buttons["theme-kente"].label.contains("locked"))
    }

    @MainActor
    func testNamNamIsTheDefaultAndSowingRelays() throws {
        app.terminate()
        app.launchArguments = ["--reset-state", "--fast-animations"]   // no rules pin: the shipped default
        app.launch()
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        openMore()
        app.buttons["btn-pass-play"].tap()
        let a1 = app.buttons["house-A1"]
        XCTAssertTrue(a1.waitForExistence(timeout: 5))
        a1.tap()
        let done = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "B to move"), object: app.staticTexts["turn-indicator"])
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: 8), .completed)
        // Under Nam-Nam the four seeds from A1 land in A5 (which held four) and are carried on, so
        // A5 is not simply 5 as it would be under Abapa; and 48 seeds are still on the board or in stores.
        XCTAssertNotEqual(app.buttons["house-A5"].value as? String, "5 seeds")
        var total = 0
        for id in ["A1", "A2", "A3", "A4", "A5", "A6", "B1", "B2", "B3", "B4", "B5", "B6"] {
            total += Int((app.buttons["house-\(id)"].value as? String ?? "0").split(separator: " ").first ?? "0") ?? 0
        }
        for id in ["store-A", "store-B"] {
            total += Int((app.otherElements[id].value as? String ?? "0").split(separator: " ").first ?? "0") ?? 0
        }
        XCTAssertEqual(total, 48)
    }

    @MainActor
    func testRulesPageLeadsWithTheChosenRules() throws {
        app.terminate()
        app.launchArguments = ["--reset-state", "--fast-animations", "--screen=heritage"]   // shipped default: Nam-Nam
        app.launch()
        XCTAssertTrue(app.staticTexts["rules-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nam-Nam, the rules this app is set to. Change them in Settings."].exists)
        app.terminate()
        app.launchArguments = ["--reset-state", "--fast-animations", "--screen=heritage", "--rules=abapa"]
        app.launch()
        XCTAssertTrue(app.staticTexts["rules-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Abapa, the rules this app is set to. Change them in Settings."].exists)
    }

    @MainActor
    func testResigningFromTheFlagEndsTheGame() throws {
        app.buttons["btn-play-ai"].tap()
        let flag = app.buttons["btn-end-game"]
        XCTAssertTrue(flag.waitForExistence(timeout: 5))
        flag.tap()
        let resign = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Resign'")).firstMatch
        XCTAssertTrue(resign.waitForExistence(timeout: 3))
        resign.tap()
        XCTAssertTrue(app.staticTexts["game-over-title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["btn-end-game"].exists, "nothing left to end")
    }

    @MainActor
    func testDifficultyCanBeChangedMidGame() throws {
        app.buttons["btn-play-ai"].tap()
        XCTAssertTrue(app.buttons["house-A1"].waitForExistence(timeout: 5))
        let title = app.buttons["btn-mode-title"]
        XCTAssertTrue(title.exists)
        XCTAssertTrue(title.label.contains("Novice"))
        title.tap()
        XCTAssertTrue(app.buttons["game-level-strategist"].waitForExistence(timeout: 3))
        app.buttons["game-level-strategist"].tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Strategist"), object: title)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 5), .completed)
        XCTAssertEqual(app.buttons["house-A1"].value as? String, "4 seeds", "the position is kept")
    }

    @MainActor
    func testPlayingAgainstTheAIGetsAReply() throws {
        app.buttons["btn-level"].tap()
        XCTAssertTrue(app.buttons["level-novice"].waitForExistence(timeout: 3))
        app.buttons["level-novice"].tap()
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

    /// Regression: going Home while seeds were still being sown froze the board for good (the move
    /// never finished, so no taps, no undo and no reply). Sowing at real speed here.
    @MainActor
    func testLeavingMidMoveDoesNotFreezeTheBoard() throws {
        app.terminate()
        app.launchArguments = ["--reset-state", "--fast-animations", "--real-speed", "--rules=abapa"]
        app.launch()
        app.buttons["btn-play-ai"].tap()
        let a3 = app.buttons["house-A3"]
        XCTAssertTrue(a3.waitForExistence(timeout: 5))
        a3.tap()
        app.buttons["btn-home"].tap()
        let resume = app.buttons["btn-continue"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        let turn = app.staticTexts["turn-indicator"]
        XCTAssertTrue(turn.waitForExistence(timeout: 5))
        // The computer still replies, and then the board takes our next move.
        let yourMove = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Your move"), object: turn)
        XCTAssertEqual(XCTWaiter().wait(for: [yourMove], timeout: 15), .completed, "the board froze")
        let a1 = app.buttons["house-A1"]
        a1.tap()
        let emptied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0 seeds"), object: a1)
        XCTAssertEqual(XCTWaiter().wait(for: [emptied], timeout: 10), .completed, "the move was not accepted")
    }
}
