import Testing
@testable import OwareEngine

/// Helper: build a position from south's and north's houses given in notation order
/// (A1…A6, B1…B6).
func position(a: [Int], b: [Int], stores: [Int] = [0, 0], toMove: Player = .south, rules: RuleSet = .abapa) -> GameState {
    precondition(a.count == 6 && b.count == 6)
    return GameState(houses: a + b, stores: stores, sideToMove: toMove, rules: rules)
}

func move(_ notation: String) -> Move { Move(notation: notation)! }

@Suite("Setup & notation")
struct SetupTests {
    @Test("Initial position has 48 seeds, four in each of twelve houses, south to move")
    func initialPosition() {
        let state = GameState.initial
        #expect(state.houses.count == 12)
        #expect(state.seedsOnBoard == 48)
        #expect(state.stores == [0, 0])
        #expect(state.houses.allSatisfy { $0 == 4 })
        #expect(state.sideToMove == .south)
        #expect(!state.isOver)
        #expect(state.legalMoves().count == 6)
    }

    @Test("Notation round-trips and rejects junk", arguments: ["A1", "A6", "B1", "B6", "b3"])
    func notation(text: String) {
        let m = Move(notation: text)
        #expect(m != nil)
        #expect(m?.notation == text.uppercased())
    }

    @Test("Invalid notation is rejected", arguments: ["A0", "A7", "C1", "AA", "", "A"])
    func invalidNotation(text: String) {
        #expect(Move(notation: text) == nil)
    }

    @Test("Absolute indices: A1→0, A6→5, B1→6, B6→11")
    func absoluteIndices() {
        #expect(move("A1").absoluteIndex == 0)
        #expect(move("A6").absoluteIndex == 5)
        #expect(move("B1").absoluteIndex == 6)
        #expect(move("B6").absoluteIndex == 11)
    }
}

@Suite("Sowing")
struct SowingTests {
    @Test("A1 from the opening sows one seed into A2…A5 and empties A1")
    func basicSow() throws {
        var state = GameState.initial
        let events = try state.apply(move("A1"))
        #expect(state.houses == [0, 5, 5, 5, 5, 4, 4, 4, 4, 4, 4, 4])
        #expect(state.sideToMove == .north)
        #expect(state.moveNumber == 1)
        #expect(events.first == .pickUp(house: 0, seeds: 4))
        #expect(events.filter { if case .sow = $0 { return true } else { return false } }.count == 4)
    }

    @Test("Sowing crosses onto the opponent's side counter-clockwise")
    func crossesSides() throws {
        var state = GameState.initial
        try state.apply(move("A6"))
        #expect(state.houses == [4, 4, 4, 4, 4, 0, 5, 5, 5, 5, 4, 4])
    }

    @Test("North's sowing wraps from B6 to A1")
    func northWraps() throws {
        var state = position(a: [0, 0, 0, 0, 0, 0], b: [0, 0, 0, 0, 0, 3], toMove: .north)
        try state.apply(move("B6"))
        #expect(state.houses == [1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    }

    @Test("A house with 12+ seeds skips its origin on every lap")
    func skipsOrigin() throws {
        var state = position(a: [0, 0, 15, 0, 0, 0], b: [3, 0, 0, 0, 0, 0])
        let events = try state.apply(move("A3"))
        // 15 seeds: 11 fill the other houses, origin skipped, 4 more go into A4…B1 (B1 ends on 5: no capture).
        #expect(state.houses[2] == 0)
        #expect(state.houses == [1, 1, 0, 2, 2, 2, 5, 1, 1, 1, 1, 1])
        #expect(events.contains(.skipOrigin(house: 2)))
        #expect(state.seedsOnBoard == 18)
        #expect(state.store(of: .south) == 0)
    }

    @Test("23+ seeds skip the origin twice")
    func skipsOriginTwice() throws {
        var state = position(a: [25, 0, 0, 0, 0, 0], b: [0, 0, 0, 0, 0, 0])
        let events = try state.apply(move("A1"))
        #expect(state.houses[0] == 0)
        #expect(events.filter { $0 == .skipOrigin(house: 0) }.count == 2)
        #expect(state.seedsOnBoard == 25)
    }

    @Test("Cannot move from an empty house or out of turn or after the game ends")
    func illegalBasics() throws {
        var state = position(a: [0, 4, 4, 4, 4, 4], b: [4, 4, 4, 4, 4, 4])
        #expect(throws: MoveError.emptyHouse) { try state.apply(move("A1")) }
        #expect(throws: MoveError.notYourTurn) { try state.apply(move("B1")) }
        state.outcome = .draw(.agreement)
        #expect(throws: MoveError.gameIsOver) { try state.apply(move("A2")) }
        #expect(state.legalMoves().isEmpty)
    }
}

@Suite("Capturing")
struct CaptureTests {
    @Test("Last seed making an opponent house 2 captures it")
    func captureTwo() throws {
        var state = position(a: [0, 0, 0, 0, 0, 1], b: [1, 4, 4, 4, 4, 4])
        let events = try state.apply(move("A6"))
        #expect(state.houses[6] == 0)
        #expect(state.store(of: .south) == 2)
        #expect(events.contains(.capture(house: 6, seeds: 2, by: .south)))
    }

