import SwiftUI
import OwareEngine
import SupportKit

@main
struct OwareApp: App {
    @State private var session: GameSession
    @State private var settings: AppSettings
    @State private var library = PuzzleLibrary()
    @State private var progress = JourneyProgress()
    @State private var tipJar = TipJar(productIDs: Tips.productIDs)

    init() {
        // Launch options used by UI tests: `--reset-state` / `-resetState YES` wipe the saved game,
        // `--fast-animations` / `-fastAnimations YES` make everything instant and silent.
        if LaunchOptions.resetState {
            GameStore.shared.clear()
            UserDefaults.standard.removeObject(forKey: "solvedPuzzleIDs")
            UserDefaults.standard.removeObject(forKey: "journeyStars")
            UserDefaults.standard.removeObject(forKey: "tutorialSeen")
            UserDefaults.standard.removeObject(forKey: "preferredDifficulty")
            UserDefaults.standard.removeObject(forKey: "supportkit.tipCount")
        }
        _session = State(initialValue: GameSession())
        _settings = State(initialValue: AppSettings())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(settings)
                .environment(library)
                .environment(progress)
                .environment(tipJar)
                .preferredColorScheme(.dark)
        }
    }
}

/// The tip jar's products. Consumables, nothing unlocked: the whole game is free.
enum Tips {
    static let productIDs = ["com.richardforjoe.oware.tip.small", "com.richardforjoe.oware.tip.medium", "com.richardforjoe.oware.tip.large"]
}

/// Launch arguments used by the test suites and for screenshots. They compile only into Debug
/// builds: the App Store build has no switches that reset state, skip the splash or stage positions.
enum LaunchOptions {
    #if DEBUG
    private static let enabled = true
    #else
    private static let enabled = false
    #endif
    private static func flag(_ name: String, defaultsKey: String? = nil) -> Bool {
        guard enabled else { return false }
        return CommandLine.arguments.contains(name) || (defaultsKey.map { UserDefaults.standard.bool(forKey: $0) } ?? false)
    }
    private static func value(_ prefix: String) -> String? {
        guard enabled else { return nil }
        return CommandLine.arguments.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    /// `--reset-state` / `-resetState YES`: wipe the saved game and progress.
    static var resetState: Bool { flag("--reset-state", defaultsKey: "resetState") }
    /// `--fast-animations` / `-fastAnimations YES`: instant, silent, no splash (UI tests).
    static var fastAnimations: Bool { flag("--fast-animations", defaultsKey: "fastAnimations") }
    /// `--start-game` / `-startGame YES`: open straight onto a new game against the Learner.
    static var startGame: Bool { flag("--start-game", defaultsKey: "startGame") }
    /// `--demo-move`: with `--start-game`, sow A1 a moment after launch (animation checks).
    static var demoMove: Bool { flag("--demo-move") }
    /// `--screen=journey|puzzles|heritage`: open on that screen.
    static var startScreen: String? { value("--screen=") }
    /// `--demo-stores=N`: with `--start-game`, put N seeds in each store and scatter the rest.
    static var demoStores: Int? { value("--demo-stores=").flatMap(Int.init) }
    /// `--rules=abapa|namnam` / `-rules abapa`: pin the variant for a test run (not persisted).
    static var rulesOverride: RuleSet.Variant? {
        let raw = value("--rules=") ?? (enabled ? UserDefaults.standard.string(forKey: "rules") : nil)
        switch raw?.lowercased() {
        case "abapa": return .abapa
        case "namnam", "nam-nam": return .namNam
        default: return nil
        }
    }
}
