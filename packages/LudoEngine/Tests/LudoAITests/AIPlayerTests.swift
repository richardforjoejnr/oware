import Foundation
import Testing
@testable import LudoAI
@testable import LudoEngine

private func game(_ placed: [PlayerColor: [Int]], rules: RuleSet = .ghana, players: [PlayerColor] = [.red, .yellow], roll: Int) -> GameState {
    var g = GameState(players: players, rules: rules, first: .red)
    g.place(placed)
    g.roll(roll)
    return g
}

/// Yellow's progress that puts a yellow token on track square `t`.
private func yellow(_ t: Int) -> Int { (t - Board.startIndex(.yellow) + Board.trackLength) % Board.trackLength }

@Suite("Computer opponent: choices")
struct AIChoiceTests {
    @Test("Always a legal move when there is one, at every level, under every rule set",
          arguments: Difficulty.allCases)
    func alwaysLegal(level: Difficulty) throws {
        let ai = AIPlayer(difficulty: level)
        for seed in 0..<30 {
            var rng = SeededGenerator(seed: UInt64(seed))
            var g = GameState(players: Array(PlayerColor.allCases.prefix(2 + seed % 3)),
                              rules: [RuleSet.ghana, .classic, RuleSet(stacking: .notAllowed)][seed % 3])
            var n = 0
            while !g.isOver && n < 3000 {
                n += 1
                g.roll(Int.random(in: 1...6, using: &rng))
                let legal = g.legalMoves()
                let chosen = ai.chooseMove(g, using: &rng)
                if legal.isEmpty { try #require(chosen == nil) } else {
                    let move = try #require(chosen)
                    try #require(legal.contains(move))
                    try g.apply(move)
                }
            }
        }
    }

    @Test("Takes a kick when one is there (Intermediate and up)", arguments: [Difficulty.intermediate, .strategist, .grandmaster])
    func takesTheKick(level: Difficulty) {
        // Red 10 can kick yellow on 14 with a 4; red's other token at 30 could just walk on.
        let g = game([.red: [10, 30, -1, -1], .yellow: [yellow(14), -1, -1, -1]], roll: 4)
        var rng = SeededGenerator(seed: 1)
        #expect(AIPlayer(difficulty: level).chooseMove(g, using: &rng)?.token == 0)
    }

    @Test("Takes a back kick when it is the only kick (Intermediate and up)", arguments: [Difficulty.intermediate, .strategist, .grandmaster])
    func takesTheBackKick(level: Difficulty) {
        let g = game([.red: [12, 30, -1, -1], .yellow: [yellow(7), -1, -1, -1]], roll: 5)
        var rng = SeededGenerator(seed: 1)
        let move = AIPlayer(difficulty: level).chooseMove(g, using: &rng)
        #expect(move?.kind == .backKick)
    }

    @Test("Brings a token home when it can (Intermediate and up)", arguments: [Difficulty.intermediate, .strategist, .grandmaster])
    func goesHome(level: Difficulty) {
        let g = game([.red: [53, 20, -1, -1]], roll: 3)
        var rng = SeededGenerator(seed: 1)
        #expect(AIPlayer(difficulty: level).chooseMove(g, using: &rng)?.to == Board.home)
    }

    @Test("Does not stop just in front of an opponent when a safe move exists (Strategist and up)",
          arguments: [Difficulty.strategist, .grandmaster])
    func avoidsDanger(level: Difficulty) {
        // Yellow sits on track 20. Red token 0 at 18 with a 4 would land on 22: two squares ahead of
        // yellow, easy prey. Red token 1 at 40 with a 4 lands on 44, nobody near.
        // (Back kick off: otherwise red's token 2 behind yellow would already be in danger.)
        let g = game([.red: [18, 40, -1, -1], .yellow: [yellow(20), -1, -1, -1]], rules: RuleSet(backKick: false), roll: 4)
        var rng = SeededGenerator(seed: 1)
        #expect(AIPlayer(difficulty: level).chooseMove(g, using: &rng)?.token == 1)
    }

