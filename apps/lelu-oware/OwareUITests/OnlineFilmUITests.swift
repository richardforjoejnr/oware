import XCTest

/// Two simulators playing each other online through the real dev relay, for a video of the
/// feature (docs/ONLINE_PLAY.md §10, "Filming"). Not part of any test run: it does nothing unless
/// `TEST_RUNNER_OWARE_FILM_DIR` names a folder both simulators share (see scripts/film-online.sh).
/// The larger phone starts the game; the other joins with the invitation link.
@MainActor
final class OnlineFilmUITests: XCTestCase {
    private var app: XCUIApplication!
    private var folder: URL!
    private var isHost: Bool { UIDevice.current.name.contains("Max") }
    private var codeFile: URL { folder.appendingPathComponent("code.txt") }

    override func setUp() async throws {
        guard let path = ProcessInfo.processInfo.environment["OWARE_FILM_DIR"], !path.isEmpty else {
            throw XCTSkip("only for filming: scripts/film-online.sh")
        }
        folder = URL(fileURLWithPath: path)
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset-state", "--fast-animations", "--real-speed", "--rules=abapa", "-nearbyName", isHost ? "Ama" : "Kofi"]
    }

    private func pause(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

    private func wait(_ element: XCUIElement, toRead label: String, timeout: TimeInterval) -> Bool {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter().wait(for: [shown], timeout: timeout) == .completed
    }

    /// Sows the first house with seeds once it is this phone's turn. False when the game is over.
    private func playOne(row: String) -> Bool {
        let turn = app.staticTexts["turn-indicator"]
        guard wait(turn, toRead: "Your turn", timeout: 60) else { return false }
        pause(1.2)
        let houses = (1...6).map { app.buttons["house-\(row)\($0)"] }
        guard let house = houses.last(where: { $0.exists && $0.value as? String != "0 seeds" }) else { return false }
        house.tap()
        return true
    }

    func testFilmAGameOnline() throws {
        isHost ? try host() : try guest()
    }

    private func host() throws {
        try? FileManager.default.removeItem(at: codeFile)
        app.launch()
        pause(2)
        let more = app.buttons["btn-more"], online = app.buttons["btn-online"]
        XCTAssertTrue(more.waitForExistence(timeout: 20))
        if !online.waitForExistence(timeout: 3) { more.tap() }
        XCTAssertTrue(online.waitForExistence(timeout: 6))
        pause(1.5)
        online.tap()
        let start = app.buttons["btn-start-online"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        pause(1.5)
        start.tap()
        let code = app.staticTexts["online-code"]
        XCTAssertTrue(code.waitForExistence(timeout: 20), "the relay gave no code")
        let text = code.label.filter { $0.isLetter || $0.isNumber }
        try text.suffix(6).description.write(to: codeFile, atomically: true, encoding: .utf8)
        // The invitation, as it would be sent in a message; then back to wait.
        pause(2)
        let share = app.buttons["btn-share-code"]
        if share.exists, share.isHittable { share.tap() }
        pause(3)
        let close = app.buttons.matching(NSPredicate(format: "label == 'Close' OR identifier == 'header.closeButton'")).firstMatch
        if close.exists, close.isHittable {
            close.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        }
        let ready = app.buttons["btn-ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 90), "nobody joined")
        pause(2.5)
        ready.tap()
        for _ in 0..<5 { guard playOne(row: "A") else { break } }
        // A second game: Kofi asks, Ama agrees.
        let rematch = app.buttons["btn-rematch"]
        XCTAssertTrue(rematch.waitForExistence(timeout: 90), "the game did not end")
        XCTAssertTrue(app.staticTexts["rematch-request"].waitForExistence(timeout: 30))
        pause(2)
        rematch.tap()
        for _ in 0..<2 { guard playOne(row: "A") else { break } }
        pause(6)
    }

    private func guest() throws {
        let end = Date().addingTimeInterval(120)
        app.launch()
        var code = ""
        while code.count != 6, Date() < end {
            code = (try? String(contentsOf: codeFile, encoding: .utf8)) ?? ""
            if code.count != 6 { pause(0.5) }
        }
        XCTAssertEqual(code.count, 6, "no code from the other simulator")
        pause(9)
        // What tapping the invitation link in a message does.
        app.open(URL(string: "leluoware://join?c=\(code)")!)
        let ready = app.buttons["btn-ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 30), "the link did not open the game")
        pause(1.5)
        ready.tap()
        for _ in 0..<4 { guard playOne(row: "B") else { break } }
        // Kofi resigns, then asks for another game.
        XCTAssertTrue(wait(app.staticTexts["turn-indicator"], toRead: "Your turn", timeout: 60))
        pause(1.5)
        app.buttons["btn-end-game"].tap()
        let resign = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Resign'")).firstMatch
        XCTAssertTrue(resign.waitForExistence(timeout: 5))
        pause(1)
        resign.tap()
        let rematch = app.buttons["btn-rematch"]
        XCTAssertTrue(rematch.waitForExistence(timeout: 20))
        pause(2.5)
        rematch.tap()
        for _ in 0..<2 { guard playOne(row: "B") else { break } }
        pause(6)
    }
}
