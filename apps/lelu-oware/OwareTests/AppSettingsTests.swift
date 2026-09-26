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

    func testNormalLaunchPlaysAtChosenSpeedWithSoundAndHaptics() {
        let settings = AppSettings(defaults: freshDefaults(), testMode: false)
        XCTAssertEqual(settings.effectiveSpeed, 1.0)
        XCTAssertTrue(settings.effectiveSound)
        XCTAssertTrue(settings.effectiveHaptics)
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