    @Test("Last seed making an opponent house 3 captures it")
    func captureThree() throws {
        var state = position(a: [0, 0, 0, 0, 0, 1], b: [2, 4, 4, 4, 4, 4])
        try state.apply(move("A6"))
        #expect(state.store(of: .south) == 3)
    }

    @Test("Last seed making 1 or 4 captures nothing")
    func noCaptureOnOneOrFour() throws {
        var s1 = position(a: [0, 0, 0, 0, 0, 1], b: [0, 4, 4, 4, 4, 4])
        try s1.apply(move("A6"))
        #expect(s1.store(of: .south) == 0)
        var s4 = position(a: [0, 0, 0, 0, 0, 1], b: [3, 4, 4, 4, 4, 4])
        try s4.apply(move("A6"))
        #expect(s4.store(of: .south) == 0)
    }

    @Test("Multiple captures walk backwards while houses are 2 or 3, and stop at the first that isn't")
    func multipleCapture() throws {
        // A6 has 4: sows B1..B4 → 2, 3, 2, 1. Last seed in B4 makes 1 → no capture at all.
        var s = position(a: [0, 0, 0, 0, 0, 4], b: [1, 2, 1, 0, 4, 4])
        try s.apply(move("A6"))
        #expect(s.store(of: .south) == 0)

        // A6 has 4: sows B1..B4 → 2, 3, 5, 2. Last seed makes B4=2 → capture B4 only (B3 is 5).
        var t = position(a: [0, 0, 0, 0, 0, 4], b: [1, 2, 4, 1, 4, 4])
        try t.apply(move("A6"))
        #expect(t.store(of: .south) == 2)
        #expect(t.houses[9] == 0 && t.houses[8] == 5)

        // A6 has 4: sows B1..B4 → 2, 3, 3, 2. Chain captures B4, B3, B2, B1 = 10 seeds.
        var u = position(a: [0, 0, 0, 0, 0, 4], b: [1, 2, 2, 1, 4, 4])
        let events = try u.apply(move("A6"))
        #expect(u.store(of: .south) == 10)
        #expect(Array(u.houses[6...9]) == [0, 0, 0, 0])
        let captures = events.compactMap { if case let .capture(h, _, _) = $0 { return h } else { return nil } }
        #expect(captures == [9, 8, 7, 6])
    }

    @Test("Captures never happen on the mover's own side")
    func noOwnSideCapture() throws {
        // A1 has 1: sows A2 → 2. Own side, so nothing captured.
        var s = position(a: [1, 1, 0, 0, 0, 0], b: [4, 4, 4, 4, 4, 4])
        try s.apply(move("A1"))
        #expect(s.store(of: .south) == 0)
        #expect(s.houses[1] == 2)
    }

    @Test("The backwards walk stops at the edge of the opponent's row")
    func walkStopsAtRowEdge() throws {
        // North sows B6 (1 seed) into A1 making 2. Walking back from A1 would be B6 (own side): stop.
        var s = position(a: [1, 0, 0, 3, 0, 0], b: [0, 0, 0, 0, 2, 1], toMove: .north)
        try s.apply(move("B6"))
        #expect(s.store(of: .north) == 2)
        #expect(s.houses[10] == 2)
        #expect(s.houses[0] == 0)
    }

