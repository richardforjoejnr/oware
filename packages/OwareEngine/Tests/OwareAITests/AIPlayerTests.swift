import Testing
import OwareEngine
@testable import OwareAI

private func position(a: [Int], b: [Int], stores: [Int] = [0, 0], toMove: Player = .south) -> GameState {
    GameState(houses: a + b, stores: stores, sideToMove: toMove)
}

@Suite("AI")
struct AIPlayerTests {
    @Test("Finds a capture in one at every level above Beginner")
    func captureInOne() {
        // A6 (1 seed) makes B1 = 3 → capture. No other house ends on a 2 or 3.
        let state = position(a: [4, 4, 5, 4, 4, 1], b: [2, 4, 4, 4, 4, 4])
        for level in Difficulty.allCases where level >= .learner {
            let ai = AIPlayer(difficulty: level)
            let analysis = ai.analyse(state)
            #expect(analysis?.move == Move(notation: "A6"), "level \(level)")
        }
    }

    @Test("Prefers the bigger capture chain")
    func biggerChain() {
        // A6 (4) sows B1..B4 → 2,3,3,2 = 10 seeds. A5 (1) makes A6 = 5: nothing.
        let state = position(a: [4, 4, 4, 4, 1, 4], b: [1, 2, 2, 1, 4, 4])
        let analysis = AIPlayer.analyse(state, depth: 2)
        #expect(analysis?.move == Move(notation: "A6"))
        #expect((analysis?.score ?? 0) > 0)
    }

    @Test("Sees a mate-in-one: reaching 25 wins")
    func seesWin() {
        let state = position(a: [4, 4, 5, 4, 4, 1], b: [1, 4, 4, 4, 4, 4], stores: [23, 0])
        let analysis = AIPlayer.analyse(state, depth: 3)
        #expect(analysis?.move == Move(notation: "A6"))
        #expect((analysis?.score ?? 0) >= Evaluation.winScore - 64)
    }

    @Test("Avoids handing the opponent an immediate capture when it can")
    func avoidsBlunder() {
        // A1 holds 1 seed and north's B6 (1) or B3 (4) would make it 2 and capture it.
        // Only moving A1 itself (→ A2 = 6) is safe; every other move loses those 2 seeds.
        let state = position(a: [1, 5, 5, 5, 5, 5], b: [4, 4, 4, 4, 4, 1])
        let analysis = AIPlayer.analyse(state, depth: 2)
        #expect(analysis?.move == Move(notation: "A1"))
    }

    @Test("Never returns an illegal move over many random positions")
    func alwaysLegal() throws {
        var rng = SeededGenerator(seed: 7)
        let ai = AIPlayer(difficulty: .learner)
        for _ in 0..<40 {
            var state = GameState.initial
            while !state.isOver {
                let move = ai.chooseMove(for: state, using: &rng)!
                #expect(state.isLegal(move))
                try state.apply(move)
            }
        }
    }

    @Test("Deterministic for the same seed")
    func deterministic() {
        let ai = AIPlayer(difficulty: .beginner)
        var a = SeededGenerator(seed: 99)
        var b = SeededGenerator(seed: 99)
        let state = GameState.initial
        #expect(ai.chooseMove(for: state, using: &a) == ai.chooseMove(for: state, using: &b))
    }

    @Test("Respects its time budget")
    func timeBudget() {
        let clock = ContinuousClock()
        let start = clock.now
        _ = AIPlayer.analyse(GameState.initial, depth: 40, timeBudget: .milliseconds(150))
        #expect(clock.now - start < .milliseconds(600))
    }

    @Test("Strong beats Beginner comfortably")
    func strongBeatsBeginner() throws {
        var rng = SeededGenerator(seed: 2024)
        let strong = AIPlayer(difficulty: .strong)
        let beginner = AIPlayer(difficulty: .beginner)
        var strongWins = 0
        let games = 8
        for g in 0..<games {
            var state = GameState.initial
            let strongSide: Player = g % 2 == 0 ? .south : .north
            while !state.isOver {
                let ai = state.sideToMove == strongSide ? strong : beginner
                try state.apply(ai.chooseMove(for: state, using: &rng)!)
            }
            if state.outcome?.winner == strongSide { strongWins += 1 }
        }
        #expect(strongWins >= games * 3 / 4, "strong won \(strongWins)/\(games)")
    }

    @Test("Position keys distinguish sides and houses")
    func keys() {
        let a = PositionKey(GameState.initial)
        var flipped = GameState.initial
        flipped.sideToMove = .north
        #expect(a != PositionKey(flipped))
        var moved = GameState.initial
        moved.houses[0] = 3
        #expect(a != PositionKey(moved))
    }
}
