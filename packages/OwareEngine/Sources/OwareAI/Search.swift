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
        var rootOrder = orderedMoves(root)
        for depth in 1...max(1, maxDepth) {
            aborted = false
            // Explicit root loop so the chosen move never depends on a transposition-table entry
            // that a shallower re-visit of the root position could have overwritten.
            var alpha = -Evaluation.winScore * 2
            let beta = Evaluation.winScore * 2
            var iterationBest: (move: Move, score: Int)?
            for move in rootOrder {
                guard let next = try? root.applying(move).state else { continue }
                let score: Int
                if next.isOver {
                    score = Evaluation.score(next, for: root.sideToMove, weights: weights, ply: 1)
                } else {
                    score = -negamax(next, depth: depth - 1, ply: 1, alpha: -beta, beta: -alpha)
                }
                if aborted { break }
                if iterationBest == nil || score > iterationBest!.score { iterationBest = (move, score) }
                alpha = max(alpha, score)
            }
            if aborted { break }
            guard let found = iterationBest else { break }
            table[PositionKey(root)] = Entry(depth: depth, score: found.score, bound: .exact, best: found.move)
            best = MoveAnalysis(move: found.move, score: found.score, depth: depth, nodes: nodes,
                                principalVariation: principalVariation(from: root, maxLength: depth))
            // Search the previous best first next iteration.
            if let idx = rootOrder.firstIndex(of: found.move) { rootOrder.swapAt(0, idx) }
            // Stop early on a forced win/loss.
            if abs(found.score) >= Evaluation.winScore - 64 { break }
        }
        return best ?? MoveAnalysis(move: rootOrder[0], score: 0, depth: 0, nodes: nodes, principalVariation: [])
    }

    private mutating func negamax(_ state: GameState, depth: Int, ply: Int, alpha: Int, beta: Int) -> Int {
        nodes += 1
        if nodes & 1023 == 0, let deadline, ContinuousClock.now >= deadline {
            aborted = true
            return 0
        }
        if state.isOver || depth == 0 {
            return Evaluation.score(state, for: state.sideToMove, weights: weights, ply: ply)
        }

        let key = PositionKey(state)
        var alpha = alpha
        var beta = beta
        if let entry = table[key], entry.depth >= depth {
            switch entry.bound {
            case .exact: return entry.score
            case .lower: alpha = max(alpha, entry.score)
            case .upper: beta = min(beta, entry.score)
            }
            if alpha >= beta { return entry.score }
        }

        var moves = orderedMoves(state)
        if let entry = table[key], let hint = entry.best, let idx = moves.firstIndex(of: hint) {
            moves.swapAt(0, idx)
        }

        let originalAlpha = alpha
        var bestScore = Int.min
        var bestMove: Move?
        for move in moves {
            guard let next = try? state.applying(move).state else { continue }
            let score: Int
            if next.isOver {
                // Terminal: evaluate from the mover's perspective, negated for the parent's convention.
                score = Evaluation.score(next, for: state.sideToMove, weights: weights, ply: ply + 1)
            } else if next.sideToMove == state.sideToMove {
                score = negamax(next, depth: depth - 1, ply: ply + 1, alpha: alpha, beta: beta)
            } else {
                score = -negamax(next, depth: depth - 1, ply: ply + 1, alpha: -beta, beta: -alpha)
            }
            if aborted { return 0 }
            if score > bestScore {
                bestScore = score
                bestMove = move
            }
            alpha = max(alpha, score)
            if alpha >= beta { break }
        }

        let bound: Bound = bestScore <= originalAlpha ? .upper : (bestScore >= beta ? .lower : .exact)
        if let existing = table[key], existing.depth > depth {
            // Keep the deeper result.
        } else {
            table[key] = Entry(depth: depth, score: bestScore, bound: bound, best: bestMove)
        }
        return bestScore
    }

    /// Captures first (largest first), then moves that keep seeds safe, then the rest.
    func orderedMoves(_ state: GameState) -> [Move] {
        state.legalMoves().map { move -> (Move, Int) in
            guard let result = try? state.applying(move) else { return (move, Int.min) }
            let gained = result.state.store(of: move.player) - state.store(of: move.player)
            return (move, gained * 10 - result.state.houses[move.absoluteIndex])
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
    }

    private func principalVariation(from root: GameState, maxLength: Int) -> [Move] {
        var pv: [Move] = []
        var state = root
        var seen: Set<PositionKey> = []
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