    @Test("A house made 2 or 3 in passing (not by the last seed) is not captured")
    func passingIsNotCapture() throws {
        // A5 has 3: sows A6, B1, B2 → B1 becomes 2 in passing, B2 becomes 5. No capture.
        var s = position(a: [0, 0, 0, 0, 3, 0], b: [1, 4, 4, 4, 4, 4])
        try s.apply(move("A5"))
        #expect(s.store(of: .south) == 0)
        #expect(s.houses[6] == 2)
    }
}

@Suite("Grand slam")
struct GrandSlamTests {
    /// A6 has 3: sows B1, B2, B3 → 2, 2, 3 which would take every seed north has.
    static let grandSlamPosition = position(a: [0, 0, 0, 0, 0, 3], b: [1, 1, 2, 0, 0, 0])

    @Test("Default (Abapa): the move is legal but the capture is forfeited")
    func forfeit() throws {
        var s = Self.grandSlamPosition
        #expect(s.isLegal(move("A6")))
        let events = try s.apply(move("A6"))
        #expect(s.store(of: .south) == 0)
        #expect(Array(s.houses[6...8]) == [2, 2, 3])
        #expect(events.contains(.grandSlamForfeited(by: .south, houses: [8, 7, 6])))
        #expect(!s.isOver)
    }

    @Test("illegalMove variant: the move is not offered and is rejected")
    func illegal() throws {
        var s = position(a: [0, 0, 0, 0, 1, 3], b: [1, 1, 2, 0, 0, 0], rules: RuleSet(grandSlam: .illegalMove))
        #expect(!s.legalMoves().contains(move("A6")))
        #expect(s.legalMoves().contains(move("A5")))
        #expect(throws: MoveError.grandSlamNotAllowed) { try s.apply(move("A6")) }
    }

    @Test("captureEndsGame variant: capture stands, mover sweeps own side, game over")
    func endsGame() throws {
        var s = position(a: [0, 0, 5, 0, 0, 3], b: [1, 1, 2, 0, 0, 0], rules: RuleSet(grandSlam: .captureEndsGame))
        try s.apply(move("A6"))
        #expect(s.store(of: .south) == 7 + 5)
        #expect(s.isOver)
        #expect(s.outcome == .win(.south, .grandSlam))
    }

    @Test("Capturing some but not all opponent seeds is not a grand slam")
    func partialIsFine() throws {
        var s = position(a: [0, 0, 0, 0, 0, 3], b: [1, 1, 2, 1, 0, 0])
        try s.apply(move("A6"))
        #expect(s.store(of: .south) == 7)
    }
}

@Suite("Feeding obligation")
struct FeedingTests {
    @Test("When the opponent is empty, only moves that reach them are legal")
    func mustFeed() throws {
        // A1 (1 seed) cannot reach north; A6 (1 seed) can.
        var s = position(a: [1, 0, 0, 0, 0, 1], b: [0, 0, 0, 0, 0, 0])
        #expect(s.legalMoves() == [move("A6")])
        #expect(throws: MoveError.mustFeedOpponent) { try s.apply(move("A1")) }
        try s.apply(move("A6"))
        #expect(s.houses[6] == 1)
        #expect(s.sideToMove == .north)
    }

    @Test("If no move can feed, the mover keeps their side and the game ends")
    func cannotFeed() throws {
        var s = position(a: [1, 1, 0, 0, 0, 0], b: [0, 0, 0, 0, 0, 0], stores: [20, 26])
        let events = try s.apply(move("A1"))
        #expect(s.isOver)
        #expect(s.store(of: .south) == 22)
        #expect(s.outcome == .win(.north, .opponentCouldNotBeFed))
        #expect(events.contains(.sweep(player: .south, seeds: 2)))
    }

    @Test("With the rule off, a stuck opponent ends the game and the mover takes the rest")
    func ruleOff() throws {
        var s = position(a: [1, 0, 0, 0, 0, 1], b: [0, 0, 0, 0, 0, 0], stores: [20, 26], rules: RuleSet(mustFeed: false))
        #expect(s.legalMoves().count == 2)
        try s.apply(move("A1"))
        #expect(s.outcome == .win(.north, .noLegalMoves))
        #expect(s.store(of: .south) == 22)
        #expect(s.seedsOnBoard == 0)
    }
}

@Suite("Game end")
struct EndTests {
    @Test("Reaching 25 wins immediately")
    func winAt25() throws {
        var s = position(a: [0, 0, 0, 0, 0, 1], b: [1, 4, 4, 4, 4, 4], stores: [23, 0])
        try s.apply(move("A6"))
        #expect(s.outcome == .win(.south, .reachedWinningSeeds))
        #expect(s.legalMoves().isEmpty)
    }

