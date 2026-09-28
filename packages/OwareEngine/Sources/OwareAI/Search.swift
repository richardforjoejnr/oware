import OwareEngine

/// Result of analysing a position.
public struct MoveAnalysis: Sendable, Hashable {
    public let move: Move
    /// Score from the side to move's point of view (see `Evaluation`).
    public let score: Int
    public let depth: Int
    public let nodes: Int
    public let principalVariation: [Move]
}

/// Compact transposition-table key: 12 houses × 6 bits + side to move.
struct PositionKey: Hashable {
    let lo: UInt64
    let hi: UInt64

    init(_ state: GameState) {
        var lo: UInt64 = 0
        var hi: UInt64 = 0
        for i in 0..<6 { lo |= UInt64(state.houses[i] & 0x3F) << (6 * i) }
        for i in 6..<12 { hi |= UInt64(state.houses[i] & 0x3F) << (6 * (i - 6)) }
        hi |= UInt64(state.sideToMove.rawValue) << 40
        // Nam-Nam: the same seeds mean different things with different territory or round.
        var owners: UInt64 = 0
        for i in 0..<12 where state.territory[i] == .north { owners |= 1 << UInt64(i) }
        hi |= owners << 41
        hi |= UInt64(truncatingIfNeeded: min(max(state.round, 0), 31)) << 53
        // Stores matter for terminal detection at the win threshold.
        lo |= UInt64(state.stores[0] & 0x3F) << 40
        lo |= UInt64(state.stores[1] & 0x3F) << 48
        self.lo = lo
        self.hi = hi
    }
}

/// Iterative-deepening alpha-beta (negamax) search with a transposition table and
/// captures-first move ordering. Deterministic for a given position and depth.
struct Searcher {
    enum Bound: UInt8 { case exact, lower, upper }
    struct Entry { let depth: Int; let score: Int; let bound: Bound; let best: Move? }

    let weights: EvaluationWeights
    let deadline: ContinuousClock.Instant?
    private(set) var nodes = 0
    private var table: [PositionKey: Entry] = [:]
    private var aborted = false
    /// Set when a score below the current node came from a repetition. Such scores depend on the
    /// moves that led here (the key does not include the position history), so they are not cached.
    private var sawRepetition = false

    /// Win/loss scores count plies from the root; in the table they count from the stored node, so
    /// an entry reused at another depth still prefers the quicker win.
    private static let winThreshold = Evaluation.winScore - 1_000
    private static func toTable(_ score: Int, ply: Int) -> Int {
        score >= winThreshold ? score + ply : (score <= -winThreshold ? score - ply : score)
    }
    private static func fromTable(_ score: Int, ply: Int) -> Int {
        score >= winThreshold ? score - ply : (score <= -winThreshold ? score + ply : score)
    }

    init(weights: EvaluationWeights, deadline: ContinuousClock.Instant?) {
        self.weights = weights
        self.deadline = deadline
    }

    /// Search to increasing depths until `maxDepth` or the deadline. Always returns the
    /// best move from the deepest *completed* iteration.
    mutating func search(_ root: GameState, maxDepth: Int) -> MoveAnalysis? {
        let moves = root.legalMoves()
        guard !moves.isEmpty else { return nil }
        if moves.count == 1 {
            return MoveAnalysis(move: moves[0], score: 0, depth: 0, nodes: 0, principalVariation: [moves[0]])
        }

        var best: MoveAnalysis?
        var rootOrder = orderedChildren(root)
        guard !rootOrder.isEmpty else { return nil }
        for depth in 1...max(1, maxDepth) {
            aborted = false
            // Explicit root loop so the chosen move never depends on a transposition-table entry
            // that a shallower re-visit of the root position could have overwritten.
            var alpha = -Evaluation.winScore * 2
            let beta = Evaluation.winScore * 2
            var iterationBest: (move: Move, score: Int)?
            for (move, next) in rootOrder {
                let score = childScore(next, parent: root, depth: depth - 1, ply: 1, alpha: alpha, beta: beta)
                if aborted { break }
                if iterationBest == nil || score > iterationBest!.score { iterationBest = (move, score) }
                alpha = max(alpha, score)
            }
            if aborted { break }
            guard let found = iterationBest else { break }
            best = MoveAnalysis(move: found.move, score: found.score, depth: depth, nodes: nodes,
                                principalVariation: principalVariation(from: root, first: found.move, maxLength: depth))
            // Search the previous best first next iteration.
            if let idx = rootOrder.firstIndex(where: { $0.move == found.move }) { rootOrder.swapAt(0, idx) }
            // Stop early on a forced win/loss.
            if abs(found.score) >= Evaluation.winScore - 64 { break }
        }
        return best ?? MoveAnalysis(move: rootOrder[0].move, score: 0, depth: 0, nodes: nodes, principalVariation: [])
    }

    /// Negamax value of `state` to `depth` plies with a full window, sharing this searcher's table
    /// (used by tests to compare against a plain search).
    mutating func value(of state: GameState, depth: Int) -> Int {
        negamax(state, depth: depth, ply: 0, alpha: -Evaluation.winScore * 2, beta: Evaluation.winScore * 2)
    }

