import Testing
@testable import OwareEngine

/// Nam-Nam: relay sowing, captures on fours, the last-four rule, rounds and territory.
@Suite("Nam-Nam")
struct NamNamTests {
    private func state(_ houses: [Int], toMove: Player = .south, stores: [Int] = [0, 0], territory: [Player] = GameState.defaultTerritory) -> GameState {
        GameState(houses: houses, stores: stores, sideToMove: toMove, rules: .namNam, territory: territory)
    }
    private func captures(_ events: [MoveEvent]) -> [(house: Int, seeds: Int, by: Player)] {
        events.compactMap { if case let .capture(h, s, b) = $0 { return (h, s, b) } else { return nil } }
    }
    private func relays(_ events: [MoveEvent]) -> [Int] {
        events.compactMap { if case let .relay(h, _) = $0 { return h } else { return nil } }
    }

    @Test("Landing in an empty house ends the turn")
    func endsOnEmptyHouse() throws {
        //            A1 A2 A3 A4 A5 A6  B1 B2 B3 B4 B5 B6
        var s = state([2, 0, 0, 5, 5, 5,  5, 5, 5, 5, 5, 6])
        let events = try s.apply(Move(player: .south, house: 0))
        #expect(relays(events).isEmpty)
        #expect(s.houses[1] == 1 && s.houses[2] == 1)
        #expect(s.sideToMove == .north)
    }

    @Test("Landing in a house that already holds seeds scoops it up and carries on")
    func relays() throws {
        //            A1 A2 A3 A4 A5 A6  B1 B2 B3 B4 B5 B6
        var s = state([2, 0, 5, 0, 0, 0,  8, 8, 8, 7, 8, 2])
        let events = try s.apply(Move(player: .south, house: 0))
        #expect(relays(events).first == 2, "A1 → A2, A3; A3 held 5 and is scooped")
        #expect(s.totalSeeds == 48)
    }

    @Test("A four on your own territory is yours at any point in the sowing")
    func ownFourCapturedMidSowing() throws {
        //            A1 A2 A3 A4 A5 A6  B1 B2 B3 B4 B5 B6
        var s = state([3, 3, 0, 0, 0, 0,  6, 6, 6, 6, 6, 6])
        // A1(3) → A2 (3→4: captured by south), A3 (1), A4 (1). Last seed in empty A4: turn over.
        let events = try s.apply(Move(player: .south, house: 0))
        let c = captures(events)
        #expect(c.count == 1 && c[0].house == 1 && c[0].seeds == 4 && c[0].by == .south)
        #expect(s.stores[0] == 4 && s.houses[1] == 0)
        #expect(s.sideToMove == .north)
    }

    @Test("A four made on the opponent's territory by a passing seed goes to the opponent")
    func opponentFourMidSowingGoesToOwner() throws {
        //            A1 A2 A3 A4 A5 A6  B1 B2 B3 B4 B5 B6
        var s = state([0, 0, 0, 0, 0, 3,  3, 0, 0, 5, 5, 5])
        // A6(3) → B1 (3→4: north's territory, not the last seed → north captures), B2 (1), B3 (1).
        let events = try s.apply(Move(player: .south, house: 5))
        let c = captures(events)
        #expect(c.count == 1 && c[0].house == 6 && c[0].by == .north)
        #expect(s.stores[1] == 4 && s.stores[0] == 0)
    }

    @Test("A four made on the opponent's territory by the last seed goes to the sower")
    func opponentFourWithLastSeedGoesToSower() throws {
        //            A1 A2 A3 A4 A5 A6  B1 B2 B3 B4 B5 B6
        var s = state([0, 0, 0, 0, 0, 1,  3, 5, 5, 5, 5, 5])
        let events = try s.apply(Move(player: .south, house: 5))   // A6 → B1 makes 4 with the last seed
        let c = captures(events)
        #expect(c.count == 1 && c[0].house == 6 && c[0].by == .south)
        #expect(s.stores[0] == 4)
        #expect(s.sideToMove == .north, "the captured house is empty, so the turn ends")
    }

    @Test("Abapa-style twos and threes are not captures in Nam-Nam")
    func noCaptureOnTwoOrThree() throws {
        var s = state([0, 0, 0, 0, 0, 1,  2, 5, 5, 5, 5, 5])
        try s.apply(Move(player: .south, house: 5))   // B1 becomes 3, and was non-empty → relay from B1
        #expect(s.stores == [0, 0])
    }

    @Test("Each relay lap skips the house it was scooped from")
    func relayLapSkipsOrigin() throws {
        //            A1 A2 A3 A4 A5 A6  B1 B2 B3 B4 B5 B6
        var s = state([1, 12, 3, 3, 3, 3,  3, 3, 3, 3, 3, 8])
        let events = try s.apply(Move(player: .south, house: 0))
        #expect(events.contains { if case .relay(house: 1, seeds: 13) = $0 { return true } else { return false } })
        #expect(events.contains { if case .skipOrigin(house: 1) = $0 { return true } else { return false } })
        #expect(s.totalSeeds == 48)
    }

