import SwiftUI

@main
struct OwareApp: App {
    @State private var session: GameSession
    @State private var settings: AppSettings
    @State private var library = PuzzleLibrary()
    @State private var progress = JourneyProgress()
    @State private var store = StoreManager()

    init() {
        // Launch options used by UI tests: `--reset-state` / `-resetState YES` wipe the saved game,
        // `--fast-animations` / `-fastAnimations YES` make everything instant and silent.
        if LaunchOptions.resetState {
            GameStore.shared.clear()
            UserDefaults.standard.removeObject(forKey: "solvedPuzzleIDs")
            UserDefaults.standard.removeObject(forKey: "journeyStars")
            UserDefaults.standard.removeObject(forKey: "hasFullJourney")
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
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}

enum LaunchOptions {
    static var resetState: Bool {
        CommandLine.arguments.contains("--reset-state") || UserDefaults.standard.bool(forKey: "resetState")
    }
    /// `--unlock-all` / `-unlockAll YES`: treat the full Journey as owned (UI tests, screenshots).
    static var unlockAll: Bool {
        CommandLine.arguments.contains("--unlock-all") || UserDefaults.standard.bool(forKey: "unlockAll")
    }
    static var fastAnimations: Bool {
        CommandLine.arguments.contains("--fast-animations") || UserDefaults.standard.bool(forKey: "fastAnimations")
    }
}
