import Testing
@testable import LudoEngine

/// A game with tokens placed by hand. Progress per colour; omitted colours stay in the yard.
private func game(_ placed: [PlayerColor: [Int]], rules: RuleSet = .ghana, players: [PlayerColor] = [.red, .gold], toMove: PlayerColor = .red) -> GameState {
    var g = GameState(players: players, rules: rules, first: toMove)
    g.place(placed)
    return g
}

@Suite("Core rules")
struct CoreRulesTests {
    @Test("Only a 6 brings a token out of the yard, onto the start square")
    func enterOnSix() throws {
        var g = GameState(players: [.red, .gold])
        g.roll(5)
        #expect(g.toMove == .gold, "nothing to move: the turn passes")
        g.roll(6)
        let moves = g.legalMoves()
        #expect(moves.count == 4 && moves.allSatisfy { $0.kind == .enter && $0.to == 0 })
        try g.apply(moves[0])
        #expect(g.tokens(of: .gold)[0] == 0)
        #expect(g.toMove == .gold && g.pendingRoll == nil, "a 6 rolls again")
    }

    @Test("A gentler game can let 1 and 6 bring tokens out")
    func gentleEntry() {
        var g = GameState(players: [.red, .gold], rules: RuleSet(entryRolls: [1, 6]))
        g.roll(1)
        #expect(!g.legalMoves().isEmpty)
    }

