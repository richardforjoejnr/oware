import Testing
@testable import OwareEngine

@Suite("GameState")
struct GameStateTests {
    @Test("Initial position has 48 seeds, four in each of twelve houses")
    func initialPosition() {
        let state = GameState.initial
        #expect(state.houses.count == 12)
        #expect(state.seedsOnBoard == 48)
        #expect(state.stores == [0, 0])
        #expect(state.houses.allSatisfy { $0 == 4 })
    }
}
