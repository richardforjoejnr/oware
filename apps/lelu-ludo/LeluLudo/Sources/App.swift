import SwiftUI

@main
struct LeluLudoApp: App {
    @State private var session: LudoSession

    init() {
        if LaunchOptions.resetState {
            GameStore.shared.clear()
            if let domain = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: domain) }
        }
        let dice: DiceSource = LaunchOptions.dice.map { ScriptedDice($0) } ?? RandomDice()
        let session = LudoSession(dice: dice)
        if LaunchOptions.fast { session.computerPause = .zero }
        if LaunchOptions.startGame { session.newGame(GameSetup(seats: [.red: .human, .black: .computer(.novice)])) }
        _session = State(initialValue: session)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @State private var inGame = LaunchOptions.startGame

    var body: some View {
        if inGame {
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
    /// `--fast`: computer turns without pauses (UI tests).
    static var fast: Bool { arguments.contains("--fast") }
}
