import Foundation
import OwareEngine

/// The game in progress, saved so the player can resume after relaunch.
struct SavedGame: Codable, Sendable, Hashable {
    var state: GameState
    var mode: GameMode
    var history: [GameState]
}

/// JSON persistence in Application Support. Kept tiny on purpose; SwiftData is overkill here.
final class GameStore: Sendable {
    static let shared = GameStore()

    private let url: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LeluOware", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("current-game.json")
    }

    func load() -> SavedGame? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SavedGame.self, from: data)
    }

    func save(_ game: SavedGame) {
        guard let data = try? JSONEncoder().encode(game) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
