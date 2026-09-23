import SwiftUI
import Observation

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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let speed = defaults.object(forKey: "animationSpeed") as? Double
        animationSpeed = AnimationSpeed(rawValue: speed ?? 1.0) ?? .normal
        hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
        soundEnabled = defaults.object(forKey: "soundEnabled") as? Bool ?? true
        showSeedCounts = defaults.object(forKey: "showSeedCounts") as? Bool ?? true
        if LaunchOptions.fastAnimations {
            // Not persisted: UI-test runs must not change the player's real preferences.
            animationSpeed = .instant
            soundEnabled = false
            hapticsEnabled = false
        }
    }
}
