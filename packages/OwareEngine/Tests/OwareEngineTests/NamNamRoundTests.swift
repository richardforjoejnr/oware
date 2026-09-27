import Foundation
import Testing
@testable import OwareEngine

/// Hand-checked Nam-Nam positions: territory across the row, feeding, the last four with seeds in
/// hand, and how each round turns seeds into houses (the "rings" on the board).
@Suite("Nam-Nam rounds and territory")
struct NamNamRoundTests {
    private func state(_ houses: [Int], toMove: Player = .south, stores: [Int], southHouses: Int = 6,
                       rules: RuleSet = .namNam) -> GameState {
        GameState(houses: houses, stores: stores, sideToMove: toMove, rules: rules,
                  territory: (0..<12).map { $0 < southHouses ? .south : .north })
    }
    private func captures(_ events: [MoveEvent]) -> [(house: Int, seeds: Int, by: Player)] {
        events.compactMap { if case let .capture(h, s, b) = $0 { return (h, s, b) } else { return nil } }
    }
    private func rings(_ s: GameState) -> (south: Int, north: Int) {
        // A ring marks a house held across the row: South holding B houses, North holding A houses.
        ((6..<12).filter { s.territory[$0] == .south }.count, (0..<6).filter { s.territory[$0] == .north }.count)
    }
    /// Ends round 1 by agreement with the given seed totals (board empty, all seeds in stores).
    private func afterRound(south: Int, north: Int, southHouses: Int = 6) -> GameState {
        var s = state(Array(repeating: 0, count: 12), stores: [south, north], southHouses: southHouses)
        _ = s.endByAgreement()
        return s
    }

    // MARK: Seeds to houses

    @Test("Each four seeds won is a house; a 28–20 round moves one house to the winner",
          arguments: [(28, 20, 7), (32, 16, 8), (24, 24, 6), (20, 28, 5), (36, 12, 9), (40, 8, 10), (44, 4, 11)])
    func housesFromSeeds(south: Int, north: Int, southHouses: Int) {
        let s = afterRound(south: south, north: north)
        #expect(s.roundHistory.last?.southHouses == southHouses)
        #expect(s.roundHistory.last?.northHouses == 12 - southHouses)
        #expect(s.houses(of: .south).count == southHouses)
    }

    @Test("A spare house goes to the player who won more seeds that round",
          arguments: [(25, 23, 7), (26, 22, 7), (27, 21, 7), (23, 25, 5), (22, 26, 5), (21, 27, 5), (29, 19, 8), (19, 29, 4), (47, 1, 12), (1, 47, 0)])
    func spareHouseToRoundWinner(south: Int, north: Int, southHouses: Int) {
        let s = afterRound(south: south, north: north)
        #expect(s.roundHistory.last?.southHouses == southHouses, "\(south)–\(north)")
        #expect((s.roundHistory.last?.southHouses ?? 0) + (s.roundHistory.last?.northHouses ?? 0) == 12)
    }

    @Test("From ten houses you need 41 seeds to gain one; 40 keeps ten; a smaller win loses houses",
          arguments: [(40, 10), (41, 11), (44, 11), (45, 12), (36, 9), (30, 8)])
    func fromTenHouses(southSeeds: Int, expected: Int) {
        let s = afterRound(south: southSeeds, north: 48 - southSeeds, southHouses: 10)
        #expect(s.roundHistory.last?.southHouses == expected, "\(southSeeds)–\(48 - southSeeds) from ten houses")
    }

