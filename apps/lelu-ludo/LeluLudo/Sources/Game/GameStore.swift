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

    /// You (red) against 1–3 computers: opposite first (black), then beside (yellow, green).
    static func versusComputer(opponents: Int, level: LudoAIDifficulty, rules: RuleSet) -> GameSetup {
        var seats: [PlayerColor: Seat] = [.red: .human]
        for c in [PlayerColor.black, .yellow, .green].prefix(max(1, min(3, opponents))) { seats[c] = .computer(level) }
        return GameSetup(seats: seats, rules: rules)
    }

    /// 2–4 people on one phone: red and black face each other, then yellow and green join.
    static func passAndPlay(players: Int, rules: RuleSet) -> GameSetup {
        let order: [PlayerColor] = [.red, .black, .yellow, .green]
        return GameSetup(seats: Dictionary(uniqueKeysWithValues: order.prefix(max(2, min(4, players))).map { ($0, Seat.human) }), rules: rules)
    }
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