    /// Score of `next` (reached by a move from `parent`) from the parent's side to move.
    private mutating func childScore(_ next: GameState, parent: GameState, depth: Int, ply: Int, alpha: Int, beta: Int) -> Int {
        if next.isOver {
            if next.outcome?.reason == .repetition || endedRoundByRepetition(next, parent: parent) { sawRepetition = true }
            // Terminal: evaluate from the mover's perspective.
            return Evaluation.score(next, for: parent.sideToMove, weights: weights, ply: ply)
        }
        if endedRoundByRepetition(next, parent: parent) { sawRepetition = true }
        // Nam-Nam can give the same player another move (feeding, or starting the next round);
        // only negate when the turn actually passes.
        if next.sideToMove == parent.sideToMove {
            return negamax(next, depth: depth, ply: ply, alpha: alpha, beta: beta)
        }
        return -negamax(next, depth: depth, ply: ply, alpha: -beta, beta: -alpha)
    }

    /// Nam-Nam: whether the move from `parent` may have ended the round on a repetition. The state
    /// does not record why a round ended, so this is conservative: the round ended and some
    /// position of it had already been seen often enough for one more visit to hit the limit.
    private func endedRoundByRepetition(_ next: GameState, parent: GameState) -> Bool {
        guard parent.rules.variant == .namNam, next.roundHistory.count > parent.roundHistory.count else { return false }
        let limit = parent.rules.repetitionLimit
        return parent.positionCounts.values.contains { $0 >= limit - 1 }
    }

    private mutating func negamax(_ state: GameState, depth: Int, ply: Int, alpha: Int, beta: Int) -> Int {
        nodes += 1
        // Every node applies each of its moves, so check the clock often: every 1024 nodes let a
        // loaded debug build overrun a 150 ms budget several times over.
        if nodes & 63 == 0, let deadline, ContinuousClock.now >= deadline {
            aborted = true
            return 0
        }
        if state.isOver || depth == 0 {
            return Evaluation.score(state, for: state.sideToMove, weights: weights, ply: ply)
        }

        let key = PositionKey(state)
        var alpha = alpha
        var beta = beta
        let cached = table[key]
        if let entry = cached, entry.depth >= depth {
            let score = Self.fromTable(entry.score, ply: ply)
            switch entry.bound {
            case .exact: return score
            case .lower: alpha = max(alpha, score)
            case .upper: beta = min(beta, score)
            }
            if alpha >= beta { return score }
        }

        var children = orderedChildren(state)
        // A hand-built position can be stuck without being marked over; score it as it stands
        // rather than returning Int.min (which the caller would negate and overflow).
        guard !children.isEmpty else {
            return Evaluation.score(state, for: state.sideToMove, weights: weights, ply: ply)
        }
        if let hint = cached?.best, let idx = children.firstIndex(where: { $0.move == hint }) {
            children.swapAt(0, idx)
        }

        let outerRepetition = sawRepetition
        sawRepetition = false
        let originalAlpha = alpha
        var bestScore = Int.min
        var bestMove: Move?
        for (move, next) in children {
            let score = childScore(next, parent: state, depth: depth - 1, ply: ply + 1, alpha: alpha, beta: beta)
            if aborted { return 0 }
            if score > bestScore {
                bestScore = score
                bestMove = move
            }
            alpha = max(alpha, score)
            if alpha >= beta { break }
        }
        let historyDependent = sawRepetition
        sawRepetition = outerRepetition || historyDependent

        let bound: Bound = bestScore <= originalAlpha ? .upper : (bestScore >= beta ? .lower : .exact)
        if historyDependent {
            // Only valid for the moves that led here; do not cache.
        } else if let existing = table[key], existing.depth > depth {
            // Keep the deeper result.
        } else {
            table[key] = Entry(depth: depth, score: Self.toTable(bestScore, ply: ply), bound: bound, best: bestMove)
        }
        return bestScore
    }

    /// Legal moves with the positions they lead to, ordered by seeds the mover gains (most first),
    /// then by fewest seeds left in the house sown from (non-zero only after a Nam-Nam relay back
    /// into it). Each move is applied once here and the result reused by the search.
    func orderedChildren(_ state: GameState) -> [(move: Move, next: GameState)] {
        state.legalMoves().compactMap { move -> (Move, GameState, Int)? in
            guard let next = try? state.applying(move).state else { return nil }
            let gained = next.store(of: move.player) - state.store(of: move.player)
            return (move, next, gained * 10 - next.houses[move.absoluteIndex])
        }
        .sorted { $0.2 > $1.2 }
        .map { ($0.0, $0.1) }
    }

    private func principalVariation(from root: GameState, first: Move, maxLength: Int) -> [Move] {
        guard let afterFirst = try? root.applying(first).state else { return [first] }
        var pv: [Move] = [first]
        var state = afterFirst
        var seen: Set<PositionKey> = [PositionKey(root)]
        while pv.count < maxLength, !state.isOver {
            let key = PositionKey(state)
            guard !seen.contains(key), let move = table[key]?.best else { break }
            seen.insert(key)
            pv.append(move)
            guard let next = try? state.applying(move).state else { break }
            state = next
        }
        return pv
    }
}
