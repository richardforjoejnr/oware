import Foundation
import Testing
import LudoEngine
@testable import LudoAI

/// The levels against a simulated casual player under Ghana Classic. Ludo is mostly dice, so even
/// Grandmaster loses a fair share; what matters is the order and that Novice is beatable.
/// Measured (400 games each, 2026-10-04): the casual player wins 64% against Novice, 37% against
/// Intermediate, 25% against Strategist, 22% against Grandmaster.
@Suite("Balance against a casual player")
struct BalanceTests {
    /// Takes a kick when it sees one, otherwise moves its most advanced token; 30% of the time it
    /// plays a random move instead.
    static func casualMove(_ s: GameState, _ rng: inout SeededGenerator) -> Move? {
        let legal = s.legalMoves()
        guard !legal.isEmpty else { return nil }
        if Double.random(in: 0..<1, using: &rng) < 0.3 { return legal.randomElement(using: &rng) }
        let kicks = legal.filter { m in
            var copy = s
            return ((try? copy.apply(m)) ?? []).contains { if case .kicked = $0 { true } else if case .kickedInLane = $0 { true } else { false } }
        }
        return kicks.first ?? legal.max { $0.from < $1.from }
    }

    static func casualWins(against level: Difficulty, games: Int) throws -> Double {
        let ai = AIPlayer(difficulty: level)
        var wins = 0
        for g in 0..<games {
            var rng = SeededGenerator(seed: UInt64(g) &* 7919 &+ 3)
            let casual: PlayerColor = g % 2 == 0 ? .red : .black
            var s = GameState(players: [.red, .black], rules: .ghanaClassic, first: g % 4 < 2 ? .red : .black)
            var n = 0
            while !s.isOver && n < 5000 {
                n += 1
                s.roll(Int.random(in: 1...6, using: &rng))
                let move = s.toMove == casual ? casualMove(s, &rng) : ai.chooseMove(s, using: &rng)
                if let move { try s.apply(move) }
            }
            if s.winner == casual { wins += 1 }
        }
        return Double(wins) / Double(games)
    }

    @Test("Novice is beatable, and each level is at least as hard as the one below")
    func ladder() throws {
        let rates = try Difficulty.allCases.map { try Self.casualWins(against: $0, games: 160) }
        print("Ludo balance (casual player wins): \(zip(Difficulty.allCases, rates).map { "\($0.0) \($0.1)" })")
        #expect(rates[0] >= 0.5, "a casual player usually beats Novice: \(rates[0])")
        #expect(rates[1] >= 0.25, "and often enough Intermediate: \(rates[1])")
        #expect(rates[3] <= 0.4, "Grandmaster is a challenge: \(rates[3])")
        #expect(rates[0] > rates[1] && rates[1] > rates[2] - 0.05 && rates[2] > rates[3] - 0.05, "harder up the ladder: \(rates)")
    }
}
