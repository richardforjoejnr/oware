import LudoEngine
import SwiftUI

@main
struct LeluLudoApp: App {
    @State private var session: LudoSession
    @State private var settings: AppSettings

    init() {
        if LaunchOptions.resetState {
            GameStore.shared.clear()
            if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
        }
        let dice: DiceSource = LaunchOptions.dice.map { ScriptedDice($0) } ?? RandomDice()
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        let session = LudoSession(dice: dice, feedback: DeviceFeedback(settings: settings))
        if LaunchOptions.fast { session.pacing = .instant }
        if LaunchOptions.startGame { session.newGame(.versusComputer(opponents: 1, level: .novice, rules: settings.rules)) }
        if let scenario = LaunchOptions.scenario { session.load(scenario) }
        if LaunchOptions.tutorial { session.startTutorial() }
        _session = State(initialValue: session)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(settings)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @State private var inGame = LaunchOptions.startGame || LaunchOptions.scenario != nil || LaunchOptions.tutorial
    /// The opening card, skipped by tests and when opening straight onto a game.
    @State private var splash = !LaunchOptions.testMode && !LaunchOptions.startGame && LaunchOptions.scenario == nil && !LaunchOptions.tutorial

    var body: some View {
        if splash {
            SplashView { withAnimation(.easeOut(duration: 0.4)) { splash = false } }
        } else if inGame {
            GameView(goHome: { inGame = false })
        } else {
            HomeView(startGame: { inGame = true })
        }
    }
}

/// Launch arguments for tests and screenshots; compiled out of release builds.
enum LaunchOptions {
    #if DEBUG
    private static let enabled = true
    #else
    private static let enabled = false
    #endif
    private static var arguments: [String] { enabled ? CommandLine.arguments : [] }

    /// `--reset-state`: start as a fresh install (no saved game, default settings).
    static var resetState: Bool { arguments.contains("--reset-state") }
    /// `--dice=6,4,3`: the die plays these faces in order, then repeats.
    static var dice: [Int]? { arguments.lazy.compactMap(ScriptedDice.parse).first }
    /// `--start-game`: open straight onto a new game, you (red) against a Novice (black).
    static var startGame: Bool { arguments.contains("--start-game") }
    /// `--scenario=back-kick`: open on an arranged position (UI tests, screenshots).
    static var scenario: Scenario? { arguments.lazy.compactMap { $0.hasPrefix("--scenario=") ? Scenario(rawValue: String($0.dropFirst(11))) : nil }.first }
    /// `--tutorial`: open straight onto Learn the game's first lesson.
    static var tutorial: Bool { arguments.contains("--tutorial") }
    /// Any test run (UI tests pass `--fast`; unit tests run inside XCTest): silent, nothing persisted
    /// about the player's own choices.
    static var testMode: Bool {
        fast || (enabled && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil)
    }
    /// `--fast`: computer turns without pauses (UI tests).
    static var fast: Bool { arguments.contains("--fast") }
}

/// Positions for UI tests and screenshots.
enum Scenario: String {
    /// You (red) on track 12, a Black token on track 7: a 5 can move on or back-kick it.
    case backKick = "back-kick"

    var game: (GameSetup, GameState) {
        switch self {
        case .backKick:
            let black = GameState.progress(of: .black, atTrackIndex: 7)
            return (GameSetup(seats: [.red: .human, .black: .computer(.novice)]),
                    GameState.arranged(players: [.red, .black], toMove: .red, tokens: [.red: [12, -1, -1, -1], .black: [black, -1, -1, -1]]))
        }
    }
}
