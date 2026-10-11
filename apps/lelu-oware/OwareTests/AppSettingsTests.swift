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

    /// House names and per-house counts: off in ordinary games unless switched on. The lesson
    /// names houses, so it always shows both; riddles never name a house but are solved by counting,
    /// so they show the counts only. The stores' score is not part of this setting.
    func testHouseLabelsAreOffInGamesNamesInLessonsCountsInRiddles() throws {
        let settings = AppSettings(defaults: freshDefaults(), testMode: false)
        XCTAssertFalse(settings.showHouseLabels, "off by default")
        let session = TestSupport.session()
        session.newGame(.versusAI(difficulty: .beginner, personality: .balanced, humanPlays: .south))
        XCTAssertFalse(settings.labelsHouses(required: session.namesHouses), "a game shows no names")
        XCTAssertFalse(settings.labelsHouses(required: session.countsSeeds), "a game shows no counts")
        session.startTutorial(step: 0, variant: .abapa)
        XCTAssertTrue(settings.labelsHouses(required: session.namesHouses), "the lesson names houses")
        XCTAssertTrue(settings.labelsHouses(required: session.countsSeeds), "the lesson counts seeds")
        let library = PuzzleLibrary(defaults: TestSupport.defaults(), bundle: Bundle(for: GameSession.self))
        let puzzle = try XCTUnwrap(library.puzzles.first)
        session.startPuzzle(puzzle)
        XCTAssertFalse(settings.labelsHouses(required: session.namesHouses), "a riddle names no houses")
        XCTAssertTrue(settings.labelsHouses(required: session.countsSeeds), "a riddle counts seeds")
        settings.showHouseLabels = true
        XCTAssertTrue(AppSettings(defaults: settings.defaultsForTesting, testMode: false).showHouseLabels, "the choice persists")
        session.newGame(.passAndPlay)
        XCTAssertTrue(settings.labelsHouses(required: session.namesHouses), "switched on, games show names")
        XCTAssertTrue(settings.labelsHouses(required: session.countsSeeds), "switched on, games show counts")
        session.startPuzzle(puzzle)
        XCTAssertTrue(settings.labelsHouses(required: session.namesHouses), "switched on, riddles show names too")
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
