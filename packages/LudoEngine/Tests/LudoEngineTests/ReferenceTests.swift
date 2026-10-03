import Foundation
import Testing
@testable import LudoEngine

/// A second, independent Ludo: written from the rules, not from the engine. Tokens live on board
/// squares (named by grid cell); moves are found by walking square by square and looking at who is
/// standing there. The engine must agree with it on every legal move and every resulting position.
private struct ReferenceLudo {
    enum Spot: Hashable { case yard, square(Board.Cell), home }
    struct Token: Hashable { var spot: Spot; var steps: Int }   // steps taken since entering (0 at start)

    let rules: RuleSet
    let players: [PlayerColor]
    var tokens: [PlayerColor: [Token]]
    var toMove: PlayerColor
    var roll: Int?
    var sixes = 0
    var winner: PlayerColor?
    var saved: [PlayerColor: [Token]]

    init(players: [PlayerColor], rules: RuleSet) {
        self.rules = rules
        self.players = players
        tokens = Dictionary(uniqueKeysWithValues: PlayerColor.allCases.map { ($0, Array(repeating: Token(spot: .yard, steps: -1), count: 4)) })
        toMove = players[0]
        saved = tokens
    }

    /// The route a colour's token follows: 51 track squares from its start, then its lane.
    static func route(_ c: PlayerColor) -> [Board.Cell] {
        let start = Board.track.firstIndex(of: [Board.Cell(1, 6), Board.Cell(8, 1), Board.Cell(13, 8), Board.Cell(6, 13)][c.rawValue])!
        return (0..<51).map { Board.track[(start + $0) % 52] } + Board.lane(c)
    }
    static let starts: Set<Board.Cell> = [Board.Cell(1, 6), Board.Cell(8, 1), Board.Cell(13, 8), Board.Cell(6, 13)]
    static let stars: Set<Board.Cell> = Set([0, 13, 26, 39].map { Board.track[($0 + 8) % 52] })

    func who(on cell: Board.Cell) -> [(PlayerColor, Int)] {
        players.flatMap { c in tokens[c]!.enumerated().compactMap { $0.element.spot == .square(cell) ? (c, $0.offset) : nil } }
    }
    func onTrack(_ cell: Board.Cell) -> Bool { Board.track.contains(cell) }
    func safe(_ cell: Board.Cell) -> Bool {
        (rules.startSquaresSafe && Self.starts.contains(cell)) || (rules.starSquaresSafe && Self.stars.contains(cell))
    }
    /// A colour other than `me` with two or more tokens here.
    func enemyPair(_ cell: Board.Cell, _ me: PlayerColor) -> Bool {
        var count: [PlayerColor: Int] = [:]
        for (c, _) in who(on: cell) where c != me { count[c, default: 0] += 1 }
        return count.values.contains { $0 >= 2 }
    }
    func mayEndOn(_ cell: Board.Cell, _ me: PlayerColor) -> Bool {
        if rules.stacking == .notAllowed { return !who(on: cell).contains { $0.0 == me } }
        if onTrack(cell) && enemyPair(cell, me) { return false }
        return true
    }
    func victims(_ cell: Board.Cell, _ me: PlayerColor) -> [(PlayerColor, Int)] {
        guard onTrack(cell), !safe(cell) else { return [] }
        if rules.stacking != .notAllowed && enemyPair(cell, me) { return [] }
        return who(on: cell).filter { $0.0 != me }
    }

