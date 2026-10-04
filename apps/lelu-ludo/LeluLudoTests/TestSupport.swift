import Foundation
@testable import LeluLudo

/// Each test gets its own save folder and settings, so tests never depend on one another.
@MainActor
enum TestSupport {
    static func store() -> GameStore {
        GameStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    static func defaults() -> UserDefaults {
        let name = "LeluLudoTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    /// A session with scripted dice and no pauses between computer moves.
    static func session(dice: [Int], store: GameStore? = nil) -> LudoSession {
        let s = LudoSession(store: store ?? self.store(), dice: ScriptedDice(dice))
        s.pacing = .instant
        return s
    }
}
