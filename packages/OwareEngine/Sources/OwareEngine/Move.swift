import Foundation

/// A move: which player sows, and from which of the twelve houses. Houses are addressed by their
/// physical position (0–5 the south row A1–A6, 6–11 the north row B1–B6); under Nam-Nam a player may
/// own houses on either row, so the mover is stored separately from the house.
public struct Move: Sendable, Hashable, CustomStringConvertible {
    public let player: Player
    public let absoluteIndex: Int

    /// Abapa-style: `house` 0–5 within the player's own row.
    public init(player: Player, house: Int) {
        precondition((0..<6).contains(house), "house must be 0...5")
        self.player = player
        self.absoluteIndex = player.houseRange.lowerBound + house
    }

    /// Any house on the board (Nam-Nam territory can be on either row).
    public init(player: Player, absoluteHouse: Int) {
        precondition((0..<GameState.houseCount).contains(absoluteHouse), "house must be 0...11")
        self.player = player
        self.absoluteIndex = absoluteHouse
    }

    /// Position within the physical row (0–5).
    public var house: Int { absoluteIndex % 6 }

    /// Physical notation: A1–A6 for the south row, B1–B6 for the north row.
    public var notation: String { "\(absoluteIndex < 6 ? "A" : "B")\(house + 1)" }

    /// Parses physical notation; the player defaults to the row's usual owner. Replays under
    /// Nam-Nam re-attribute the mover from the side to move.
    public init?(notation: String) {
        let text = notation.trimmingCharacters(in: .whitespaces).uppercased()
        guard text.count == 2,
              let player = Player(label: String(text.prefix(1))),
              let n = Int(text.suffix(1)), (1...6).contains(n) else { return nil }
        self.init(player: player, house: n - 1)
    }

    public var description: String { notation }
}

extension Move: Codable {
    private enum CodingKeys: String, CodingKey { case player, house, absoluteIndex }

    /// Throws `DecodingError.dataCorrupted` for a house off the board rather than trapping.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let player = try c.decode(Player.self, forKey: .player)
        if let absolute = try c.decodeIfPresent(Int.self, forKey: .absoluteIndex) {
            guard (0..<GameState.houseCount).contains(absolute) else {
                throw DecodingError.dataCorruptedError(forKey: .absoluteIndex, in: c, debugDescription: "house must be 0...11")
            }
            self.init(player: player, absoluteHouse: absolute)
        } else {
            let house = try c.decode(Int.self, forKey: .house)   // pre-Nam-Nam saves
            guard (0..<6).contains(house) else {
                throw DecodingError.dataCorruptedError(forKey: .house, in: c, debugDescription: "house must be 0...5")
            }
            self.init(player: player, house: house)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(player, forKey: .player)
        try c.encode(absoluteIndex, forKey: .absoluteIndex)
    }
}

public enum MoveError: Error, Sendable, Equatable {
    case gameIsOver
    case notYourTurn
    case notYourHouse
    case emptyHouse
    case mustFeedOpponent
    case grandSlamNotAllowed
}

/// What one round of Nam-Nam settled.
public struct RoundResult: Sendable, Codable, Hashable {
    public let round: Int
    public let southSeeds: Int
    public let northSeeds: Int
    public let southHouses: Int
    public let northHouses: Int

    public init(round: Int, southSeeds: Int, northSeeds: Int, southHouses: Int, northHouses: Int) {
        self.round = round
        self.southSeeds = southSeeds
        self.northSeeds = northSeeds
        self.southHouses = southHouses
        self.northHouses = northHouses
    }

    public var winner: Player? {
        southSeeds == northSeeds ? nil : (southSeeds > northSeeds ? .south : .north)
    }
}

public enum MoveEvent: Sendable, Codable, Hashable {
    case pickUp(house: Int, seeds: Int)
    case sow(house: Int, count: Int)
    case skipOrigin(house: Int)
    /// Relay sowing: the last seed landed in a non-empty house, which is scooped up and sown on.
    case relay(house: Int, seeds: Int)
    case capture(house: Int, seeds: Int, by: Player)
    case grandSlamForfeited(by: Player, houses: [Int])
    case sweep(player: Player, seeds: Int)
    /// Nam-Nam: a round ended; the board is reset with the new territory (unless the game is over).
    case roundOver(RoundResult)
    case gameOver(GameOutcome)
}

public struct MoveResult: Sendable, Hashable {
    public let move: Move
    public let events: [MoveEvent]
    public let state: GameState
}
