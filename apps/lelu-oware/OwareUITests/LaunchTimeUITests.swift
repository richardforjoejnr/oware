import XCTest

/// People expect to be using an app within about three seconds of tapping it. This guards the part
/// this repository controls: from the app's first code to the home menu appearing, as the app itself
/// measures it (LaunchClock), so neither the test runner nor the simulator loading a Debug build is
/// counted. The total since process start is logged for reference. The splash is left out (a design
/// choice, timed by SplashSchedule). The fastest of three cold launches.
final class LaunchTimeUITests: XCTestCase {
    /// Our own work is about 0.5–0.6 s today, on a Mac's simulator and on CI alike (CI, 2026-10-03:
    /// 0.48–0.86 s, median 0.59). Well past this and launch (setup, the home screen's first render)
    /// has got heavier.
    static let budget: TimeInterval = 1.0

    @MainActor
    func testTheHomeMenuAppearsQuickly() throws {
        var app: [TimeInterval] = [], total: [TimeInterval] = []
        for _ in 0..<3 {
            let launched = XCUIApplication()
            launched.launchArguments = ["--fast-animations", "--rules=abapa", "--report-launch-time"]
            launched.launch()
            let label = launched.staticTexts["launch-time"]
            XCTAssertTrue(label.waitForExistence(timeout: 15), "the home menu reports its launch time")
            let parts = label.label.split(separator: " ").compactMap { TimeInterval($0) }
            XCTAssertEqual(parts.count, 2)
            app.append(parts[0]); total.append(parts[1])
            launched.terminate()
        }
        // The fastest of three: a busy CI runner only ever makes a launch slower, so the fastest is the
        // truest measure of the app's own work, and a real regression makes all three slow. (The middle
        // one failed once on CI at 1.04 s, between 1.91 and 0.88, for no change to the app.)
        let fastest = app.min()!
        let line = { (xs: [TimeInterval]) in xs.map { String(format: "%.2f", $0) }.joined(separator: ", ") }
        // Recorded as an activity so the numbers are in the result bundle (CI uploads it), not just stdout.
        XCTContext.runActivity(named: "Launch: app's own work \(line(app)) s (fastest \(String(format: "%.2f", fastest)), budget \(Self.budget)); since process start \(line(total)) s") { _ in }
        XCTAssertLessThanOrEqual(fastest, Self.budget, "from the app's first code to the home menu took \(line(app)) s")
    }
}
