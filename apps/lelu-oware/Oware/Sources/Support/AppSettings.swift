import SwiftUI
import Observation
import UIKit
import OwareEngine

/// User preferences. Backed by UserDefaults so they survive relaunch.
@MainActor
@Observable
final class AppSettings {
    enum AnimationSpeed: Double, CaseIterable, Identifiable {
        case slow = 0.7, normal = 1.0, fast = 1.6, instant = 100
        var id: Double { rawValue }
        var label: String {
            switch self {
            case .slow: "Slow"
            case .normal: "Normal"
            case .fast: "Fast"
            case .instant: "Instant"
            }
        }
    }

    var animationSpeed: AnimationSpeed {
        didSet { defaults.set(animationSpeed.rawValue, forKey: "animationSpeed") }
    }
    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: "hapticsEnabled") }
    }
    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: "soundEnabled") }
    }
    var showSeedCounts: Bool {
        didSet { defaults.set(showSeedCounts, forKey: "showSeedCounts") }
    }
    /// Grand-slam convention for new games (Abapa forfeit by default).
    var grandSlamRule: RuleSet.GrandSlamRule {
        didSet { defaults.set(grandSlamRule.rawValue, forKey: "grandSlamRule") }
    }
    var rules: RuleSet { RuleSet(grandSlam: grandSlamRule) }
    /// Chosen board look (see `BoardTheme`).
    var boardThemeID: String {
        didSet { defaults.set(boardThemeID, forKey: "boardTheme") }
    }
    var boardTheme: BoardTheme { BoardTheme.named(boardThemeID) }

    /// UI-test launches (`--fast-animations`) play instantly and silently *without* touching the
    /// player's saved preferences. (Assigning the stored properties in `init` used to persist them,
    /// because `@Observable` routes those assignments through the observed setters.)
    let testMode: Bool

    /// Honour Reduce Motion and test mode: sowing becomes instant.
    var effectiveSpeed: Double {
        (testMode || UIAccessibility.isReduceMotionEnabled) ? AnimationSpeed.instant.rawValue : animationSpeed.rawValue
    }
    var effectiveSound: Bool { soundEnabled && !testMode }
    var effectiveHaptics: Bool { hapticsEnabled && !testMode }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, testMode: Bool = LaunchOptions.fastAnimations) {
        self.defaults = defaults
        self.testMode = testMode
        Self.repairPreferencesIfNeeded(in: defaults, testMode: testMode)
        let speed = defaults.object(forKey: "animationSpeed") as? Double
        animationSpeed = AnimationSpeed(rawValue: speed ?? 1.0) ?? .normal
        hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        showSeedCounts = defaults.object(forKey: "showSeedCounts") as? Bool ?? true
        grandSlamRule = RuleSet.GrandSlamRule(rawValue: defaults.string(forKey: "grandSlamRule") ?? "") ?? .forfeitCapture
        boardThemeID = defaults.string(forKey: "boardTheme") ?? BoardTheme.heritage.id
    }

    /// Builds before 2026-09-24 leaked the test flags into saved preferences (instant sowing, sound
    /// and haptics off). Undo that once for anyone who never chose those settings themselves.
    private static func repairPreferencesIfNeeded(in defaults: UserDefaults, testMode: Bool) {
        let marker = "preferencesRepaired.2026-09-24"
        guard !testMode, !defaults.bool(forKey: marker) else { return }
        defaults.set(true, forKey: marker)
        let leaked = defaults.object(forKey: "animationSpeed") as? Double == AnimationSpeed.instant.rawValue
            && defaults.object(forKey: "soundEnabled") as? Bool == false
            && defaults.object(forKey: "hapticsEnabled") as? Bool == false
        if leaked {
            defaults.removeObject(forKey: "animationSpeed")
            defaults.removeObject(forKey: "soundEnabled")
            defaults.removeObject(forKey: "hapticsEnabled")
        }
    }
}
