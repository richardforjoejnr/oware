import SwiftUI

@main
struct OwareApp: App {
    @State private var session: GameSession
    @State private var settings: AppSettings

    init() {
        // Launch options used by UI tests: `--reset-state` / `-resetState YES` wipe the saved game,
        // `--fast-animations` / `-fastAnimations YES` make everything instant and silent.
        if LaunchOptions.resetState { GameStore.shared.clear() }
        _session = State(initialValue: GameSession())
        _settings = State(initialValue: AppSettings())
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

enum LaunchOptions {
    static var resetState: Bool {
        CommandLine.arguments.contains("--reset-state") || UserDefaults.standard.bool(forKey: "resetState")
    }
    static var fastAnimations: Bool {
        CommandLine.arguments.contains("--fast-animations") || UserDefaults.standard.bool(forKey: "fastAnimations")
    }
}
