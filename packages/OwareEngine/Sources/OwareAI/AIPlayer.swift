import OwareEngine

/// Deterministic seeded RNG (SplitMix64) so AI behaviour is reproducible in tests and replays.
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

/// A computer opponent. Value type; safe to use from any task.
public struct AIPlayer: Sendable, Hashable, Codable {
    public var difficulty: Difficulty
    public var personality: Personality

    public init(difficulty: Difficulty = .player, personality: Personality = .balanced) {
        self.difficulty = difficulty
        self.personality = personality
    }

    /// Pick a move for the side to move. Returns nil if the game is over.
    /// Heavy: call from a background task. Honours the difficulty's time budget and depth.
    public func chooseMove(for state: GameState, seed: UInt64 = 0) -> Move? {
        var rng = SeededGenerator(seed: seed ^ UInt64(state.moveNumber &* 0x9E37_79B9))
        return chooseMove(for: state, using: &rng)
    }

    public func chooseMove<G: RandomNumberGenerator>(for state: GameState, using rng: inout G) -> Move? {
        let moves = state.legalMoves()
        guard !moves.isEmpty else { return nil }
        if moves.count == 1 { return moves[0] }
        if difficulty.blunderRate > 0, Double.random(in: 0..<1, using: &rng) < difficulty.blunderRate {
            return moves.randomElement(using: &rng)
        }
        return analyse(state)?.move ?? moves[0]
    }

    /// Full analysis of the position (used for hints and the CLI).
    public func analyse(_ state: GameState) -> MoveAnalysis? {
        var searcher = Searcher(weights: personality.weights, deadline: ContinuousClock.now + difficulty.timeBudget)
        return searcher.search(state, maxDepth: difficulty.maxDepth)
    }

    /// Analysis with explicit limits, independent of difficulty (used by tests and the hint system).
    public static func analyse(_ state: GameState, depth: Int, timeBudget: Duration? = nil, weights: EvaluationWeights = .balanced) -> MoveAnalysis? {
        let deadline = timeBudget.map { ContinuousClock.now + $0 }
        var searcher = Searcher(weights: weights, deadline: deadline)
        return searcher.search(state, maxDepth: depth)
    }
}
