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
