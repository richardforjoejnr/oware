/// One token's move for the current roll.
public struct Move: Sendable, Codable, Hashable, CustomStringConvertible {
    public enum Kind: String, Sendable, Codable {
        /// Out of the yard onto the start square.
        case enter
        /// Forwards by the roll (along the track, into the home lane, or home).
        case forward
        /// Backwards by the roll onto an opponent, kicking it home (`RuleSet.backKick`).
        case backKick
        /// Into an opponent's home lane with the exact roll, kicking them (`RuleSet.homeKick`).
        case homeKick
        /// A visitor in another colour's lane moving back out (and on, if the roll is long enough).
        case walkOut
        /// Forwards (or backwards) by the roll, then across a home lane onto an opponent.
        case sideKickForward, sideKickBack
    }

    /// A token standing in another colour's home lane after a home kick.
    public struct Visit: Sendable, Codable, Hashable {
        public let owner: PlayerColor
        /// 1 is the lane square next to its entrance, 5 the one next to the centre.
        public let depth: Int
        public init(owner: PlayerColor, depth: Int) { self.owner = owner; self.depth = depth }
    }

    public let token: Int
    public let kind: Kind
    /// Progress before and after (yard is -1, home 56). A visitor's progress is that of the lane's
    /// entrance square on its own journey.
    public let from: Int
    public let to: Int
    /// Where the token ends up if that is inside another colour's lane (home kick, walking out).
    public let visit: Visit?

    public init(token: Int, kind: Kind, from: Int, to: Int, visit: Visit? = nil) {
        self.token = token
        self.kind = kind
        self.from = from
        self.to = to
        self.visit = visit
    }

    public var description: String {
        "token \(token) \(kind.rawValue) \(from)→\(to)" + (visit.map { " in \($0.owner)'s lane at \($0.depth)" } ?? "")
    }
}

/// What happened, in order, for the app to animate and announce.
public enum GameEvent: Sendable, Codable, Hashable {
    case rolled(PlayerColor, Int)
    case moved(PlayerColor, Move)
    /// `token` of `color` was kicked home from track index `at`.
    case kicked(PlayerColor, token: Int, at: Int, by: PlayerColor)
    /// `token` of `color` was kicked home from square `depth` of `lane`'s home lane (a home kick, or a
    /// lane's owner landing on a visitor).
    case kickedInLane(PlayerColor, token: Int, lane: PlayerColor, depth: Int, by: PlayerColor)
    case reachedHome(PlayerColor, token: Int)
    /// A third 6: the turn's moves are undone and play passes.
    case threeSixes(PlayerColor)
    /// No legal move for the roll.
    case passed(PlayerColor)
    case rollAgain(PlayerColor)
    case turn(PlayerColor)
    case won(PlayerColor)
}