    @Test("Runs a token out of danger (Strategist and up)", arguments: [Difficulty.strategist, .grandmaster])
    func escapes(level: Difficulty) {
        // Red token 0 on 22 is 2 ahead of yellow on 20; token 1 at 40 is safe. A 5 takes token 0 to 27,
        // 7 clear of yellow: out of reach.
        let g = game([.red: [22, 40, -1, -1], .yellow: [yellow(20), -1, -1, -1]], rules: RuleSet(backKick: false), roll: 5)
        var rng = SeededGenerator(seed: 1)
        #expect(AIPlayer(difficulty: level).chooseMove(g, using: &rng)?.token == 0)
    }

    @Test("Takes a home kick into an opponent's lane (Intermediate and up)", arguments: [Difficulty.intermediate, .strategist, .grandmaster])
    func takesTheHomeKick(level: Difficulty) {
        // Red at 8 is 3 short of yellow's entrance; yellow waits 2 into its lane (52). A 5 kicks it.
        let g = game([.red: [8, 30, -1, -1], .yellow: [52, -1, -1, -1]], roll: 5)
        var rng = SeededGenerator(seed: 1)
        #expect(AIPlayer(difficulty: level).chooseMove(g, using: &rng)?.kind == .homeKick)
    }

    @Test("Takes the side-kick shortcut across its own lane (Intermediate and up)", arguments: [Difficulty.intermediate, .strategist, .grandmaster])
    func takesTheShortcut(level: Difficulty) {
        // Red 0 → 1 then across its own lane onto yellow at track 47: 46 squares nearer home.
        let g = game([.red: [0, 30, -1, -1], .yellow: [yellow(47), -1, -1, -1]], roll: 1)
        var rng = SeededGenerator(seed: 1)
        let move = AIPlayer(difficulty: level).chooseMove(g, using: &rng)
        #expect(move?.kind == .sideKickForward && move?.to == 47)
    }

    @Test("Same position and seed, same move")
    func deterministic() {
        let g = game([.red: [10, 20, 30, -1], .yellow: [yellow(14), yellow(33), -1, -1]], roll: 6)
        for level in Difficulty.allCases {
            var a = SeededGenerator(seed: 77), b = SeededGenerator(seed: 77)
            #expect(AIPlayer(difficulty: level).chooseMove(g, using: &a) == AIPlayer(difficulty: level).chooseMove(g, using: &b))
        }
    }
}

@Suite("Computer opponent: strength")
struct AIStrengthTests {
    /// Win rate of `a` against `b` over seeded two-player games, alternating who starts.
    static func winRate(_ a: AIPlayer, _ b: AIPlayer, games: Int, rules: RuleSet = .ghana) throws -> Double {
        var wins = 0
        for n in 0..<games {
            var rng = SeededGenerator(seed: 0x1D0 &+ UInt64(n) &* 7919)
            let aColor: PlayerColor = n % 2 == 0 ? .red : .black
            var g = GameState(players: [.red, .black], rules: rules, first: n % 4 < 2 ? .red : .black)
            var rolls = 0
            while !g.isOver && rolls < 5000 {
                rolls += 1
                g.roll(Int.random(in: 1...6, using: &rng))
                let ai = g.toMove == aColor ? a : b
                if let m = ai.chooseMove(g, using: &rng) { try g.apply(m) }
            }
            if g.winner == aColor { wins += 1 }
        }
        return Double(wins) / Double(games)
    }

    @Test("Each level beats the one below it more often than not, and Grandmaster beats Novice clearly")
    func ladder() throws {
        let levels = Difficulty.allCases.map { AIPlayer(difficulty: $0) }
        for i in 1..<levels.count {
            let rate = try Self.winRate(levels[i], levels[i - 1], games: 200)
            print("Ludo AI: \(levels[i].difficulty) vs \(levels[i - 1].difficulty): \(rate)")
            #expect(rate > 0.5, "\(levels[i].difficulty) should beat \(levels[i - 1].difficulty): \(rate)")
        }
        let top = try Self.winRate(levels.last!, levels.first!, games: 200)
        print("Ludo AI: grandmaster vs novice: \(top)")
        #expect(top >= 0.65)
    }
}
