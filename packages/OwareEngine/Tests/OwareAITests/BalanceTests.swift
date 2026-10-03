import Foundation
import Testing
import OwareEngine
@testable import OwareAI

/// The difficulty ladder against simulated people (see Difficulty). A "casual" player always takes
/// the biggest capture they can see and never looks further; the levels must form even steps down
/// from "they usually win" (Novice) to "they rarely do" (Strategist), in both rule sets. Seeded, so
/// the same games are played every run.
@Suite("Difficulty balance")
struct BalanceTests {
    static let games = 40

    /// The casual player's score (win 1, draw ½) against `level`, alternating who starts.
    static func casualScore(against level: Difficulty, rules: RuleSet) throws -> Double {
        let ai = AIPlayer(difficulty: level)
        var total = 0.0
        for g in 0..<games {
            var rng = SeededGenerator(seed: 0xBA1A_0000 &+ UInt64(g) &* 7919 &+ UInt64(level.rawValue))
            var state = GameState.initial(rules: rules)
            let human: Player = g % 2 == 0 ? .south : .north
            var plies = 0
            while !state.isOver && plies < 3000 {
                let legal = state.legalMoves()
                let move: Move
                if state.sideToMove == human {
                    move = AIPlayer.analyse(state, depth: 1)?.move ?? legal[0]
                } else {
                    // No time budget: the same games on any machine.
                    move = try #require(ai.chooseMove(for: state, using: &rng, timeBudget: nil))
                }
                try state.apply(move)
                plies += 1
            }
            total += state.outcome?.winner.map { $0 == human ? 1 : 0 } ?? 0.5
        }
        return total / Double(games)
    }

    @Test("A casual player usually beats Novice and Intermediate, rarely Strategist", arguments: [RuleSet.namNam, .abapa])
    func ladder(rules: RuleSet) throws {
        let novice = try Self.casualScore(against: .beginner, rules: rules)
        let intermediate = try Self.casualScore(against: .learner, rules: rules)
        let strategist = try Self.casualScore(against: .strong, rules: rules)
        let master = try Self.casualScore(against: .master, rules: rules)
        print("Balance \(rules.variant): casual wins Novice \(novice), Intermediate \(intermediate), Strategist \(strategist), master \(master)")
        #expect(novice >= 0.75, "Novice should be easy: \(novice)")
        #expect(intermediate >= 0.5, "Intermediate should be winnable: \(intermediate)")
        #expect(strategist <= 0.6, "Strategist should be a challenge: \(strategist)")
        #expect(novice >= intermediate && intermediate >= strategist && strategist >= master, "each level is harder than the one before")
    }

    @Test("Menu levels and names")
    func menu() {
        #expect(Difficulty.menuLevels.map(\.displayName) == ["Novice", "Intermediate", "Strategist", "Grandmaster"])
        // Saved choices keep their name: the old Intermediate (player) and Strategist (master) map on.
        #expect(Difficulty.player.menuLevel.displayName == "Intermediate")
        #expect(Difficulty.master.menuLevel.displayName == "Strategist")
    }
}