    /// (token, steps after) for every legal move, as the engine's progress numbers.
    func moves() -> Set<[Int]> {
        guard let r = roll, winner == nil else { return [] }
        let me = toMove, route = Self.route(me)
        var out: Set<[Int]> = []
        for (i, t) in tokens[me]!.enumerated() {
            switch t.spot {
            case .home: continue
            case .yard:
                if rules.entryRolls.contains(r) && mayEndOn(route[0], me) { out.insert([i, -1, 0]) }
            case .square:
                let target = t.steps + r
                if target <= 56 {
                    var blocked = false
                    if rules.stacking == .wall {
                        for s in (t.steps + 1)..<target where s <= 50 && enemyPair(route[s], me) { blocked = true }
                    }
                    let ok = target == 56 || mayEndOn(route[target], me)
                    if !blocked && ok { out.insert([i, t.steps, target]) }
                }
                if rules.backKick && t.steps <= 50 && r <= t.steps {
                    let back = t.steps - r
                    var blocked = false
                    if rules.stacking == .wall {
                        for s in (back + 1)..<t.steps where enemyPair(route[s], me) { blocked = true }
                    }
                    if !blocked && !victims(route[back], me).isEmpty { out.insert([i, t.steps, back]) }
                }
            }
        }
        return out
    }

    mutating func doRoll(_ v: Int) {
        sixes = v == 6 ? sixes + 1 : 0
        if rules.threeSixesForfeit && sixes == 3 { tokens = saved; next(); return }
        roll = v
        if moves().isEmpty { roll = nil; if v != 6 { next() } }
    }

    mutating func play(token i: Int, to target: Int) {
        let me = toMove, r = roll!, route = Self.route(me)
        var earned = false
        if target == 56 {
            tokens[me]![i] = Token(spot: .home, steps: 56); earned = true
        } else {
            let cell = route[target]
            for (c, j) in victims(cell, me) { tokens[c]![j] = Token(spot: .yard, steps: -1); earned = true }
            tokens[me]![i] = Token(spot: .square(cell), steps: target)
        }
        roll = nil
        if tokens[me]!.allSatisfy({ $0.spot == .home }) { winner = me; return }
        if !(r == 6 || (rules.kickOrHomeEarnsRoll && earned)) { next() }
    }

    mutating func next() {
        toMove = players[(players.firstIndex(of: toMove)! + 1) % players.count]
        sixes = 0; roll = nil; saved = tokens
    }

    func progress(_ c: PlayerColor) -> [Int] { tokens[c]!.map(\.steps) }
}

@Suite("Engine agrees with an independent reference")
struct ReferenceTests {
    struct LCG: RandomNumberGenerator {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
    }

    static let ruleSets: [RuleSet] = [
        .ghana, .classic,
        RuleSet(stacking: .notAllowed), RuleSet(stacking: .safe),
        RuleSet(startSquaresSafe: true, starSquaresSafe: true),
        RuleSet(stacking: .notAllowed, backKick: true, startSquaresSafe: true, entryRolls: [1, 6]),
        RuleSet(kickOrHomeEarnsRoll: false, threeSixesForfeit: true, stacking: .safe, backKick: false, starSquaresSafe: true),
    ]

    @Test("Random games: the same legal moves, positions, turns and winner, roll by roll", arguments: ruleSets)
    func sameGames(rules: RuleSet) throws {
        for seed in 0..<80 {
            var rng = LCG(s: UInt64(seed) &* 2654435761 &+ 7)
            let players = Array(PlayerColor.allCases.prefix(2 + seed % 3))
            var engine = GameState(players: players, rules: rules)
            var ref = ReferenceLudo(players: players, rules: rules)
            var rolls = 0
            while !engine.isOver && rolls < 20_000 {
                let v = Int.random(in: 1...6, using: &rng)
                engine.roll(v); ref.doRoll(v); rolls += 1
                let legal = Set(engine.legalMoves().map { [$0.token, $0.from, $0.to] })
                try #require(legal == ref.moves(), "seed \(seed) roll \(rolls): engine \(legal) vs reference \(ref.moves())")
                if let pick = engine.legalMoves().randomElement(using: &rng) {
                    try engine.apply(pick); ref.play(token: pick.token, to: pick.to)
                }
                for c in PlayerColor.allCases {
                    try #require(engine.tokens(of: c) == ref.progress(c), "seed \(seed) roll \(rolls) \(c)")
                }
                try #require(engine.toMove == ref.toMove && engine.winner == ref.winner, "seed \(seed) roll \(rolls)")
            }
            #expect(engine.winner != nil)
        }
    }
}
