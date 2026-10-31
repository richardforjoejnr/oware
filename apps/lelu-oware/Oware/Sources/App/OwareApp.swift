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
    @State private var lobby: NearbyLobby

    init() {
        LaunchClock.appStarted()
        // Launch options used by UI tests: `--reset-state` / `-resetState YES` start from a clean
        // install (saved game, progress and every setting), so no test depends on one before it;
        // `--fast-animations` / `-fastAnimations YES` make everything instant and silent.
        if LaunchOptions.resetState {
            GameStore.shared.clear()
            if let domain = Bundle.main.bundleIdentifier {
                // Key by key as well: reading the launch options has already loaded the settings,
                // and removing the domain alone can leave them cached for this launch.
                let keys = UserDefaults.standard.persistentDomain(forName: domain)?.keys.map { $0 } ?? []
                UserDefaults.standard.removePersistentDomain(forName: domain)
                keys.forEach(UserDefaults.standard.removeObject(forKey:))
            }
        }
        // The session records results itself, so a game that ends off-screen still counts.
        let progress = JourneyProgress()
        let session = GameSession()
        session.journey = progress
        _session = State(initialValue: session)
        _progress = State(initialValue: progress)
        let network: any NearbyNetwork = LaunchOptions.nearbyDemo ? DemoNetwork() : LiveNearbyNetwork()
        _lobby = State(initialValue: NearbyLobby(session: session, network: network))
        // Every tip is counted, including ones the App Store delivers later (Ask to Buy).
        // `--tips-unavailable` (Debug only): the App Store returns nothing, to test the Try again path.
        let noTips: TipJar.ProductLoader = { _ in [] }
        let tipJar = TipJar(productIDs: Tips.productIDs, loader: LaunchOptions.tipsUnavailable ? noTips : nil)
        tipJar.onTip = { PlayerEvents.shared.tipPurchased(productID: $0) }
        _tipJar = State(initialValue: tipJar)
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        // Analytics and Game Center stay silent in test launches.
        Analytics.shared.configure(enabled: settings.effectiveUsageStats)
        Analytics.shared.track(.appLaunched)
        if FeatureFlags.gameCenter, !settings.testMode { GameCenter.shared.authenticate() }
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
                .environment(lobby)
                .preferredColorScheme(.dark)
        }
    }
}

/// The tip jar's products. Consumables, nothing unlocked: the whole game is free. These are the
/// only in-app purchases this version asks for, so they are the only ones to submit with it
/// (online play's product stays out until that feature ships: see OnlineAccess.swift).
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
        return isOn(name, defaultsKey: defaultsKey, in: CommandLine.arguments)
            || (defaultsKey.map { UserDefaults.standard.bool(forKey: $0) } ?? false)
    }
    /// `name` itself, or `defaultsKey true`: Maestro passes a true/false argument as a bare key and
    /// its value, with no dash, so the defaults never see it.
    static func isOn(_ name: String, defaultsKey: String?, in arguments: [String]) -> Bool {
        if arguments.contains(name) { return true }
        guard let defaultsKey else { return false }
        return zip(arguments, arguments.dropFirst()).contains { key, value in
            key == defaultsKey && ["true", "yes", "1"].contains(value.lowercased())
        }
    }
    private static func value(_ prefix: String) -> String? {
        guard enabled else { return nil }
        return CommandLine.arguments.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }
    private static func number(_ prefix: String, defaultsKey: String) -> Int? {
        guard enabled else { return nil }
        return value(prefix).flatMap(Int.init) ?? (UserDefaults.standard.object(forKey: defaultsKey) as? NSNumber)?.intValue
            ?? UserDefaults.standard.string(forKey: defaultsKey).flatMap(Int.init)
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
    /// `--tips-unavailable`: the tip jar gets no products, as when the App Store cannot be reached.
    static var tipsUnavailable: Bool { flag("--tips-unavailable") }
    /// The tip jar is shown: `FeatureFlags.tips`, or `--tips` in a Debug launch (the tip jar's own tests).
    static var showsTips: Bool { FeatureFlags.tips || flag("--tips") }
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
    /// `--nearby` / `-nearbyPlay YES`: show nearby play while its switch is off (trying it on two
    /// phones before it ships).
    static var nearbyPlay: Bool { flag("--nearby", defaultsKey: "nearbyPlay") || nearbyDemo }
    /// `--nearby-demo` / `-nearbyDemo YES`: Play nearby finds only the demo player, Ama (UI tests).
    static var nearbyDemo: Bool { flag("--nearby-demo", defaultsKey: "nearbyDemo") }
    /// `--demo-resign-after=N`: Ama resigns her first game once she has made N moves.
    static var demoResignAfter: Int? { number("--demo-resign-after=", defaultsKey: "demoResignAfter") }
    /// `--demo-quiet-after=N`: Ama's phone goes quiet for twelve seconds after her Nth move.
    static var demoQuietAfter: Int? { number("--demo-quiet-after=", defaultsKey: "demoQuietAfter") }
    /// `--nearby-local-network-off` / `--nearby-wifi-off`: Play nearby acts as if the phone said
    /// so (NearbyAccessUITests; a simulator cannot switch either off).
    static var nearbyLocalNetworkOff: Bool { flag("--nearby-local-network-off") }
    static var nearbyWiFiOff: Bool { flag("--nearby-wifi-off") }
    /// `--demo-drop-after=N`: Ama's connection drops after her Nth move (the reconnect UI tests).
    static var demoDropAfter: Int? { number("--demo-drop-after=", defaultsKey: "demoDropAfter") }
    /// `--demo-away=S`: and she is back after S seconds (3 by default).
    static var demoAway: Double? { number("--demo-away=", defaultsKey: "demoAway").map(Double.init) }
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
