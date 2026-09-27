import Testing
import OwareEngine
@testable import OwareAI

/// Checks the transposition table against a search that has none.
@Suite("Search")
struct SearchTests {
    /// Plain negamax: no pruning, no table, same scoring conventions as `Searcher`.
    static func plain(_ state: GameState, depth: Int, ply: Int = 0, weights: EvaluationWeights = .balanced) -> Int {
        if state.isOver || depth == 0 { return Evaluation.score(state, for: state.sideToMove, weights: weights, ply: ply) }
        var best = Int.min
        for move in state.legalMoves() {
            guard let next = try? state.applying(move).state else { continue }
            let score: Int
            if next.isOver {
                score = Evaluation.score(next, for: state.sideToMove, weights: weights, ply: ply + 1)
            } else if next.sideToMove == state.sideToMove {
                score = plain(next, depth: depth - 1, ply: ply + 1, weights: weights)
            } else {
                score = -plain(next, depth: depth - 1, ply: ply + 1, weights: weights)
            }
            best = max(best, score)
        }
        return best == Int.min ? Evaluation.score(state, for: state.sideToMove, weights: weights, ply: ply) : best
    }

    /// Mid-game positions from seeded random play, plus Abapa endgames near the winning line so
    /// that forced wins (ply-relative scores) are in reach of the search.
    static let cases = positions()

    static func positions() -> [GameState] {
        var rng = SeededGenerator(seed: 2026)
        var out: [GameState] = []
        for rules in [RuleSet.abapa, .namNam] {
            for _ in 0..<5 {
                var s = GameState.initial(rules: rules)
                let plies = 10 + Int(rng.next() % 30)
                for _ in 0..<plies {
                    guard let m = s.legalMoves().randomElement(using: &rng) else { break }
                    try? s.apply(m)
                }
                if !s.isOver { out.append(s) }
            }
        }
        // Abapa endgames with a forced win or loss 2–4 plies away (not an immediate win), so
        // ply-relative win scores are stored in the table and read back at other plies.
        var forced = 0
        while forced < 8 {
            var s = GameState.initial
            while !s.isOver, let m = s.legalMoves().randomElement(using: &rng) {
                try? s.apply(m)
                if !s.isOver, max(s.stores[0], s.stores[1]) >= 18, s.legalMoves().count > 1,
                   abs(plain(s, depth: 1)) < Evaluation.winScore - 64,
                   abs(plain(s, depth: 4)) >= Evaluation.winScore - 64 {
                    out.append(s)
                    forced += 1
                    break
                }
            }
        }
        return out
    }

    @Test("Iterative deepening with the table scores the root exactly like a plain search")
    func tableMatchesPlainSearch() {
        let positions = Self.cases
        #expect(positions.count >= 15)
        var forcedResults = 0
        for state in positions {
            guard let analysis = AIPlayer.analyse(state, depth: 4), analysis.depth > 0 else { continue }
            if abs(analysis.score) >= Evaluation.winScore - 64 { forcedResults += 1 }
            #expect(analysis.score == Self.plain(state, depth: analysis.depth), "\(state)")
        }
        #expect(forcedResults >= 8, "some positions should hold a forced win or loss")
    }

    @Test("A table shared across searches of related positions still gives exact values")
    func sharedTableMatchesPlainSearch() {
        var searcher = Searcher(weights: .balanced, deadline: nil)
        for state in Self.cases {
            for depth in 1...3 {
                #expect(searcher.value(of: state, depth: depth) == Self.plain(state, depth: depth), "depth \(depth)\n\(state)")
            }
            // Children re-use entries stored while searching the parent at other plies.
            for move in state.legalMoves() {
                guard let next = try? state.applying(move).state, !next.isOver else { continue }
                #expect(searcher.value(of: next, depth: 2) == Self.plain(next, depth: 2), "\(next)")
            }
        }
    }

    @Test("A score that came from a repetition is not reused for the same houses with a fresh history")
    func repetitionScoresAreNotCached() throws {
        // One seed each chasing round the board: the feeding rule forces every move, so play
        // cycles until the position repeats and each side keeps its seed — North then wins 23–25.
        // (A new searcher each step: the cycle is 12 plies, and a shared table would legitimately
        // answer from deeper entries, which a fixed-depth plain search cannot match.)
        var late = GameState(houses: [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1], stores: [22, 24])
        var checked = 0, historyMattered = 0
        while !late.isOver {
            let fresh = GameState(houses: late.houses, stores: late.stores, sideToMove: late.sideToMove)
            var searcher = Searcher(weights: .balanced, deadline: nil)
            #expect(searcher.value(of: late, depth: 6) == Self.plain(late, depth: 6))   // may see the repetition coming
            if Self.plain(late, depth: 6) != Self.plain(fresh, depth: 6) { historyMattered += 1 }
            #expect(searcher.value(of: fresh, depth: 6) == Self.plain(fresh, depth: 6), "\(fresh)")
            checked += 1
            try late.apply(late.legalMoves()[0])
        }
        #expect(late.outcome == .win(.north, .repetition))
        #expect(checked > 12 && historyMattered > 3)
    }

    @Test("A stuck position that is not marked over is scored, not crashed on")
    func stuckPosition() {
        // South has nothing to sow, but nothing marked the game over (hand-built, not reached by play).
        let stuck = GameState(houses: [0, 0, 0, 0, 0, 0, 4, 4, 4, 4, 4, 4], stores: [12, 12])
        #expect(stuck.legalMoves().isEmpty && !stuck.isOver)
        var searcher = Searcher(weights: .balanced, deadline: nil)
        #expect(searcher.value(of: stuck, depth: 3) == Evaluation.score(stuck, for: .south, weights: .balanced))
        #expect(AIPlayer.analyse(stuck, depth: 3) == nil)
        #expect(AIPlayer(difficulty: .grandmaster).chooseMove(for: stuck) == nil)
    }
}
