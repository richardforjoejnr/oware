import Testing
@testable import OwareEngine

@Suite("Move preview")
struct MovePreviewTests {
    @Test("Preview reports path, landing house and captures without changing the state")
    func preview() {
        let state = position(a: [0, 0, 0, 0, 0, 4], b: [1, 2, 2, 1, 4, 4])
        let p = state.preview(move("A6"))!
        #expect(p.path == [6, 7, 8, 9])
        #expect(p.landingHouse == 9)
        #expect(p.captures == [9, 8, 7, 6])
        #expect(p.capturedSeeds == 10)
        #expect(!p.grandSlamForfeited)
        #expect(state.houses[5] == 4)
    }

    @Test("Preview flags a forfeited grand slam and shows no captures")
    func grandSlam() {
        let state = position(a: [0, 0, 0, 0, 0, 3], b: [1, 1, 2, 0, 0, 0])
        let p = state.preview(move("A6"))!
        #expect(p.grandSlamForfeited)
        #expect(p.captures.isEmpty)
        #expect(p.capturedSeeds == 0)
    }

    @Test("Preview is nil for empty houses, the wrong side, or a finished game")
    func nils() {
        var state = position(a: [0, 4, 4, 4, 4, 4], b: [4, 4, 4, 4, 4, 4])
        #expect(state.preview(move("A1")) == nil)
        #expect(state.preview(move("B1")) == nil)
        state.outcome = .draw(.agreement)
        #expect(state.preview(move("A2")) == nil)
    }
}
