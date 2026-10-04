import XCTest

/// App Store screenshots from the real app, one test per shot (`make screenshots`).
///
/// Opt-in: skipped unless `SCREENSHOT_DIR` reaches the test runner (xcodebuild passes on
/// `TEST_RUNNER_SCREENSHOT_DIR`), so `make test` and CI never write files. Each shot is saved there as
/// `<device>-NN-name.png` (device `iPhone` or `iPad`) at the simulator's full resolution. Positions
/// come from `--scenario=` and dice from `--dice=`, so every run shoots the same game; `--fast`
/// leaves out the tumbling die and the pauses, so nothing is caught mid-animation.
final class ScreenshotUITests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? ""
        try XCTSkipIf(path.isEmpty, "screenshots only with SCREENSHOT_DIR (make screenshots)")
        dir = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    @MainActor private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-state", "--fast"] + extra
        app.launch()
        return app
    }

    /// Lets the last tap's highlight and any layout change finish, then saves the screen.
    @MainActor private func shoot(_ name: String) throws {
        Thread.sleep(forTimeInterval: 1.5)
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        let shot = XCUIScreen.main.screenshot()
        try shot.pngRepresentation.write(to: dir.appendingPathComponent("\(device)-\(name).png"))
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func wait(_ element: XCUIElement, _ what: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 20), what)
    }

    @MainActor private func waitForLabel(_ element: XCUIElement, contains text: String) {
        expectation(for: NSPredicate(format: "label CONTAINS %@", text), evaluatedWith: element)
        waitForExpectations(timeout: 20)
    }

    /// Opens a menu tile's panel (it appears under the tiles, below the board box).
    @MainActor private func openPanel(_ app: XCUIApplication, tile: String, showing anchor: XCUIElement) {
        let button = app.buttons[tile]
        wait(button, tile)
        button.tap()
        wait(anchor, "\(tile)'s panel")
    }

    /// Scrolls the menu so the tiles sit just under the status bar and the open panel fills the
    /// screen below them. A drag loses a little to touch slop, so it corrects once or twice.
    @MainActor private func scrollTilesToTop(_ app: XCUIApplication, tile: String) {
        let target = app.frame.height * 0.075
        for _ in 0..<4 {
            let distance = app.buttons[tile].frame.minY - target
            if abs(distance) < 8 { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: distance > 0 ? 0.85 : 0.3))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                        withVelocity: .slow, thenHoldForDuration: 0.5)
        }
    }

    // MARK: - The shots, in App Store order

    @MainActor func test01Home() throws {
        let app = launch([])
        wait(app.images["home-title"], "the menu")
        wait(app.buttons["tile-learn"], "the tiles")
        try shoot("01-home")
    }

    @MainActor func test02GameInProgress() throws {
        // Red to roll against three computers; a 4 lets two tokens move.
        let app = launch(["--scenario=midgame", "--dice=4"])
        let roll = app.buttons["btn-roll"]
        wait(roll, "the board")
        roll.tap()
        waitForLabel(app.staticTexts["status"], contains: "choose a token")
        try shoot("02-game")
    }

    @MainActor func test03KickChoice() throws {
        // A 5: the token on track 12 can move on, or back-kick Black's token 5 squares behind it.
        let app = launch(["--scenario=kick", "--dice=5"])
        let roll = app.buttons["btn-roll"]
        wait(roll, "the board")
        roll.tap()
        let token = app.descendants(matching: .any)["token-red-1"]
        wait(token, "the kicking token")
        token.tap()
        wait(app.descendants(matching: .any)["choice-backKick"], "the back kick is offered")
        try shoot("03-kick")
    }

    @MainActor func test04Learn() throws {
        let app = launch([])
        openPanel(app, tile: "tile-learn", showing: app.buttons["btn-start-tutorial"])
        scrollTilesToTop(app, tile: "tile-learn")
        try shoot("04-learn")
    }

    @MainActor func test05Lesson() throws {
        // Lesson 1 played: the scripted 6 rolled and a token brought out, the lesson says why.
        let app = launch(["--tutorial"])
        wait(app.staticTexts["lesson-title"], "the lesson")
        app.buttons["btn-roll"].tap()
        let token = app.descendants(matching: .any)["token-red-0"]
        wait(token, "a token to bring out")
        token.tap()
        wait(app.buttons["btn-lesson-next"], "the lesson done")
        try shoot("05-lesson")
    }

    @MainActor func test06PlayTheComputer() throws {
        let app = launch([])
        openPanel(app, tile: "tile-start", showing: app.buttons["btn-play-computer"])
        app.buttons["opponents-3"].tap()
        app.buttons["level-strategist"].tap()
        scrollTilesToTop(app, tile: "tile-start")
        try shoot("06-computer")
    }

    @MainActor func test07Settings() throws {
        let app = launch([])
        openPanel(app, tile: "btn-settings", showing: app.buttons["rules-ghanaClassic"])
        scrollTilesToTop(app, tile: "btn-settings")
        try shoot("07-settings")
    }

    @MainActor func test08PassAndPlay() throws {
        // Four people on one phone: Yellow rolls a 6.
        let app = launch(["--scenario=pass-and-play", "--dice=6"])
        let roll = app.buttons["btn-roll"]
        wait(roll, "the board")
        roll.tap()
        waitForLabel(app.staticTexts["status"], contains: "choose a token")
        try shoot("08-pass-and-play")
    }
}
