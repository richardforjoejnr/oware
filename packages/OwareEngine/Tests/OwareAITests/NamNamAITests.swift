import Testing
@testable import OwareEngine
@testable import OwareAI

@Suite("AI under Nam-Nam")
struct NamNamAITests {
    @Test("Different territory never shares a search-cache key")
    func keyIncludesTerritory() {
        let a = GameState(houses: Array(repeating: 4, count: 12), rules: .namNam)
        let b = GameState(houses: Array(repeating: 4, count: 12), rules: .namNam,
                          territory: (0..<12).map { $0 < 7 ? .south : .north })
        #expect(PositionKey(a) != PositionKey(b))
    }

    @Test("A player who is ahead stays clearly ahead across the round reset")
    func evaluationSteadyAcrossRoundEnd() throws {
        // South (41 won) cannot feed North, so sowing A1 ends the round: South keeps its seed,
        // 41–7 becomes eleven houses to one, and the board is refilled for round 2.
        var s = GameState(houses: [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], stores: [40, 7], rules: .namNam)
        let before = Evaluation.score(s, for: .south, weights: .balanced)
        try s.apply(Move(player: .south, absoluteHouse: 0))
        #expect(s.round == 2 && !s.isOver && s.houses(of: .south).count == 11)
        let after = Evaluation.score(s, for: .south, weights: .balanced)
        #expect(before > 3_000)
        #expect(after > 3_000, "the lead must survive the reset (before \(before), after \(after))")
        #expect(abs(after - before) < before / 4)
    }

    @Test("The AI ends a round it is winning rather than playing on")
    func endsWinningRound() throws {
        // A1 drops its seed on A2 (3 → 4): South takes that four, only four seeds remain, so South
        // takes them too and the round ends 44–4. A2 instead plays on with the round still open.
        let s = GameState(houses: [1, 3, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0], stores: [36, 4], rules: .namNam)
        let ending = try s.applying(Move(player: .south, absoluteHouse: 0)).state
        #expect(ending.round == 2 && ending.roundHistory.last?.southSeeds == 44)
        for depth in [1, 2, 4] {
            #expect(AIPlayer.analyse(s, depth: depth)?.move == Move(player: .south, absoluteHouse: 0), "depth \(depth)")
        }
    }

    @Test("AI-versus-AI Nam-Nam games finish with 48 seeds accounted for")
    func selfPlay() throws {
        for seed in 0..<3 as Range<UInt64> {
            var s = GameState.initial(rules: .namNam)
            let south = AIPlayer(difficulty: .beginner), north = AIPlayer(difficulty: .learner)
            var plies = 0
            while !s.isOver && plies < 3_000 {
                let ai = s.sideToMove == .south ? south : north
                guard let move = ai.chooseMove(for: s, seed: seed &+ UInt64(plies)) else { break }
                try s.apply(move)
                #expect(s.totalSeeds == 48)
                plies += 1
            }
            #expect(s.isOver)
        }
    }
}
