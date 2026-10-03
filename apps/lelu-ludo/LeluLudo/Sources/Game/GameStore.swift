import Foundation
import LudoAI
import LudoEngine

/// Who sits at each colour.
enum Seat: Codable, Hashable, Sendable {
    case human
    case computer(LudoAIDifficulty)
}

/// LudoAI's levels under a name of their own in the app.
typealias LudoAIDifficulty = LudoAI.Difficulty

/// The players and rules for a game.
struct GameSetup: Codable, Hashable, Sendable {
    var seats: [PlayerColor: Seat]
    var rules: RuleSet = .ghana

    var colors: [PlayerColor] { PlayerColor.allCases.filter { seats[$0] != nil } }
    func seat(_ color: PlayerColor) -> Seat { seats[color] ?? .human }
}

/// The game in progress, saved so the player can resume after relaunch.
struct SavedGame: Codable, Sendable, Hashable {
    var setup: GameSetup
    var state: GameState
    var aiSeed: UInt64
}

/// JSON in Application Support, as Lelu Oware does.
final class GameStore: Sendable {
    static let shared = GameStore()
    private let url: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LeluLudo", isDirectory: true)
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

    func clear() { try? FileManager.default.removeItem(at: url) }
}
