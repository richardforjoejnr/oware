import Foundation

/// The old name, from before nearby play. Kept until every caller has moved to `OwareMatch`.
public typealias OnlineMatch = OwareMatch

/// What a phone asks the host to do. The host applies it to its `OwareMatch` and, if the rules
/// allow it, sends everyone the new match.
public enum OwareIntent: Sendable, Codable, Hashable {
    case play(house: Int)
    case resign
    /// Both players have asked for another game.
    case rematch
}

/// A match as it travels between two phones, nearby or (later) as Game Center turn-based match
/// data. It holds only the rules, who started and the houses played; every copy is replayed
/// through the rules engine, so a tampered or out-of-date message is refused instead of trusted.
public struct OwareMatch: Sendable, Codable, Hashable {
    /// Bump when the format changes; older apps refuse newer matches rather than misread them.
    /// Version 2 added `starter`, `matchID` and `game`; version 1 data still decodes.
    public static let formatVersion = 2
    /// Game Center turn-based match data is limited to 64 KB; a whole Oware game is far smaller.
    public static let maxEncodedBytes = 64 * 1024

    public enum Failure: Error, Equatable {
        case newerFormat(Int)
        case illegalMove(ply: Int, house: Int)
        case tooLarge
        case gameIsOver
        case notYourTurn
        /// A rematch was asked for before the game ended.
        case gameNotOver
    }

    public var version: Int
    public var rules: RuleSet
    /// Who sowed first. The other player starts the rematch.
    public var starter: Player
    /// Tells this game apart from others, for rejoining and so an old game's messages are ignored.
    public var matchID: UUID
    /// 1 for the first game between these phones, 2 for the first rematch, and so on.
    public var game: Int
    /// Absolute houses (0–11) in the order they were played; the mover is whoever was to move.
    public var houses: [Int]
    /// Set when a player resigned; the other player wins.
    public var resignedBy: Player?

    public init(
        rules: RuleSet,
        starter: Player = .south,
        matchID: UUID = UUID(),
        game: Int = 1,
        houses: [Int] = [],
        resignedBy: Player? = nil
    ) {
        self.version = Self.formatVersion
        self.rules = rules
        self.starter = starter
        self.matchID = matchID
        self.game = game
        self.houses = houses
        self.resignedBy = resignedBy
    }

    private enum CodingKeys: String, CodingKey {
        case version, rules, starter, matchID, game, houses, resignedBy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        rules = try c.decode(RuleSet.self, forKey: .rules)
        // Version 1 matches always started with South and had no id.
        starter = try c.decodeIfPresent(Player.self, forKey: .starter) ?? .south
        matchID = try c.decodeIfPresent(UUID.self, forKey: .matchID) ?? UUID()
        game = try c.decodeIfPresent(Int.self, forKey: .game) ?? 1
        houses = try c.decode([Int].self, forKey: .houses)
        resignedBy = try c.decodeIfPresent(Player.self, forKey: .resignedBy)
    }

    /// The position after every move, checked against the rules.
    public func state() throws -> GameState {
        var state = GameState(
            houses: Array(repeating: GameState.seedsPerHouse, count: GameState.houseCount),
            sideToMove: starter,
            rules: rules
        )
        for (ply, house) in houses.enumerated() {
            guard (0..<GameState.houseCount).contains(house) else { throw Failure.illegalMove(ply: ply, house: house) }
            let move = Move(player: state.sideToMove, absoluteHouse: house)
            guard state.isLegal(move) else { throw Failure.illegalMove(ply: ply, house: house) }
            try state.apply(move)
        }
        if let loser = resignedBy, !state.isOver {
            state.outcome = .win(loser.opponent, .agreement)
        }
        return state
    }

    /// Whose turn it is, or nil when the match has ended.
    public func playerToMove() throws -> Player? {
        let s = try state()
        return s.isOver ? nil : s.sideToMove
    }

    /// This match with one more move, refused if the move is not legal now.
    public func playing(_ house: Int) throws -> OwareMatch {
        let current = try state()
        guard !current.isOver else { throw Failure.gameIsOver }
        guard (0..<GameState.houseCount).contains(house),
              current.isLegal(Move(player: current.sideToMove, absoluteHouse: house)) else {
            throw Failure.illegalMove(ply: houses.count, house: house)
        }
        var next = self
        next.houses.append(house)
        return next
    }

    public func resigning(_ player: Player) throws -> OwareMatch {
        guard try !state().isOver else { throw Failure.gameIsOver }
        var next = self
        next.resignedBy = player
        return next
    }

    /// The match after `player` asks for `intent`, or the reason the host refuses it.
    public func applying(_ intent: OwareIntent, from player: Player) throws -> OwareMatch {
        switch intent {
        case let .play(house):
            guard let mover = try playerToMove() else { throw Failure.gameIsOver }
            guard mover == player else { throw Failure.notYourTurn }
            return try playing(house)
        case .resign:
            return try resigning(player)
        case .rematch:
            guard try state().isOver else { throw Failure.gameNotOver }
            return OwareMatch(rules: rules, starter: starter.opponent, game: game + 1)
        }
    }

    /// Whether a phone holding `current` should take this match in its place: a later game, or
    /// the same game carried further. Repeats, stale copies and other games are ignored.
    public func supersedes(_ current: OwareMatch) -> Bool {
        if game != current.game { return game > current.game }
        guard matchID == current.matchID, rules == current.rules, starter == current.starter,
              houses.starts(with: current.houses) else { return false }
        if current.resignedBy != nil { return false }
        return houses.count > current.houses.count || resignedBy != nil
    }

    public func encoded() throws -> Data {
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maxEncodedBytes else { throw Failure.tooLarge }
        return data
    }

    /// Decodes and validates a received match.
    public static func decode(_ data: Data) throws -> OwareMatch {
        let match = try JSONDecoder().decode(OwareMatch.self, from: data)
        guard match.version <= formatVersion else { throw Failure.newerFormat(match.version) }
        _ = try match.state()
        return match
    }
}
