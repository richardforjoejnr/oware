import Foundation
import LudoEngine
import Observation

/// Which rules new games use.
enum RulesPreset: String, CaseIterable, Sendable {
    /// Lelu Ludo's default: every Ghanaian kick on (owner, 2026-10-03).
    case ghanaClassic
    /// Plain Ludo as printed rule sheets give it.
    case classic
    /// The player's own switches, starting from Ghana Classic.
    case custom

    /// The preset's name where room is short (the Settings switch): Ghana · Classic · Custom.
    var shortTitle: String {
        switch self {
        case .ghanaClassic: "Ghana"
        case .classic: "Classic"
        case .custom: "Custom"
        }
    }

    var title: String {
        switch self {
        case .ghanaClassic: "Ghana Classic"
        case .classic: "Classic"
        case .custom: "Custom"
        }
    }
}

/// The player's choices, kept in UserDefaults (injectable for tests).
@MainActor
@Observable
final class AppSettings {
    var preset: RulesPreset { didSet { defaults.set(preset.rawValue, forKey: "rulesPreset") } }
    /// The custom rules (used when the preset is Custom).
    var custom: RuleSet {
        didSet { if let data = try? JSONEncoder().encode(custom) { defaults.set(data, forKey: "customRules") } }
    }
    var soundOn: Bool { didSet { defaults.set(soundOn, forKey: "soundOn") } }
    var hapticsOn: Bool { didSet { defaults.set(hapticsOn, forKey: "hapticsOn") } }
    /// The dice throw the player chose (Full, Quick or Off); nil until they choose.
    var diceThrowChoice: DiceAnimation? { didSet { defaults.set(diceThrowChoice?.rawValue, forKey: "diceAnimation") } }

    /// The dice throw in use: the player's choice, or until they choose, the device's Reduce Motion
    /// (on: Off; off: Full). Choosing Full or Quick shows the throw even with Reduce Motion on: the
    /// player asked for it (owner, 2026-10-04).
    func diceThrow(reduceMotion: Bool) -> DiceAnimation { diceThrowChoice ?? (reduceMotion ? .off : .full) }

    /// Test launches are silent without touching what the player chose.
    let testMode: Bool
    var effectiveSound: Bool { soundOn && !testMode }
    var effectiveHaptics: Bool { hapticsOn && !testMode }

    /// The rules for the next game.
    var rules: RuleSet {
        switch preset {
        case .ghanaClassic: .ghanaClassic
        case .classic: .classic
        case .custom: custom
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, testMode: Bool = LaunchOptions.testMode) {
        self.defaults = defaults
        self.testMode = testMode
        preset = RulesPreset(rawValue: defaults.string(forKey: "rulesPreset") ?? "") ?? .ghanaClassic
        var stored = (defaults.data(forKey: "customRules")).flatMap { try? JSONDecoder().decode(RuleSet.self, from: $0) } ?? .ghanaClassic
        stored.labourerEnabled = false   // reserved until the owner defines it
        // Damaged or old settings must still let a token out of the yard (and make saves that load).
        if stored.entryRolls.isEmpty || !stored.entryRolls.isSubset(of: 1...6) { stored.entryRolls = [6] }
        custom = stored
        soundOn = defaults.object(forKey: "soundOn") as? Bool ?? true
        hapticsOn = defaults.object(forKey: "hapticsOn") as? Bool ?? true
        diceThrowChoice = DiceAnimation(rawValue: defaults.string(forKey: "diceAnimation") ?? "")
    }
}
