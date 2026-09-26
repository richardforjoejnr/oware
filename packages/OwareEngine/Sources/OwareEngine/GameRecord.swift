import Foundation

/// A full game: starting rules plus the move list, replayable to any point.
/// Notation is a space-separated list such as "A3 B1 A6 B4".
public struct GameRecord: Sendable, Codable, Hashable {
    public var rules: RuleSet
    public var moves: [Move]
    public var endedByAgreement: Bool

    public init(rules: RuleSet = .abapa, moves: [Move] = [], endedByAgreement: Bool = false) {
        self.rules = rules
        self.moves = moves
        self.endedByAgreement = endedByAgreement
    }

    public var notation: String { moves.map(\.notation).joined(separator: " ") }

    /// Parse a notation string. Returns nil if any token is invalid.
    public init?(notation: String, rules: RuleSet = .abapa) {
        var moves: [Move] = []
        for token in notation.split(whereSeparator: \.isWhitespace) {
            guard let move = Move(notation: String(token)) else { return nil }
            moves.append(move)
        }
        self.init(rules: rules, moves: moves)
    }

    /// Replay the first `count` moves (all by default). Throws on the first illegal move.
    public func replay(upTo count: Int? = nil) throws -> GameState {
        var state = GameState.initial(rules: rules)
        for move in moves.prefix(count ?? moves.count) {
            try state.apply(move)
        }
        if endedByAgreement, (count ?? moves.count) >= moves.count {
            _ = state.endByAgreement()
        }
        return state
    }

    /// Every intermediate state, index 0 being the initial position.
    public func states() throws -> [GameState] {
        var state = GameState.initial(rules: rules)
        var out = [state]
        for move in moves {
            try state.apply(move)
            out.append(state)
        }
        return out
    }
}