    @Test("Winning a round never leaves the winner with fewer houses than the loser")
    func roundWinnerNeverBehind() {
        for south in 0...48 {
            let r = afterRound(south: south, north: 48 - south).roundHistory.last!
            if south > 24 { #expect(r.southHouses > r.northHouses, "\(south)–\(48 - south)") }
            if south < 24 { #expect(r.southHouses < r.northHouses, "\(south)–\(48 - south)") }
            if south == 24 { #expect(r.southHouses == 6) }
        }
    }

    // MARK: Rings (houses held across the row)

    @Test("Winning round one by a house puts exactly one ring on B1, in South's hands")
    func oneRingAfterOneHouse() {
        let s = afterRound(south: 28, north: 20)
        #expect(rings(s).south == 1 && rings(s).north == 0)
        #expect(s.territory[6] == .south)
    }

    @Test("Winning by two houses adds two rings, not one")
    func twoRingsAfterTwoHouses() {
        let s = afterRound(south: 32, north: 16)
        #expect(rings(s).south == 2 && rings(s).north == 0)
    }

    @Test("Holding eight houses and winning the next round 26–22 drops to seven: a ring goes, though the round was won")
    func winningCanStillCostAHouse() {
        let s = afterRound(south: 26, north: 22, southHouses: 8)
        #expect(s.roundHistory.last?.southHouses == 7)
        #expect(rings(s).south == 1)
    }

    @Test("Losing a round moves rings to your own row, in the other player's colour")
    func losingPutsRingsOnYourRow() {
        let s = afterRound(south: 16, north: 32)
        #expect(rings(s).south == 0 && rings(s).north == 2)
        #expect(s.territory[4] == .north && s.territory[5] == .north && s.territory[3] == .south)
    }

    @Test("Territory is always contiguous from A1 and the houses always add up to twelve")
    func territoryShape() {
        for south in 0...48 {
            let s = afterRound(south: south, north: 48 - south)
            guard !s.isOver else { continue }
            let k = s.houses(of: .south).count
            #expect(s.territory == (0..<12).map { $0 < k ? .south : .north })
            #expect(s.houses == Array(repeating: 4, count: 12))
            #expect(s.stores == [0, 0])
            #expect(s.totalSeeds == 48)
        }
    }

    // MARK: Territory across the row

    @Test("A house you own on the other row is yours: a four made there in passing is yours")
    func ownHouseAcrossTheRow() throws {
        //                  A1 A2 A3 A4 A5 A6  B1 B2 B3 B4 B5 B6
        var s = state([1, 2, 1, 2, 1, 2, 3, 0, 5, 5, 5, 5], stores: [8, 8], southHouses: 7)
        // A6(2) → B1 (3→4: South owns B1, so South takes it), B2 (0→1, empty: turn ends).
        let events = try s.apply(Move(player: .south, absoluteHouse: 5))
        let c = captures(events)
        #expect(c.count == 1 && c[0].house == 6 && c[0].by == .south)
        #expect(s.stores == [12, 8])
    }

    @Test("The same passing four on B1 goes to North when North owns it")
    func sameFourDefaultTerritory() throws {
        var s = state([1, 2, 1, 2, 1, 2, 3, 0, 5, 5, 5, 5], stores: [8, 8])
        let events = try s.apply(Move(player: .south, absoluteHouse: 5))
        #expect(captures(events).map(\.by) == [.north])
        #expect(s.stores == [8, 12])
    }

    @Test("You may sow from your houses on the other row; the other player may not")
    func movesFollowOwnership() throws {
        let s = state([1, 2, 1, 2, 1, 2, 3, 1, 5, 5, 5, 5], stores: [8, 7], southHouses: 7)
        #expect(s.legalMoves().map(\.absoluteIndex).contains(6))
        var north = s; north.sideToMove = .north
        #expect(!north.legalMoves().map(\.absoluteIndex).contains(6))
        #expect(throws: MoveError.notYourHouse) { try north.apply(Move(player: .north, absoluteHouse: 6)) }
        var south = s
        #expect(throws: MoveError.notYourHouse) { try south.apply(Move(player: .south, absoluteHouse: 7)) }
    }

    // MARK: Feeding

    @Test("When the other side is empty only a feeding move is allowed")
    func mustFeed() throws {
        var s = state([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0], stores: [23, 23])
        #expect(s.legalMoves().map(\.notation) == ["A6"])
        #expect(throws: MoveError.mustFeedOpponent) { try s.apply(Move(player: .south, absoluteHouse: 0)) }
        try s.apply(Move(player: .south, absoluteHouse: 5))
        #expect(s.houses[6] == 1 && s.sideToMove == .north)
    }

    @Test("Emptying the other side by a capture means you move again, and must feed")
    func moveAgainToFeed() throws {
        //                  A1 A2 A3 A4 A5 A6  B1 B2 B3 B4 B5 B6
        var s = state([2, 0, 0, 3, 0, 1, 3, 0, 0, 0, 0, 0], stores: [20, 19])
        try s.apply(Move(player: .south, absoluteHouse: 5))   // A6 → B1 makes four with the last seed
        #expect(s.stores[0] == 24)
        #expect(s.sideToMove == .south, "North has nothing, so South goes again")
        #expect(s.legalMoves().map(\.notation) == ["A4"], "only A4 reaches North")
        #expect(!s.isOver && s.round == 1)
    }

    @Test("If nobody can be fed the mover keeps their side and the round ends")
    func nobodyCanBeFed() throws {
        //                  A1 A2 A3 A4 A5 A6  B1 B2 B3 B4 B5 B6
        var s = state([2, 0, 0, 0, 0, 1, 3, 0, 0, 0, 0, 0], stores: [20, 22])
        try s.apply(Move(player: .south, absoluteHouse: 5))   // takes B1; North empty; A1 cannot reach
        #expect(s.round == 2)
        #expect(s.roundHistory.last == RoundResult(round: 1, southSeeds: 26, northSeeds: 22, southHouses: 7, northHouses: 5))
    }

    @Test("A position with the other side already empty and no way to feed ends the round on the first move")
    func alreadyStuck() throws {
        var s = state([1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], stores: [24, 23])
        try s.apply(Move(player: .south, absoluteHouse: 0))
        #expect(s.roundHistory.last == RoundResult(round: 1, southSeeds: 25, northSeeds: 23, southHouses: 7, northHouses: 5))
    }

    // MARK: The last four

    @Test("The last four includes seeds still in hand")
    func lastFourWithSeedsInHand() throws {
        //                  A1 A2 A3 A4 A5 A6  B1 B2 B3 B4 B5 B6
        var s = state([2, 3, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0], stores: [20, 20])
        // A1(2): A2 3→4 (South's), one seed still in hand; B3's three + that seed are the last four.
        let events = try s.apply(Move(player: .south, absoluteHouse: 0))
        #expect(captures(events).map(\.house) == [1, 8])
        #expect(s.roundHistory.last == RoundResult(round: 1, southSeeds: 28, northSeeds: 20, southHouses: 7, northHouses: 5))
        #expect(s.totalSeeds == 48)
    }

    @Test("A passing four that goes to the other player still triggers the last four for them")
    func lastFourGoesToWhoeverTookThePenultimate() throws {
        //                  A1 A2 A3 A4 A5 A6  B1 B2 B3 B4 B5 B6
        var s = state([0, 0, 0, 0, 0, 2, 3, 0, 0, 3, 0, 0], stores: [20, 20])
        // A6(2): B1 3→4 in passing → North's; left: B4's 3 + one in hand = 4 → North takes them.
        let events = try s.apply(Move(player: .south, absoluteHouse: 5))
        #expect(captures(events).allSatisfy { $0.by == .north })
        #expect(s.roundHistory.last?.northSeeds == 28)
    }

    // MARK: Endless relays

    @Test("A relay chain that would go round for ever stops when it repeats itself")
    func endlessRelayStops() throws {
        // Found by random play: round 2, South holds A1–A2, North to move B6. Without the cycle
        // check the seeds circle the board for ever.
        //                  A1 A2 A3 A4 A5 A6  B1 B2 B3 B4 B5 B6
        var s = state([0, 1, 0, 2, 1, 0, 2, 1, 0, 2, 1, 2], toMove: .north, stores: [16, 20], southHouses: 2)
        let sim = s.simulateNamNam(Move(player: .north, absoluteHouse: 11))
        let relays = sim.steps.filter { if case .relayed = $0 { return true } else { return false } }.count
        #expect(relays < GameState.maxRelayLaps, "stopped by the cycle check, not the backstop")
        #expect(relays > 20, "this position really does loop")
        try s.apply(Move(player: .north, absoluteHouse: 11))
        #expect(s.totalSeeds == 48)
    }

    // MARK: Rounds and the end of the game

    @Test("Rounds alternate who starts: North in round 2, South in round 3")
    func starterAlternates() {
        var s = afterRound(south: 24, north: 24)
        #expect(s.round == 2 && s.sideToMove == .north)
        _ = s.endByAgreement()   // board refilled with 4s: each side keeps its 24
        #expect(s.round == 3 && s.sideToMove == .south)
    }

    @Test("The round cap ends the game on houses", arguments: [(28, 20, Player?.some(.south)), (20, 28, .north), (24, 24, nil)])
    func roundCap(south: Int, north: Int, winner: Player?) {
        var s = state(Array(repeating: 0, count: 12), stores: [south, north], rules: RuleSet(variant: .namNam, maxRounds: 1))
        _ = s.endByAgreement()
        #expect(s.outcome?.reason == .roundLimit)
        #expect(s.outcome?.winner == winner)
    }

    @Test("Holding all twelve houses wins, and a player left with none has lost")
    func allTwelve() {
        let s = afterRound(south: 48, north: 0)
        #expect(s.outcome == .win(.south, .territory))
        #expect(s.legalMoves().isEmpty)
        let t = afterRound(south: 1, north: 47)
        #expect(t.outcome == .win(.north, .territory))
    }

    @Test("Moves after the game has ended are refused")
    func noMovesAfterEnd() {
        var s = afterRound(south: 48, north: 0)
        #expect(throws: MoveError.gameIsOver) { try s.apply(Move(player: .south, absoluteHouse: 0)) }
    }

    // MARK: Saves

    @Test("A Nam-Nam game saved mid-round resumes with its territory, round and history")
    func codableMidRound() throws {
        var s = afterRound(south: 32, north: 16)
        try s.apply(s.legalMoves()[0])
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        #expect(back == s)
        #expect(back.territory == s.territory && back.round == 2 && back.roundHistory.count == 1)
    }

    @Test("Saves from before Nam-Nam load as Abapa with the usual rows")
    func oldSavesLoadAsAbapa() throws {
        let data = try JSONEncoder().encode(GameState.initial)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["territory", "round", "lastCapturer", "roundHistory"] { json.removeValue(forKey: key) }
        var rules = try #require(json["rules"] as? [String: Any])
        rules.removeValue(forKey: "variant"); rules.removeValue(forKey: "maxRounds")
        json["rules"] = rules
        let old = try JSONSerialization.data(withJSONObject: json)
        let back = try JSONDecoder().decode(GameState.self, from: old)
        #expect(back.rules.variant == .abapa)
        #expect(back.territory == GameState.defaultTerritory)
        #expect(back.round == 1)
    }
}

