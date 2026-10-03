import XCTest
@testable import Oware

@MainActor
final class AppSettingsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "AppSettingsTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testTestModeIsInstantAndSilentButNeverSaved() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults, testMode: true)
        XCTAssertEqual(settings.effectiveSpeed, AppSettings.AnimationSpeed.instant.rawValue)
        XCTAssertFalse(settings.effectiveSound)
        XCTAssertFalse(settings.effectiveHaptics)
        XCTAssertNil(defaults.object(forKey: "animationSpeed"), "test mode must not persist")
        XCTAssertNil(defaults.object(forKey: "soundEnabled"))
        XCTAssertEqual(settings.animationSpeed, .normal, "the player's own preference is untouched")
    }

    /// House names and per-house counts: off in ordinary games unless switched on, always in lessons
    /// and riddles (their text names houses). The stores' score is not part of this setting.
    func testHouseLabelsAreOffInGamesButAlwaysInLessonsAndRiddles() {
        let settings = AppSettings(defaults: freshDefaults(), testMode: false)
        XCTAssertFalse(settings.showHouseLabels, "off by default")
        let session = TestSupport.session()
        session.newGame(.versusAI(difficulty: .beginner, personality: .balanced, humanPlays: .south))
        XCTAssertFalse(settings.labelsHouses(namesHouses: session.namesHouses), "a game shows no labels")
        session.startTutorial(step: 0, variant: .abapa)
        XCTAssertTrue(settings.labelsHouses(namesHouses: session.namesHouses), "the lesson always does")
        settings.showHouseLabels = true
        XCTAssertTrue(AppSettings(defaults: settings.defaultsForTesting, testMode: false).showHouseLabels, "the choice persists")
        session.newGame(.passAndPlay)
        XCTAssertTrue(settings.labelsHouses(namesHouses: session.namesHouses), "switched on, games show them")
    }

    func testNamNamIsTheDefaultRuleSetForNewGames() {
        let settings = AppSettings(defaults: freshDefaults(), testMode: false)
        XCTAssertEqual(settings.variant, .namNam)
        XCTAssertEqual(settings.rules.variant, .namNam)
        settings.variant = .abapa
        XCTAssertEqual(AppSettings(defaults: settings.defaultsForTesting, testMode: false).variant, .abapa, "the choice persists")
    }

    func testNormalLaunchPlaysAtChosenSpeedWithSoundAndHaptics() {
        let settings = AppSettings(defaults: freshDefaults(), testMode: false)
        XCTAssertEqual(settings.effectiveSpeed, 1.0)
        XCTAssertTrue(settings.effectiveSound)
        XCTAssertTrue(settings.effectiveHaptics)
    }

    func testLeakedInstantSpeedIsRepairedEvenWhenSoundWasTurnedBackOn() {
        let defaults = freshDefaults()
        defaults.set(100.0, forKey: "animationSpeed")
        defaults.set(true, forKey: "soundEnabled")      // the player already fixed this one by hand
        let repaired = AppSettings(defaults: defaults, testMode: false)
        XCTAssertEqual(repaired.animationSpeed, .normal, "a stored Instant speed can only have come from the leak")
        XCTAssertTrue(repaired.soundEnabled)
    }

    func testLeakedTestPreferencesAreRepairedOnce() {
        let defaults = freshDefaults()
        defaults.set(100.0, forKey: "animationSpeed")
        defaults.set(false, forKey: "soundEnabled")
        defaults.set(false, forKey: "hapticsEnabled")
        let repaired = AppSettings(defaults: defaults, testMode: false)
        XCTAssertEqual(repaired.animationSpeed, .normal)
        XCTAssertTrue(repaired.soundEnabled)
        XCTAssertTrue(repaired.hapticsEnabled)
        // A deliberate later choice of Instant stays.
        repaired.animationSpeed = .instant
        repaired.soundEnabled = false
        repaired.hapticsEnabled = false
        let again = AppSettings(defaults: defaults, testMode: false)
        XCTAssertEqual(again.animationSpeed, .instant)
    }
}