    @Test("Tokens move forwards by the roll; a non-6 passes the turn")
    func forward() throws {
        var g = game([.red: [10, -1, -1, -1]])
        g.roll(4)
        try g.apply(try #require(g.legalMoves().first { $0.kind == .forward }))
        #expect(g.tokens(of: .red)[0] == 14)
        #expect(g.toMove == .gold)
    }

    @Test("Landing on a lone opponent kicks it back to its yard, and earns a roll")
    func forwardKick() throws {
        var g = game([.red: [10, -1, -1, -1], .gold: [Self.goldProgress(atTrack: 14), -1, -1, -1]])
        g.roll(4)
        let events = try g.apply(try #require(g.legalMoves().first { $0.kind == .forward }))
        #expect(g.tokens(of: .gold)[0] == Board.yard)
        #expect(events.contains(.kicked(.gold, token: 0, at: 14, by: .red)))
        #expect(g.toMove == .red, "a kick earns another roll")
    }

    static func goldProgress(atTrack t: Int) -> Int { (t - Board.startIndex(.gold) + Board.trackLength) % Board.trackLength }

    @Test("The home lane is private and home needs the exact roll")
    func exactHome() {
        var g = game([.red: [53, -1, -1, -1]])
        g.roll(4)   // 57 would overshoot
        #expect(g.toMove == .gold, "no legal move: passed")
        var h = game([.red: [53, -1, -1, -1]])
        h.roll(3)
        #expect(h.legalMoves().contains { $0.to == Board.home })
    }

    @Test("Bringing the last token home wins")
    func win() throws {
        var g = game([.red: [56, 56, 56, 55]])
        g.roll(1)
        let events = try g.apply(try #require(g.legalMoves().first))
        #expect(g.winner == .red && g.isOver)
        #expect(events.last == .won(.red))
    }

    @Test("A move that is not legal is refused")
    func illegal() {
        var g = game([.red: [10, -1, -1, -1]])
        g.roll(3)
        #expect(throws: GameState.MoveError.self) { try g.apply(Move(token: 0, kind: .forward, from: 10, to: 20)) }
    }
}

@Suite("House rules")
struct HouseRulesTests {
    @Test("Back kick: an opponent exactly the roll behind can be kicked by moving back")
    func backKick() throws {
        let behind = CoreRulesTests.goldProgress(atTrack: 7)   // red token on track 12, gold on 7
        var g = game([.red: [12, -1, -1, -1], .gold: [behind, -1, -1, -1]])
        g.roll(5)
        let back = try #require(g.legalMoves().first { $0.kind == .backKick })
        #expect(back.to == 7)
        try g.apply(back)
        #expect(g.tokens(of: .gold)[0] == Board.yard)
        #expect(g.tokens(of: .red)[0] == 7)
    }

    @Test("No back kick without an opponent to kick, behind the start, or with the rule off")
    func noBackKick() {
        var g = game([.red: [12, -1, -1, -1]])
        g.roll(5)
        #expect(!g.legalMoves().contains { $0.kind == .backKick }, "nobody there")
        var h = game([.red: [3, -1, -1, -1], .gold: [CoreRulesTests.goldProgress(atTrack: 50), -1, -1, -1]])
        h.roll(5)
        #expect(!h.legalMoves().contains { $0.kind == .backKick }, "never back past your own start")
        var off = game([.red: [12, -1, -1, -1], .gold: [CoreRulesTests.goldProgress(atTrack: 7), -1, -1, -1]], rules: .classic)
        off.roll(5)
        #expect(!off.legalMoves().contains { $0.kind == .backKick })
    }

    @Test("Wall: two of a colour on a square cannot be passed, landed on or kicked")
    func wall() {
        let g7 = CoreRulesTests.goldProgress(atTrack: 7)
        var g = game([.red: [5, -1, -1, -1], .gold: [g7, g7, -1, -1]])
        g.roll(4)   // red 5 → 9 would pass the wall on 7
        #expect(g.toMove == .gold, "blocked: passed")
        var land = game([.red: [5, -1, -1, -1], .gold: [g7, g7, -1, -1]])
        land.roll(2)
        #expect(!land.legalMoves().contains { $0.to == 7 }, "a wall cannot be landed on")
    }

    @Test("Safe stacks can be passed but not kicked")
    func safeStack() throws {
        let g7 = CoreRulesTests.goldProgress(atTrack: 7)
        var g = game([.red: [5, -1, -1, -1], .gold: [g7, g7, -1, -1]], rules: RuleSet(stacking: .safe))
        g.roll(4)
        #expect(g.legalMoves().contains { $0.kind == .forward && $0.to == 9 }, "passing is fine")
        var land = game([.red: [5, -1, -1, -1], .gold: [g7, g7, -1, -1]], rules: RuleSet(stacking: .safe))
        land.roll(2)
        #expect(!land.legalMoves().contains { $0.to == 7 })
    }

    @Test("One token per square: you may not end on your own token")
    func oneTokenPerSquare() {
        var g = game([.red: [5, 9, -1, -1]], rules: RuleSet(stacking: .notAllowed))
        g.roll(4)
        #expect(!g.legalMoves().contains { $0.token == 0 && $0.to == 9 })
    }

    @Test("Three sixes in a row undo the turn and pass play")
    func threeSixes() throws {
        var g = game([.red: [10, 20, -1, -1]])
        g.roll(6); try g.apply(try #require(g.legalMoves().first { $0.token == 0 && $0.kind == .forward }))
        g.roll(6); try g.apply(try #require(g.legalMoves().first { $0.token == 1 && $0.kind == .forward }))
        let events = g.roll(6)
        #expect(events.contains(.threeSixes(.red)))
        #expect(g.tokens(of: .red) == [10, 20, -1, -1], "the turn's moves are undone")
        #expect(g.toMove == .gold)
        var classic = game([.red: [10, 20, -1, -1]], rules: .classic)
        classic.roll(6); try classic.apply(classic.legalMoves().first!)
        classic.roll(6); try classic.apply(classic.legalMoves().first!)
        classic.roll(6)
        #expect(classic.pendingRoll == 6, "without the rule a third 6 is just a roll")
    }

    @Test("With the rule off a kick does not earn a roll")
    func noKickBonus() throws {
        var g = game([.red: [10, -1, -1, -1], .gold: [CoreRulesTests.goldProgress(atTrack: 14), -1, -1, -1]], rules: .classic)
        g.roll(4)
        try g.apply(try #require(g.legalMoves().first))
        #expect(g.toMove == .gold)
    }

    @Test("Safe start squares protect any token on them")
    func safeStart() {
        let onGoldStart = Board.startIndex(.gold)   // track 13
        var g = game([.red: [onGoldStart - 3, -1, -1, -1], .gold: [0, -1, -1, -1]], rules: RuleSet(startSquaresSafe: true))
        g.roll(3)
        #expect(g.legalMoves().contains { $0.to == onGoldStart })
        var h = g
        _ = try? h.apply(g.legalMoves().first { $0.to == onGoldStart }!)
        #expect(h.tokens(of: .gold)[0] == 0, "not kicked on a safe square")
    }
}

@Suite("Whole games")
struct WholeGameTests {
    struct LCG: RandomNumberGenerator {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
    }

    @Test("Random games under every rule set finish with a winner and tokens always in range",
          arguments: [RuleSet.ghana, .classic, RuleSet(stacking: .notAllowed), RuleSet(stacking: .safe, startSquaresSafe: true, starSquaresSafe: true)])
    func randomGames(rules: RuleSet) throws {
        for seed in 0..<60 {
            var rng = LCG(s: UInt64(seed) &+ 99)
            let players = Array(PlayerColor.allCases.prefix(2 + seed % 3))
            var g = GameState(players: players, rules: rules)
            var rolls = 0
            while !g.isOver && rolls < 20_000 {
                g.roll(Int.random(in: 1...6, using: &rng))
                rolls += 1
                let moves = g.legalMoves()
                if !moves.isEmpty { try g.apply(moves.randomElement(using: &rng)!) }
                for c in PlayerColor.allCases { #expect(g.tokens(of: c).allSatisfy { (Board.yard...Board.home).contains($0) }) }
            }
            #expect(g.winner != nil, "seed \(seed) finished")
        }
    }

    @Test("A game encodes and decodes to the same state")
    func codable() throws {
        var g = GameState(players: [.red, .black])
        g.roll(6)
        let data = try JSONEncoder().encode(g)
        #expect(try JSONDecoder().decode(GameState.self, from: data) == g)
    }
}

import Foundation
