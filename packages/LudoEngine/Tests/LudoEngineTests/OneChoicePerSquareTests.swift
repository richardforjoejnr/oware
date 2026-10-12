import Foundation
import Testing
@testable import LudoEngine

/// One move, one choice. Round a corner a side kick can land on the very square a straight move by
/// the roll lands on, kicking the same token (found in play, 2026-10-11: "Back kick" and a second
/// marker both took the computer's pawn). It is listed once, as the straight move.
@Suite("One choice per square")
struct OneChoicePerSquareTests {
    func game(_ players: [PlayerColor], _ placed: [PlayerColor: [Int]], toMove: PlayerColor) -> GameState {
        var g = GameState(players: players, rules: .ghanaClassic, first: toMove)
        g.place(placed)
        return g
    }

    /// `color`'s progress for the track square `mover` reaches at `progress`.
    func on(_ color: PlayerColor, whereMover mover: PlayerColor, isAt progress: Int) -> Int {
        GameState.progress(of: color, atTrackIndex: Board.trackIndex(mover, progress: progress))
    }

    @Test("Back 3 onto a token, or forward 3 and across onto it: one back kick")
    func backKickNotAlsoASideKick() {
        // Yellow on 24 with a 3; a black token 3 behind. Forward 3 to 27 and across the lane lands there too.
        var g = game([.yellow, .black], [.yellow: [-1, -1, -1, 24], .black: [on(.black, whereMover: .yellow, isAt: 21), -1, -1, -1]], toMove: .yellow)
        g.roll(3)
        let mine = g.legalMoves().filter { $0.token == 3 }
        #expect(Set(mine.map(\.kind)) == [.forward, .backKick], "the plain move to an empty square, and the back kick, once: \(mine)")
    }

    @Test("Forward 2 onto a token, or back 2 and across onto it: one forward move")
    func forwardNotAlsoASideKick() {
        var g = game([.black, .green], [.black: [-1, -1, 11, -1], .green: [-1, -1, on(.green, whereMover: .black, isAt: 13), -1]], toMove: .black)
        g.roll(2)
        let mine = g.legalMoves().filter { $0.token == 2 }
        #expect(mine.map(\.kind) == [.forward], "\(mine)")
        var after = g
        let events = try? after.apply(mine[0])
        #expect(events?.contains { if case .kicked(.green, 2, _, _) = $0 { true } else { false } } == true, "it still kicks")
    }

    @Test("With the straight way blocked by a wall, the side kick is the way there, and stays")
    func sideKickStaysWhenTheStraightWayIsBlocked() {
        let wall = on(.yellow, whereMover: .black, isAt: 12)
        var g = game([.black, .green, .yellow],
                     [.black: [-1, -1, 11, -1], .green: [-1, -1, on(.green, whereMover: .black, isAt: 13), -1], .yellow: [wall, wall, -1, -1]],
                     toMove: .black)
        g.roll(2)
        let mine = g.legalMoves().filter { $0.token == 2 }
        #expect(mine.map(\.kind) == [.sideKickBack], "\(mine)")
    }

    @Test("In random games under every kick rule, no token is ever offered two moves to one square")
    func neverTwoMovesToOneSquare() throws {
        var rng = SeededRandom(seed: 11)
        for rules in [RuleSet.ghanaClassic, RuleSet(homeKick: true, forwardSideKick: true, backSideKick: true)] {
            for _ in 0..<40 {
                var g = GameState(players: PlayerColor.allCases, rules: rules, first: .red)
                for _ in 0..<1500 where g.winner == nil {
                    g.roll(Int.random(in: 1...6, using: &rng))
                    let moves = g.legalMoves()
                    guard !moves.isEmpty else { continue }
                    for (_, same) in Dictionary(grouping: moves, by: \.token) {
                        let ends = same.map { [$0.to, $0.visit?.owner.rawValue ?? -1, $0.visit?.depth ?? 0] }
                        try #require(Set(ends).count == ends.count, "two moves to one square: \(same)")
                    }
                    _ = try g.apply(moves.randomElement(using: &rng)!)
                }
            }
        }
    }
}

/// SplitMix64, so the sweep is the same every run.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
