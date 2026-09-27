import Foundation

/// An online match as it travels between two phones (for example as Game Center turn-based match
/// data). It holds only the rules and the houses played; every copy is replayed through the rules
/// engine, so a tampered or out-of-date message is refused instead of trusted.
public struct OnlineMatch: Sendable, Codable, Hashable {
    /// Bump when the format changes; older apps refuse newer matches rather than misread them.
    public static let formatVersion = 1
    /// Game Center turn-based match data is limited to 64 KB; a whole Oware game is far smaller.
    public static let maxEncodedBytes = 64 * 1024

    public enum Failure: Error, Equatable {
        case newerFormat(Int)
        case illegalMove(ply: Int, house: Int)
        case tooLarge
        case gameIsOver
    }

    public var version: Int
    public var rules: RuleSet
    /// Absolute houses (0–11) in the order they were played; the mover is whoever was to move.
    public var houses: [Int]
    /// Set when a player resigned; the other player wins.
    public var resignedBy: Player?

    public init(rules: RuleSet, houses: [Int] = [], resignedBy: Player? = nil) {
        self.version = Self.formatVersion
        self.rules = rules
        self.houses = houses
        self.resignedBy = resignedBy
    }

    /// The position after every move, checked against the rules.
    public func state() throws -> GameState {
        var state = GameState.initial(rules: rules)
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
    public func playing(_ house: Int) throws -> OnlineMatch {
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

    public func resigning(_ player: Player) throws -> OnlineMatch {
        guard try !state().isOver else { throw Failure.gameIsOver }
        var next = self
        next.resignedBy = player
        return next
    }

    public func encoded() throws -> Data {
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maxEncodedBytes else { throw Failure.tooLarge }
        return data
    }

    /// Decodes and validates a received match.
    public static func decode(_ data: Data) throws -> OnlineMatch {
        let match = try JSONDecoder().decode(OnlineMatch.self, from: data)
        guard match.version <= formatVersion else { throw Failure.newerFormat(match.version) }
        _ = try match.state()
        return match
    }
}