    @Test("24–24 is a draw (here reached when the last seed cannot feed)")
    func draw() throws {
        var s = position(a: [1, 0, 0, 0, 0, 0], b: [0, 0, 0, 0, 0, 0], stores: [23, 24])
        try s.apply(move("A1"))
        #expect(s.outcome == .draw(.opponentCouldNotBeFed))
        #expect(s.stores == [24, 24])
        #expect(s.totalSeeds == 48)
    }

    @Test("The final capture empties the board under captureEndsGame")
    func boardEmpty() throws {
        var s = position(a: [0, 0, 0, 0, 0, 1], b: [1, 0, 0, 0, 0, 0], stores: [22, 24],
                         rules: RuleSet(grandSlam: .captureEndsGame))
        try s.apply(move("A6"))
        #expect(s.seedsOnBoard == 0)
        #expect(s.outcome == .draw(.grandSlam))
    }

    @Test("A position repeated three times ends the game with each side keeping its seeds")
    func repetition() throws {
        // One seed each at A6/B6: the seeds chase each other round the board, every house
        // only ever reaches 1, and the feeding rule always forces the same reply, so play cycles.
        var s = position(a: [0, 0, 0, 0, 0, 1], b: [0, 0, 0, 0, 0, 1], stores: [23, 23])
        var guardCount = 0
        while !s.isOver {
            try s.apply(s.legalMoves()[0])
            guardCount += 1
            #expect(guardCount < 500)
        }
        #expect(s.totalSeeds == 48)
        #expect(s.seedsOnBoard == 0)
        #expect(s.outcome == .draw(.repetition))
    }

    @Test("Ending by agreement sweeps both sides")
    func agreement() {
        var s = position(a: [1, 0, 0, 0, 0, 0], b: [0, 0, 0, 0, 0, 3], stores: [22, 22])
        _ = s.endByAgreement()
        #expect(s.outcome == .win(.north, .agreement))
        #expect(s.stores == [23, 25])
    }
}

@Suite("Records & invariants")
struct RecordTests {
    @Test("A record replays to the same state and round-trips notation")
    func replay() throws {
        let record = GameRecord(notation: "A1 B1 A6 B6")!
        let state = try record.replay()
        #expect(state.moveNumber == 4)
        #expect(record.notation == "A1 B1 A6 B6")
        #expect(try record.states().count == 5)
        #expect(GameRecord(notation: "A1 Z9") == nil)
    }

    @Test("State encodes and decodes losslessly")
    func codable() throws {
        var s = GameState.initial
        try s.apply(move("A3"))
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        #expect(back == s)
    }

    @Test("Random playouts always conserve 48 seeds and terminate")
    func randomPlayouts() throws {
        var rng = SplitMix64(seed: 0xC0FFEE)
        for _ in 0..<300 {
            var s = GameState.initial
            var plies = 0
            while !s.isOver {
                let moves = s.legalMoves()
                #expect(!moves.isEmpty)
                let m = moves[Int(rng.next() % UInt64(moves.count))]
                try s.apply(m)
                plies += 1
                #expect(s.totalSeeds == 48)
                #expect(s.houses.allSatisfy { $0 >= 0 })
                if plies > 2000 { Issue.record("playout did not terminate"); break }
            }
            #expect(s.outcome != nil)
        }
    }

    @Test("Every rule variant also terminates under random play")
    func variantsTerminate() throws {
        var rng = SplitMix64(seed: 42)
        for variant in RuleSet.GrandSlamRule.allCases {
            for mustFeed in [true, false] {
                let rules = RuleSet(grandSlam: variant, mustFeed: mustFeed)
                for _ in 0..<30 {
                    var s = GameState.initial(rules: rules)
                    var plies = 0
                    while !s.isOver, plies < 2000 {
                        let moves = s.legalMoves()
                        if moves.isEmpty { break }
                        try s.apply(moves[Int(rng.next() % UInt64(moves.count))])
                        plies += 1
                    }
                    #expect(s.totalSeeds == 48)
                    #expect(s.isOver, "variant \(variant) mustFeed=\(mustFeed) did not end")
                }
            }
        }
    }
}

import Foundation

/// Tiny deterministic RNG for tests.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
