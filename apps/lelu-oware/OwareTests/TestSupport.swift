import Foundation
@testable import Oware

/// Everything a test touches is its own: a fresh settings store, a fresh saved-game folder and a
/// private analytics recorder. No test reads what another wrote, so they pass in any order.
@MainActor
enum TestSupport {
    static func defaults() -> UserDefaults {
        let name = "OwareTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    static func store() -> GameStore {
        GameStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    /// A session with its own storage whose results go to `track` (nowhere by default), never to
    /// the app's analytics or Game Center.
    static func session(store: GameStore? = nil, track: @escaping (AnalyticsEvent) -> Void = { _ in }) -> GameSession {
        let s = GameSession(store: store ?? self.store())
        s.events = PlayerEvents(track: track, services: nil, defaults: defaults())
        return s
    }
}
