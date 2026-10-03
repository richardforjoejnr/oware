/// One token's move for the current roll.
public struct Move: Sendable, Codable, Hashable, CustomStringConvertible {
    public enum Kind: String, Sendable, Codable {
        /// Out of the yard onto the start square.
        case enter
        /// Forwards by the roll (along the track, into the home lane, or home).
        case forward
        /// Backwards by the roll onto an opponent, kicking it home (`RuleSet.backKick`).
        case backKick
    }

    public let token: Int
    public let kind: Kind
    /// Progress before and after (yard is -1, home 56).
    public let from: Int
    public let to: Int

    public init(token: Int, kind: Kind, from: Int, to: Int) {
        self.token = token
        self.kind = kind
        self.from = from
        self.to = to
    }

    public var description: String { "token \(token) \(kind.rawValue) \(from)→\(to)" }
}

/// What happened, in order, for the app to animate and announce.
public enum GameEvent: Sendable, Codable, Hashable {
    case rolled(PlayerColor, Int)
    case moved(PlayerColor, Move)
    /// `token` of `color` was kicked home from track index `at`.
    case kicked(PlayerColor, token: Int, at: Int, by: PlayerColor)
    case reachedHome(PlayerColor, token: Int)
    /// A third 6: the turn's moves are undone and play passes.
    case threeSixes(PlayerColor)
    /// No legal move for the roll.
    case passed(PlayerColor)
    case rollAgain(PlayerColor)
    case turn(PlayerColor)
    case won(PlayerColor)
}
