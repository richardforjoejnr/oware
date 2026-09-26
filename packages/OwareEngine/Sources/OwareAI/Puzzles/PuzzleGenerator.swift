import OwareEngine

/// Mines puzzles from random-but-plausible play, keeping only positions whose answer is unique.
/// Deterministic for a given seed, so the shipped puzzle file is reproducible.
public struct PuzzleGenerator {
    public var seed: UInt64
    public var rules: RuleSet

    public init(seed: UInt64 = 2026, rules: RuleSet = .abapa) {
        self.seed = seed
        self.rules = rules
    }

    /// Generate up to `count` puzzles of each kind. Positions come from games between a mid-level
    /// AI and a noisy one, so they look like real games rather than random scatter.
    public func generate(perKind count: Int, maxGames: Int = 4000) -> PuzzleSet {
        var rng = SeededGenerator(seed: seed)
        var found: [Puzzle.Kind: [Puzzle]] = [:]
        var seenKeys: Set<String> = []
        let strong = AIPlayer(difficulty: .player)
        let noisy = AIPlayer(difficulty: .beginner)

        func done() -> Bool { Puzzle.Kind.allCases.allSatisfy { (found[$0]?.count ?? 0) >= count } }

        var game = 0
        while game < maxGames && !done() {
            game += 1
            var state = GameState.initial(rules: rules)
            var ply = 0
            while !state.isOver && ply < 120 {
                ply += 1
                // Examine this position for every kind still needed.
                if ply > 6, !seenKeys.contains(state.positionKey) {
                    for kind in Puzzle.Kind.allCases where (found[kind]?.count ?? 0) < count {
                        if let puzzle = Self.classify(state, as: kind, index: (found[kind]?.count ?? 0) + 1) {
                            found[kind, default: []].append(puzzle)
                            seenKeys.insert(state.positionKey)
                            break
                        }
                    }
                }
                let mover = (ply % 2 == 0) == (rng.next() % 2 == 0) ? strong : noisy
                guard let move = mover.chooseMove(for: state, using: &rng) else { break }
                try? state.apply(move)
            }
        }
        let all = Puzzle.Kind.allCases.flatMap { found[$0] ?? [] }
        return PuzzleSet(puzzles: all.sorted { ($0.difficulty, $0.id) < ($1.difficulty, $1.id) })
    }

    // MARK: - Classification

    /// Immediate capture value of each legal move.
    static func captureValues(_ state: GameState) -> [(Move, Int)] {
        state.legalMoves().map { move in
            let after = (try? state.applying(move).state) ?? state
            return (move, after.store(of: move.player) - state.store(of: move.player))
        }
    }

    /// Best reply capture the opponent gets after `move` (0 if none).
    static func opponentBestCapture(after move: Move, in state: GameState) -> Int {
        guard let next = try? state.applying(move).state, !next.isOver else { return 0 }
        return captureValues(next).map(\.1).max() ?? 0
    }

    static func classify(_ state: GameState, as kind: Puzzle.Kind, index: Int) -> Puzzle? {
        let moves = state.legalMoves()
        guard moves.count >= 3 else { return nil }
        let player = state.sideToMove
        let values = captureValues(state)
        let best = values.max { $0.1 < $1.1 }!
        let secondBest = values.filter { $0.0 != best.0 }.map(\.1).max() ?? 0

        func make(_ solution: Move, target: Int, difficulty: Int) -> Puzzle {
            Puzzle(id: "\(kind.rawValue)-\(index)", kind: kind, houses: state.houses, stores: state.stores,
                   toMove: player, solution: solution, target: target, difficulty: difficulty)
        }

        switch kind {
        case .captureInOne:
            // Unique best capture, worth at least 4, clearly better than the runner-up.
            guard best.1 >= 4, best.1 - secondBest >= 2 else { return nil }
            let chain = (try? state.applying(best.0))?.events.filter { if case .capture = $0 { return true } else { return false } }.count ?? 1
            return make(best.0, target: best.1, difficulty: min(5, 1 + (chain - 1) + (best.1 >= 8 ? 1 : 0)))

        case .winInOne:
            let winning = moves.filter { (try? state.applying($0).state.outcome?.winner) == player }
            guard winning.count == 1, best.1 < 10 else { return nil }
            return make(winning[0], target: state.rules.winningSeeds - state.store(of: player), difficulty: 2)

        case .escapeTheTrap:
            // No capture available now; exactly one move leaves the opponent no capture, others lose ≥ 3.
            guard best.1 == 0 else { return nil }
            let risks = moves.map { ($0, opponentBestCapture(after: $0, in: state)) }
            let safe = risks.filter { $0.1 == 0 }
            guard safe.count == 1 else { return nil }
            let worst = risks.filter { $0.1 > 0 }.map(\.1)
            guard worst.count == risks.count - 1, (worst.min() ?? 0) >= 3 else { return nil }
            return make(safe[0].0, target: worst.max() ?? 0, difficulty: 3)

        case .feedOrLose:
            guard state.sideIsEmpty(player.opponent), moves.count >= 2 else { return nil }
            let risks = moves.map { ($0, opponentBestCapture(after: $0, in: state)) }
            let safe = risks.filter { $0.1 == 0 }
            guard safe.count == 1, risks.contains(where: { $0.1 >= 2 }) else { return nil }
            return make(safe[0].0, target: risks.map(\.1).max() ?? 0, difficulty: 3)

        case .captureInTwo:
            // No good capture now; one move guarantees ≥ 5 within our next move regardless of reply,
            // and no other first move guarantees more than 2. Depth-3 exact minimax on captures.
            guard best.1 <= 1 else { return nil }
            func guaranteed(after first: Move) -> Int {
                guard let s1 = try? state.applying(first).state, !s1.isOver else { return 0 }
                let gainedNow = s1.store(of: player) - state.store(of: player)
                var worst = Int.max
                for reply in s1.legalMoves() {
                    guard let s2 = try? s1.applying(reply).state else { continue }
                    if s2.isOver { worst = min(worst, s2.store(of: player) - state.store(of: player)); continue }
                    let ours = captureValues(s2).map(\.1).max() ?? 0
                    worst = min(worst, gainedNow + ours)
                }
                return worst == Int.max ? gainedNow : worst
            }
            let scored = moves.map { ($0, guaranteed(after: $0)) }
            let top = scored.max { $0.1 < $1.1 }!
            let runnerUp = scored.filter { $0.0 != top.0 }.map(\.1).max() ?? 0
            guard top.1 >= 5, runnerUp <= 2 else { return nil }
            return make(top.0, target: top.1, difficulty: 4)
        }
    }
}
