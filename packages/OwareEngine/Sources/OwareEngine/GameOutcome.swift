public enum GameEndReason: String, Sendable, Codable, Hashable {
    /// A player reached the winning number of seeds.
    case reachedWinningSeeds
    /// All 48 seeds have been captured.
    case boardEmpty
    /// The mover could not give the opponent any seeds; the mover kept their own side.
    case opponentCouldNotBeFed
    /// The position repeated; each player kept the seeds on their side.
    case repetition
    /// The side to move had no legal move (only possible in variants without the feeding rule,
    /// or when every move would be an illegal grand slam). Remaining seeds go to the player who
    /// still had seeds, or each side keeps its own.
    case noLegalMoves
    /// A grand-slam capture ended the game (only under `captureEndsGame`).
    case grandSlam
    /// Both players agreed to stop; each kept the seeds on their side.
    case agreement
}

public enum GameOutcome: Sendable, Codable, Hashable {
    case win(Player, GameEndReason)
    case draw(GameEndReason)

    public var winner: Player? {
        if case let .win(p, _) = self { return p }
        return nil
    }

    public var reason: GameEndReason {
        switch self {
        case let .win(_, r), let .draw(r): return r
        }
    }
}
