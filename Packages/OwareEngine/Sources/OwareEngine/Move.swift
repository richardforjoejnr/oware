import Foundation

/// A move: the player scoops one of their six houses. `house` is 0–5 relative to the player
/// (0 is the leftmost house from that player's own seat).
public struct Move: Sendable, Codable, Hashable, CustomStringConvertible {
    public let player: Player
    public let house: Int

    public init(player: Player, house: Int) {
        precondition((0..<6).contains(house), "house must be 0...5")
        self.player = player
        self.house = house
    }

    /// Absolute board index 0–11.
    public var absoluteIndex: Int { player.houseRange.lowerBound + house }

    /// Notation such as "A3" or "B6".
    public var notation: String { "\(player.label)\(house + 1)" }

    /// Parse notation such as "A3" / "b6". Returns nil for anything else.
    public init?(notation: String) {
        let text = notation.trimmingCharacters(in: .whitespaces).uppercased()
        guard text.count == 2,
              let player = Player(label: String(text.prefix(1))),
              let n = Int(text.suffix(1)), (1...6).contains(n) else { return nil }
        self.init(player: player, house: n - 1)
    }

    public var description: String { notation }
}

public enum MoveError: Error, Sendable, Equatable {
    case gameIsOver
    case notYourTurn
    case emptyHouse
    /// The opponent has no seeds and this move would not give them any, but another move would.
    case mustFeedOpponent
    /// Under `RuleSet.GrandSlamRule.illegalMove`, this move would capture all opponent seeds.
    case grandSlamNotAllowed
}

/// Everything that happened during one move, in order, so the UI can animate it.
public enum MoveEvent: Sendable, Codable, Hashable {
    /// All seeds lifted from the origin house.
    case pickUp(house: Int, seeds: Int)
    /// One seed dropped into `house`, leaving it with `count` seeds.
    case sow(house: Int, count: Int)
    /// The origin house was skipped on a lap (12+ seeds).
    case skipOrigin(house: Int)
    /// `seeds` captured from `house` by `player`.
    case capture(house: Int, seeds: Int, by: Player)
    /// A capture of all opponent seeds was forfeited under the grand-slam rule.
    case grandSlamForfeited(by: Player, houses: [Int])
    /// Remaining seeds on `player`'s side moved to their store at game end.
    case sweep(player: Player, seeds: Int)
    case gameOver(GameOutcome)
}

public struct MoveResult: Sendable, Hashable {
    public let move: Move
    public let events: [MoveEvent]
    public let state: GameState
}
