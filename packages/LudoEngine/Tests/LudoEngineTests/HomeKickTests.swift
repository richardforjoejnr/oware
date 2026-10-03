import Foundation
import Testing
@testable import LudoEngine

/// Home kick (owner's Ghana Classic rule, 2026-10-03): an opponent in their own home lane is not
/// safe. With the exact roll a token turns into that lane and kicks them; it stays there and on later
/// turns walks back out the way it came before carrying on.
///
/// Yellow's lane entrance is track square 11 (the top of the board), which is red's progress 11.
@Suite("Home kick")
struct HomeKickTests {
    static let rules = RuleSet(homeKick: true)

    func game(_ placed: [PlayerColor: [Int]], visits: [PlayerColor: [Move.Visit?]] = [:], rules: RuleSet = Self.rules) -> GameState {
        var g = GameState(players: [.red, .yellow], rules: rules, first: .red)
        g.place(placed, visits: visits)
        return g
    }

    @Test("The entrance square and its progress are where the rule expects")
    func geometry() {
        #expect(Board.entranceIndex(.yellow) == 11)
        #expect(Board.track[11] == Board.Cell(7, 0))
        #expect(Board.lane(.yellow)[0] == Board.Cell(7, 1))
    }

    @Test("With the exact roll, a token turns into the lane and kicks the token there")
    func kicksInTheLane() throws {
        // Red at 8 is 3 short of yellow's entrance; yellow has a token 2 squares into its lane (52).
        var g = game([.red: [8, -1, -1, -1], .yellow: [52, -1, -1, -1]])
        g.roll(5)
        let kick = try #require(g.legalMoves().first { $0.kind == .homeKick })
        #expect(kick.to == 11 && kick.visit == Move.Visit(owner: .yellow, depth: 2))
        #expect(g.legalMoves().contains { $0.kind == .forward && $0.to == 13 }, "walking on is still a choice")
        let events = try g.apply(kick)
        #expect(g.tokens(of: .yellow)[0] == Board.yard)
        #expect(g.visit(of: .red, token: 0) == Move.Visit(owner: .yellow, depth: 2))
        #expect(events.contains(.kickedInLane(.yellow, token: 0, lane: .yellow, depth: 2, by: .red)))
        #expect(g.toMove == .red, "a kick earns another roll")
    }

    @Test("Only the exact roll, only onto an opponent, and only with the rule on")
    func onlyExact() {
        var short = game([.red: [8, -1, -1, -1], .yellow: [52, -1, -1, -1]])
        short.roll(4)   // would reach the lane's first square, which is empty
        #expect(!short.legalMoves().contains { $0.kind == .homeKick })
        var off = game([.red: [8, -1, -1, -1], .yellow: [52, -1, -1, -1]], rules: RuleSet())
        off.roll(5)
        #expect(!off.legalMoves().contains { $0.kind == .homeKick })
    }

    @Test("Never into a lane whose entrance is behind you")
    func notBehind() {
        var g = game([.red: [12, -1, -1, -1], .yellow: [52, -1, -1, -1]])
        g.roll(3)   // red has passed yellow's entrance (11)
        #expect(!g.legalMoves().contains { $0.kind == .homeKick })
    }

    @Test("A visitor walks back out: inside the lane, onto the entrance, then on along the track",
          arguments: [(1, 11, 1), (2, 11, nil), (5, 14, nil)] as [(Int, Int, Int?)])
    func walksOut(roll: Int, progress: Int, depth: Int?) throws {
        var g = game([.red: [11, -1, -1, -1]], visits: [.red: [Move.Visit(owner: .yellow, depth: 2), nil, nil, nil]])
        g.roll(roll)
        let out = try #require(g.legalMoves().first { $0.kind == .walkOut })
        try g.apply(out)
        #expect(g.tokens(of: .red)[0] == progress)
        #expect(g.visit(of: .red, token: 0)?.depth == depth)
    }

    @Test("A visitor cannot go deeper or kick from the lane any other way")
    func visitorMovesOnlyOut() {
        var g = game([.red: [11, -1, -1, -1]], visits: [.red: [Move.Visit(owner: .yellow, depth: 2), nil, nil, nil]])
        g.roll(3)
        #expect(g.legalMoves().filter { $0.token == 0 }.allSatisfy { $0.kind == .walkOut })
    }

    @Test("The lane's owner can kick a visitor by landing on it")
    func ownerKicksVisitor() throws {
        var g = GameState(players: [.red, .yellow], rules: Self.rules, first: .yellow)
        g.place([.red: [11, -1, -1, -1], .yellow: [51, -1, -1, -1]], visits: [.red: [Move.Visit(owner: .yellow, depth: 2), nil, nil, nil]])
        g.roll(1)   // yellow 51 → 52, the visitor's square
        try g.apply(try #require(g.legalMoves().first { $0.token == 0 }))
        #expect(g.tokens(of: .red)[0] == Board.yard)
        #expect(g.visit(of: .red, token: 0) == nil, "a kicked token leaves the lane for its yard")
    }

    @Test("Three sixes undo a home kick too")
    func threeSixesUndo() throws {
        // Red at 6 is 5 short of yellow's entrance; a 6 reaches yellow's first lane square (51).
        var g = game([.red: [6, 30, -1, -1], .yellow: [51, -1, -1, -1]])
        g.roll(6)
        try g.apply(try #require(g.legalMoves().first { $0.kind == .homeKick }))
        #expect(g.tokens(of: .yellow)[0] == Board.yard)
        g.roll(6)
        try g.apply(try #require(g.legalMoves().first { $0.token == 1 }))
        g.roll(6)
        #expect(g.tokens(of: .red) == [6, 30, -1, -1], "everything the turn did is undone")
        #expect((0..<4).allSatisfy { g.visit(of: .red, token: $0) == nil })
        #expect(g.tokens(of: .yellow)[0] == 51, "the kicked token is back in its lane")
    }

    @Test("A game with a visitor saves and loads exactly")
    func saves() throws {
        let g = game([.red: [11, -1, -1, -1]], visits: [.red: [Move.Visit(owner: .yellow, depth: 3), nil, nil, nil]])
        #expect(try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(g)) == g)
    }
}
