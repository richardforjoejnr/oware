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
    /// Names people gave themselves (pass & play); a colour without one is called by its colour.
    var names: [PlayerColor: String] = [:]

    init(seats: [PlayerColor: Seat], rules: RuleSet = .ghana, names: [PlayerColor: String] = [:]) {
        self.seats = seats
        self.rules = rules
        self.names = names.compactMapValues(Self.cleanName)
    }

    // Saves from before names existed have no `names`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(seats: try c.decode([PlayerColor: Seat].self, forKey: .seats),
                  rules: try c.decodeIfPresent(RuleSet.self, forKey: .rules) ?? .ghana,
                  names: try c.decodeIfPresent([PlayerColor: String].self, forKey: .names) ?? [:])
    }

    /// The longest name kept, so it fits the tray and the status plaque.
    static let nameLimit = 14

    /// A name as typed, tidied: spaces trimmed, cut to `nameLimit`; nil when nothing is left.
    static func cleanName(_ raw: String) -> String? {
        let name = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameLimit))
        return name.isEmpty ? nil : name
    }

    var colors: [PlayerColor] { PlayerColor.allCases.filter { seats[$0] != nil } }
    func seat(_ color: PlayerColor) -> Seat { seats[color] ?? .human }

    /// The colours computers take against you, in order: the seat opposite first, then the two beside.
    static func opponentColours(for you: PlayerColor, count: Int) -> [PlayerColor] {
        let i = you.rawValue
        return [(i + 2) % 4, (i + 1) % 4, (i + 3) % 4].compactMap(PlayerColor.init(rawValue:)).prefix(max(1, min(3, count))).map { $0 }
    }

    /// You, in the colour you chose, against 1–3 computers in the colours left.
    static func versusComputer(you: PlayerColor = .red, opponents: Int, level: LudoAIDifficulty, rules: RuleSet) -> GameSetup {
        var seats: [PlayerColor: Seat] = [you: .human]
        for c in opponentColours(for: you, count: opponents) { seats[c] = .computer(level) }
        return GameSetup(seats: seats, rules: rules)
    }

    /// People on one device, each in a colour of their own (a colour can't be taken twice: they are
    /// the keys), with the names they gave (none: called by their colour). 2–4 players, or nil.
    static func passAndPlay(_ players: [PlayerColor: String], rules: RuleSet) -> GameSetup? {
        guard (2...4).contains(players.count) else { return nil }
        return GameSetup(seats: players.mapValues { _ in Seat.human }, rules: rules, names: players)
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
