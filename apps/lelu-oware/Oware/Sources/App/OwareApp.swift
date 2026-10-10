import SwiftUI
import OwareEngine
import SupportKit

@main
struct OwareApp: App {
    @State private var session: GameSession
    @State private var settings: AppSettings
    @State private var library = PuzzleLibrary()
    @State private var progress: JourneyProgress
    @State private var tipJar: TipJar
    @State private var reminder = RiddleReminder()

    init() {
        LaunchClock.appStarted()
        // Launch options used by UI tests: `--reset-state` / `-resetState YES` start from a clean
        // install (saved game, progress and every setting), so no test depends on one before it;
        // `--fast-animations` / `-fastAnimations YES` make everything instant and silent.
        if LaunchOptions.resetState {
            GameStore.shared.clear()
            if let domain = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: domain)
            }
        }
        // The session records results itself, so a game that ends off-screen still counts.
        let progress = JourneyProgress()
        let session = GameSession()
        session.journey = progress
        _session = State(initialValue: session)
        _progress = State(initialValue: progress)
        // Every tip is counted, including ones the App Store delivers later (Ask to Buy).
        let tipJar = TipJar(productIDs: Tips.productIDs)
        tipJar.onTip = { PlayerEvents.shared.tipPurchased(productID: $0) }
        _tipJar = State(initialValue: tipJar)
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        // Analytics and Game Center stay silent in test launches.
        Analytics.shared.configure(enabled: settings.effectiveUsageStats)
        Analytics.shared.track(.appLaunched)
        if !settings.testMode { GameCenter.shared.authenticate() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(settings)
                .environment(library)
                .environment(progress)
                .environment(tipJar)
                .environment(reminder)
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
    /// The app is hosting the unit tests (XCTest set it running): no analytics, no Game Center.
    static var isUnitTestHost: Bool { enabled && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }
    /// Any test run: quiet, instant, and nothing sent anywhere.
    static var testMode: Bool { fastAnimations || isUnitTestHost }
    /// `--real-speed`: with `--fast-animations`, still sow at normal speed (tests that need a move
    /// in flight, e.g. leaving the game mid-sowing).
    static var realSpeed: Bool { flag("--real-speed") }
    /// `--ask-usage-stats`: show the one-time usage-stats question even in a test launch.
    static var askUsageStats: Bool { flag("--ask-usage-stats") }
    /// `--report-launch-time`: the home menu reports how long launch took (LaunchTimeUITests).
    static var reportLaunchTime: Bool { flag("--report-launch-time") }
    /// `--start-game` / `-startGame YES`: open straight onto a new game at Casual level.
    static var startGame: Bool { flag("--start-game", defaultsKey: "startGame") }
    /// `--demo-move`: with `--start-game`, sow A1 a moment after launch (animation checks).
    static var demoMove: Bool { flag("--demo-move") }
    /// `--screen=journey|puzzles|heritage|lesson`: open on that screen (lesson: its first step).
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