    @Test("When a capture leaves four seeds on the board, the capturer takes them and the round ends")
    func lastFourRule() throws {
        //            A1 A2 A3 A4 A5 A6  B1 B2 B3 B4 B5 B6
        var s = state([3, 0, 0, 0, 0, 0,  0, 0, 0, 0, 4, 1], stores: [20, 20])
        // A1(3) → A2 (1), A3 (1), A4 (1): no four yet, lands empty, turn ends. Use a position that
        // does capture instead: A1(1) → A2 holding 3 makes 4 on south's territory.
        s = state([1, 3, 0, 0, 0, 0,  0, 0, 0, 0, 4, 0], stores: [20, 20])
        let events = try s.apply(Move(player: .south, house: 0))
        let c = captures(events)
        #expect(c.map(\.house) == [1, 10], "A2 (the penultimate four) then B5 (the last four)")
        #expect(c.allSatisfy { $0.by == .south })
        #expect(events.contains { if case .roundOver = $0 { return true } else { return false } })
        #expect(s.round == 2)
        #expect(s.roundHistory.last == RoundResult(round: 1, southSeeds: 28, northSeeds: 20, southHouses: 7, northHouses: 5))
    }

    @Test("Territory after a round is contiguous from A1 and the board is refilled")
    func territoryAfterRound() throws {
        var s = state([1, 3, 0, 0, 0, 0,  0, 0, 0, 0, 4, 0], stores: [20, 20])
        try s.apply(Move(player: .south, house: 0))
        #expect(s.territory == [.south, .south, .south, .south, .south, .south, .south, .north, .north, .north, .north, .north])
        #expect(s.houses == Array(repeating: 4, count: 12))
        #expect(s.stores == [0, 0])
        #expect(s.sideToMove == .north, "the other player starts the next round")
        #expect(s.houses(of: .south).count == 7)
        // South may now play from B1 (house 6), which is theirs.
        #expect(s.legalMoves().isEmpty == false)
        var t = s; t.sideToMove = .south
        #expect(t.legalMoves().map(\.absoluteIndex).contains(6))
    }

    @Test("A spare house from equal remainders goes to the player with more seeds")
    func spareHouse() {
        // Agreement sweeps both sides: 20 + 6 = 26 for south, 22 for north → 6 r2 and 5 r2.
        var s = state([1, 1, 1, 1, 1, 1,  0, 0, 0, 0, 0, 0], stores: [20, 22])
        _ = s.endByAgreement()
        #expect(s.roundHistory.last == RoundResult(round: 1, southSeeds: 26, northSeeds: 22, southHouses: 7, northHouses: 5))
        #expect(!s.isOver)
    }

    @Test("Owning all twelve houses wins the game")
    func gameEndsWhenAllHousesOwned() throws {
        // South owns eleven houses. A1 → A2 makes four (south's), leaving four in B6: last-four rule.
        var houses = Array(repeating: 0, count: 12)
        houses[0] = 1; houses[1] = 3; houses[11] = 4
        var s = state(houses, stores: [40, 0], territory: (0..<12).map { $0 < 11 ? .south : .north })
        try s.apply(Move(player: .south, absoluteHouse: 0))
        #expect(s.stores[0] == 48)
        #expect(s.outcome == .win(.south, .territory))
    }

    @Test("A player with no seeds is fed: the other player moves again")
    func feedingTurnPassesBack() throws {
        //            A1 A2 A3 A4 A5 A6  B1 B2 B3 B4 B5 B6
        var s = state([0, 0, 0, 0, 0, 2,  0, 0, 0, 0, 0, 0], stores: [24, 22])
        // South must feed: A6(2) → B1 (1), B2 (1). Now north has seeds and moves.
        try s.apply(Move(player: .south, house: 5))
        #expect(s.sideToMove == .north)
        #expect(s.houses[6] == 1 && s.houses[7] == 1)
    }

    @Test("Abapa is untouched: the default variant still stops after one lap")
    func abapaUnchanged() throws {
        var s = GameState(houses: [2, 0, 5, 0, 0, 0, 8, 8, 8, 7, 8, 2])
        try s.apply(Move(player: .south, house: 0))
        #expect(s.houses[2] == 6, "Abapa leaves the six seeds in A3")
        #expect(s.rules.variant == .abapa)
    }

    private struct LCG: RandomNumberGenerator {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
    }

    @Test("Random Nam-Nam games conserve 48 seeds, change territory and finish", arguments: [11, 12, 13])
    func randomGames(seed: UInt64) throws {
        var rng = LCG(s: seed)
        var relayed = 0, captured = 0, rounds = 0, territoryChanged = 0
        for _ in 0..<60 {
            var s = GameState.initial(rules: .namNam)
            var plies = 0
            while !s.isOver && plies < 4_000 {
                let moves = s.legalMoves()
                #expect(moves.allSatisfy { s.territory[$0.absoluteIndex] == s.sideToMove })
                guard let move = moves.randomElement(using: &rng) else { break }
                let events = try s.apply(move)
                relayed += events.filter { if case .relay = $0 { return true } else { return false } }.count
                captured += events.filter { if case .capture = $0 { return true } else { return false } }.count
                if events.contains(where: { if case .roundOver = $0 { return true } else { return false } }) {
                    rounds += 1
                    if s.houses(of: .south).count != 6 { territoryChanged += 1 }
                }
                #expect(s.totalSeeds == 48, "\(s)")
                plies += 1
            }
            #expect(s.isOver, "a Nam-Nam game should reach a result within the round cap")
        }
        #expect(relayed > 1_000)
        #expect(captured > 1_000)
        #expect(rounds > 60)
        #expect(territoryChanged > 20)
    }
}
