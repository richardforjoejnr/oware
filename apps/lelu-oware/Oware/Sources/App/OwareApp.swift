import SwiftUI
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

enum LaunchOptions {
    static var resetState: Bool {
        CommandLine.arguments.contains("--reset-state") || UserDefaults.standard.bool(forKey: "resetState")
    }
    /// `--start-game` / `-startGame YES`: open straight onto a new game against the Learner (screenshots).
    static var startGame: Bool {
        CommandLine.arguments.contains("--start-game") || UserDefaults.standard.bool(forKey: "startGame")
    }
    /// `--demo-move`: with `--start-game`, sow A1 a moment after launch (for animation checks).
    static var demoMove: Bool { CommandLine.arguments.contains("--demo-move") }
    /// `--screen=journey|puzzles|heritage`: open on that screen (screenshots).
    static var startScreen: String? {
        CommandLine.arguments.first { $0.hasPrefix("--screen=") }.map { String($0.dropFirst("--screen=".count)) }
    }
    static var fastAnimations: Bool {
        CommandLine.arguments.contains("--fast-animations") || UserDefaults.standard.bool(forKey: "fastAnimations")
    }
}
