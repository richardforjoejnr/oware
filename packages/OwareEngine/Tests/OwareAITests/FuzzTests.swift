import Foundation
import Testing
import OwareEngine
@testable import OwareAI

/// Seeded whole-game fuzzing: random movers and low-depth AIs play complete games under every rule
/// combination, and every ply is checked. Deterministic: no time limits are involved.
@Suite("Fuzz: whole games")
struct FuzzTests {
    static let ruleSets: [RuleSet] = {
        var all: [RuleSet] = []
        for mustFeed in [true, false] {
            for grandSlam in RuleSet.GrandSlamRule.allCases {
                all.append(RuleSet(variant: .abapa, grandSlam: grandSlam, mustFeed: mustFeed))
            }
            all.append(RuleSet(variant: .namNam, mustFeed: mustFeed))
        }
        all.append(RuleSet(repetitionLimit: 2))
        all.append(RuleSet(variant: .namNam, repetitionLimit: 2, maxRounds: 5))
        return all
    }()

    enum Mover { case random, analyse(depth: Int), player(AIPlayer) }

    @Test("Random and AI players finish every game legally, with all 48 seeds", arguments: ruleSets)
    func wholeGames(rules: RuleSet) throws {
        // A stable seed per rule set (hashValue changes from run to run).
        let name = "\(rules.variant)/\(rules.grandSlam)/\(rules.mustFeed)/\(rules.repetitionLimit)/\(rules.maxRounds)"
        var rng = SeededGenerator(seed: name.utf8.reduce(0xF022) { ($0 ^ UInt64($1)) &* 0x100_0000_01B3 })
        let movers: [Mover] = [.random, .analyse(depth: 1), .analyse(depth: 2), .player(AIPlayer(difficulty: .beginner)),
                               .player(AIPlayer(difficulty: .learner, personality: .trickster))]
        // Plenty for any real game: Abapa ends by repetition long before, Nam-Nam rounds are capped.
        let plyLimit = rules.variant == .abapa ? 2_000 : 5_000 * rules.maxRounds
        for game in 0..<40 {   // covers every south/north pairing of the five movers
            let south = movers[game % movers.count], north = movers[(game / movers.count + game) % movers.count]
            var state = GameState.initial(rules: rules)
            var plies = 0
            while !state.isOver {
                let legal = state.legalMoves()
                try #require(!legal.isEmpty, "a game that is not over must have a move\n\(state)")
                let move: Move?
                switch state.sideToMove == .south ? south : north {
                case .random: move = legal.randomElement(using: &rng)
                case let .analyse(depth): move = AIPlayer.analyse(state, depth: depth)?.move
                case let .player(ai): move = ai.chooseMove(for: state, seed: rng.next())
                }
                let chosen = try #require(move)
                try #require(legal.contains(chosen), "\(chosen) is not legal\n\(state)")
                let before = state
                let events = try state.apply(chosen)
                plies += 1
                #expect(state.totalSeeds == 48, "\(chosen)\n\(before)")
                #expect(state.houses.allSatisfy { $0 >= 0 } && state.stores.allSatisfy { $0 >= 0 })
                #expect(!events.isEmpty)
                if plies % 50 == 0 {
                    #expect(try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state)) == state)
                }
                try #require(plies <= plyLimit, "game did not finish\n\(state)")
            }
            #expect(state.legalMoves().isEmpty)
            #expect(state.totalSeeds == 48)
        }
    }
}
