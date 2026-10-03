import XCTest

/// Apple's accessibility audit on the main screens. Contrast, Dynamic Type and clipping are left
/// out: they are measured against photos, wood grain and glass and report false alarms there
/// (checked by eye instead; see docs/STATUS.md). Everything else must stay clean.
final class AccessibilityAuditUITests: XCTestCase {
    private let checks: XCUIAccessibilityAuditType = XCUIAccessibilityAuditType.all.subtracting([.contrast, .dynamicType, .textClipped])

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-state", "--fast-animations", "--rules=abapa"] + extra
        app.launch()
        return app
    }

    @MainActor func testHome() throws {
        let app = launch([])
        XCTAssertTrue(app.staticTexts["home-title"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: checks)
    }

    @MainActor func testGame() throws {
        let app = launch(["--start-game"])
        XCTAssertTrue(app.buttons["house-A1"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: checks)
    }

    @MainActor func testSettingsAndTipJar() throws {
        let app = launch([])
        let more = app.buttons["btn-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        if !more.isHittable { app.swipeUp() }
        more.tap()
        XCTAssertTrue(app.buttons["btn-settings"].waitForExistence(timeout: 6))
        app.buttons["btn-settings"].tap()
        XCTAssertTrue(app.switches["setting-usage-stats"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: checks)
        let tips = app.buttons["btn-tip-jar"]
        for _ in 0..<3 where !tips.isHittable { app.swipeUp() }
        tips.tap()
        XCTAssertTrue(app.staticTexts["tip-jar-title"].waitForExistence(timeout: 5))
        // Audit once the products have loaded (or failed to): a spinner that vanishes mid-audit fails it.
        for _ in 0..<20 where app.activityIndicators.count > 0 { usleep(500_000) }
        try app.performAccessibilityAudit(for: checks)
    }

    @MainActor func testRiddlesJourneyAndRules() throws {
        for screen in ["puzzles", "journey", "heritage"] {
            let app = launch(["--screen=\(screen)"])
            sleep(1)
            try app.performAccessibilityAudit(for: checks)
            app.terminate()
        }
    }
}
