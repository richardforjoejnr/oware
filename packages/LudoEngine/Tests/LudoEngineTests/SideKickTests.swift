import Foundation
import Testing
@testable import LudoEngine

/// Side kicks (owner's Ghana Classic rule, 2026-10-03): after a legal move forwards (or backwards),
/// a token directly across a home lane from an opponent, with the lane square between them clear,
/// jumps across and kicks them. Each is its own legal move; the player chooses.
///
/// The top arm: the left column (6, 5…0) is track 5…10, going up; the right column (8, 0…5) is track
/// 12…17, going down; yellow's lane runs down the middle (7, 1…5). (6,3) is track 7, (8,3) track 15.
@Suite("Side kicks")
struct SideKickTests {
    static let rules = RuleSet(homeKick: false, forwardSideKick: true, backSideKick: true)

    func game(_ placed: [PlayerColor: [Int]], rules: RuleSet = Self.rules) -> GameState {
        var g = GameState(players: [.red, .yellow], rules: rules, first: .red)
        g.place(placed)
        return g
    }

    /// Yellow's progress that puts a yellow token on track square `t`.
    func yellow(_ t: Int) -> Int { GameState.progress(of: .yellow, atTrackIndex: t) }

    @Test("Squares across each home lane are paired, with the lane square between")
    func pairs() {
        let across = Board.across[7]
        #expect(across?.opposite == 15 && across?.laneOwner == .yellow && across?.depth == 3)
        #expect(Board.across[15]?.opposite == 7)
        #expect(Board.across.count == 40, "4 lanes × 5 squares × both sides")
    }

    @Test("Forward side kick: move by the roll, then across onto the opponent")
    func forward() throws {
        // Red 5 → 7 with a 2, across the lane to 15 where a yellow token stands.
        var g = game([.red: [5, -1, -1, -1], .yellow: [yellow(15), -1, -1, -1]])
        g.roll(2)
        let side = try #require(g.legalMoves().first { $0.kind == .sideKickForward })
        #expect(side.from == 5 && side.to == 15)
        #expect(g.legalMoves().contains { $0.kind == .forward && $0.to == 7 }, "the plain move is still a choice")
        let events = try g.apply(side)
        #expect(g.tokens(of: .yellow)[0] == Board.yard)
        #expect(g.tokens(of: .red)[0] == 15)
        #expect(events.contains(.kicked(.yellow, token: 0, at: 15, by: .red)))
    }

    @Test("Back side kick: back by the roll, then across")
    func back() throws {
        // Red 17 back 2 to 15, across to 7 where yellow stands.
        var g = game([.red: [17, -1, -1, -1], .yellow: [yellow(7), -1, -1, -1]])
        g.roll(2)
        let side = try #require(g.legalMoves().first { $0.kind == .sideKickBack })
        #expect(side.from == 17 && side.to == 7)
        try g.apply(side)
        #expect(g.tokens(of: .yellow)[0] == Board.yard)
    }

    @Test("Not if the lane square between is occupied")
    func blockedByTheLane() {
        // Yellow has a token on its lane square 3, between (6,3) and (8,3).
        var g = game([.red: [5, -1, -1, -1], .yellow: [yellow(15), 53, -1, -1]])
        g.roll(2)
        #expect(!g.legalMoves().contains { $0.kind == .sideKickForward })
    }

    @Test("Across your own home lane too: from the start of the journey almost to its end")
    func acrossOwnLane() throws {
        // Red 0 → 1 is (2,6); across red's own lane is (2,8), track 47: red's progress 47.
        var g = game([.red: [0, -1, -1, -1], .yellow: [yellow(47), -1, -1, -1]])
        g.roll(1)
        let side = try #require(g.legalMoves().first { $0.kind == .sideKickForward })
        #expect(side.to == 47, "a shortcut home: 46 squares in one move")
        try g.apply(side)
        #expect(g.tokens(of: .red)[0] == 47 && g.tokens(of: .yellow)[0] == Board.yard)
    }

    @Test("Your own lane square between must be clear too")
    func ownLaneMustBeClear() {
        // Red's lane square 2 is (2,7); a red token there blocks the jump from (2,6) to (2,8).
        var g = game([.red: [0, 52, -1, -1], .yellow: [yellow(47), -1, -1, -1]])
        g.roll(1)
        #expect(!g.legalMoves().contains { $0.kind == .sideKickForward })
    }

    @Test("Never from inside your own home lane (found by the reference implementation)")
    func notFromTheHomeLane() {
        // Red token on its lane square 4 (54): stepping back 6 to 48 and across would be a side kick
        // if lane tokens could step out. They cannot: the home lane only leads home.
        var g = game([.red: [54, -1, -1, -1], .yellow: [yellow(0), -1, -1, -1]])
        g.roll(6)
        #expect(!g.legalMoves().contains { $0.kind == .sideKickBack || $0.kind == .sideKickForward })
    }

    @Test("Only with the rules on, and only onto a lone opponent")
    func onlyWithTheRule() {
        var off = game([.red: [5, -1, -1, -1], .yellow: [yellow(15), -1, -1, -1]], rules: RuleSet(forwardSideKick: false, backSideKick: false))
        off.roll(2)
        #expect(!off.legalMoves().contains { $0.kind == .sideKickForward || $0.kind == .sideKickBack })
        var wall = game([.red: [5, -1, -1, -1], .yellow: [yellow(15), yellow(15), -1, -1]])
        wall.roll(2)
        #expect(!wall.legalMoves().contains { $0.kind == .sideKickForward }, "a pair is a wall")
        var empty = game([.red: [5, -1, -1, -1]])
        empty.roll(2)
        #expect(!empty.legalMoves().contains { $0.kind == .sideKickForward }, "nobody across")
    }
}
