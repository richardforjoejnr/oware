import LudoEngine

/// Deterministic seeded RNG (SplitMix64), as Oware's AI uses, so games replay exactly in tests.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Levels, named as in Lelu Oware. Lower levels notice less and slip more.
public enum Difficulty: Int, Sendable, Codable, CaseIterable, Comparable {
    case novice, intermediate, strategist, grandmaster

    public static func < (a: Difficulty, b: Difficulty) -> Bool { a.rawValue < b.rawValue }

    /// Chance of a random legal move instead of the best one.
    public var slipRate: Double {
        switch self {
        case .novice: 0.5
        case .intermediate: 0.2
        case .strategist: 0.05
        case .grandmaster: 0
        }
    }

    public var displayName: String {
        switch self {
        case .novice: "Novice"
        case .intermediate: "Intermediate"
        case .strategist: "Strategist"
        case .grandmaster: "Grandmaster"
        }
    }
}

/// A computer opponent. Ludo is a dice game, so it weighs each legal move by what a good player
/// looks for rather than searching far ahead:
/// - Novice: progress, kicks and getting home.
/// - Intermediate: also back kicks, bringing tokens out and reaching the safe lane.
/// - Strategist: also danger (where opponents could hit with one roll, back kicks included),
///   escaping it, and building walls.
/// - Grandmaster: also the danger to all its tokens after the move, not just the one it moved.
public struct AIPlayer: Sendable, Hashable, Codable {
    public var difficulty: Difficulty

    public init(difficulty: Difficulty = .intermediate) { self.difficulty = difficulty }

    /// The move for the pending roll, or nil if there is none.
    public func chooseMove<G: RandomNumberGenerator>(_ state: GameState, using rng: inout G) -> Move? {
        let moves = state.legalMoves()
        guard !moves.isEmpty else { return nil }
        if moves.count == 1 { return moves[0] }
        if difficulty.slipRate > 0, Double.random(in: 0..<1, using: &rng) < difficulty.slipRate {
            return moves.randomElement(using: &rng)
        }
        // Highest score; ties go to the first (so a choice is always the same for the same position).
        var best = moves[0], bestScore = -Double.infinity
        for move in moves {
            let s = score(move, in: state)
            if s > bestScore { best = move; bestScore = s }
        }
        return best
    }

    /// How good a move looks to this level.
    public func score(_ move: Move, in state: GameState) -> Double {
        let me = state.toMove
        let level = difficulty
        var s = Double(move.to - move.from) * 0.5   // progress (negative for a back kick)

        // Kicks: worth more the further the victim had come.
        if move.to <= Board.lastTrackProgress {
            let square = Board.trackIndex(me, progress: move.to)
            for victim in state.occupants(at: square) where victim.color != me && !state.isSafe(square) {
                let theirs = state.tokens(of: victim.color)[victim.token]
                if move.kind == .backKick && level < .intermediate { continue }
                s += 20 + Double(theirs)
            }
        }
        if move.to == Board.home { s += 30 }
        guard level >= .intermediate else { return s }

        if move.kind == .enter { s += 12 }
        if move.from <= Board.lastTrackProgress && move.to > Board.lastTrackProgress { s += 15 }   // safe in the lane
        guard level >= .strategist else { return s }

        // Danger to the moved token where it lands, and relief from the danger it leaves.
        if move.to <= Board.lastTrackProgress {
            s -= Self.danger(at: Board.trackIndex(me, progress: move.to), for: me, in: state, ignoringToken: move.token) * (10 + Double(move.to))
        }
        if move.from >= 0 && move.from <= Board.lastTrackProgress {
            s += Self.danger(at: Board.trackIndex(me, progress: move.from), for: me, in: state, ignoringToken: move.token) * (10 + Double(move.from))
        }
        // Walls: joining your own token builds one; leaving a pair breaks it.
        if state.rules.stacking != .notAllowed {
            if move.to <= Board.lastTrackProgress, state.tokens(of: me).enumerated().contains(where: { $0.offset != move.token && $0.element == move.to }) { s += 8 }
            if move.from >= 0 && move.from <= Board.lastTrackProgress,
               state.tokens(of: me).enumerated().contains(where: { $0.offset != move.token && $0.element == move.from }) { s -= 6 }
        }
        guard level >= .grandmaster else { return s }

        // The whole position after the move: every token of ours left within an opponent's reach.
        var after = state
        if (try? after.apply(move)) != nil {
            s -= Self.exposure(of: me, in: after) * 0.5
        }
        return s
    }

    /// Chance (0…1) that some opponent can kick a token of `me` standing on this square next roll:
    /// forwards from up to six behind, by entering if it is their start square, and backwards from
    /// up to six ahead when back kicks are on. Safe squares and walls are out of reach.
    static func danger(at square: Int, for me: PlayerColor, in state: GameState, ignoringToken: Int? = nil) -> Double {
        if state.isSafe(square) { return 0 }
        let mine = state.tokens(of: me).enumerated().filter { $0.offset != ignoringToken && $0.element >= 0 && $0.element <= Board.lastTrackProgress }
        if state.rules.stacking != .notAllowed, mine.contains(where: { Board.trackIndex(me, progress: $0.element) == square }) { return 0 }
        var rolls = Set<Int>()
        for color in state.players where color != me {
            for p in state.tokens(of: color) {
                if p == Board.yard {
                    if square == Board.startIndex(color) { rolls.formUnion(state.rules.entryRolls) }
                    continue
                }
                guard p <= Board.lastTrackProgress else { continue }
                let at = Board.trackIndex(color, progress: p)
                let behind = (square - at + Board.trackLength) % Board.trackLength
                if (1...6).contains(behind) && p + behind <= Board.lastTrackProgress { rolls.insert(behind) }
                let ahead = (at - square + Board.trackLength) % Board.trackLength
                if state.rules.backKick, (1...6).contains(ahead), p - ahead >= 0 { rolls.insert(ahead) }
            }
        }
        return Double(rolls.count) / 6
    }

    /// Sum over our tokens on the track of danger × how far each has come.
    static func exposure(of me: PlayerColor, in state: GameState) -> Double {
        state.tokens(of: me).enumerated().reduce(0) { total, token in
            guard token.element >= 0 && token.element <= Board.lastTrackProgress else { return total }
            return total + danger(at: Board.trackIndex(me, progress: token.element), for: me, in: state) * (10 + Double(token.element))
        }
    }
}
