import Foundation
import Testing
@testable import LudoEngine

/// A second, independent Ludo: written from the rules, not from the engine. Tokens live on board
/// squares (named by grid cell); moves are found by walking square by square and looking at who is
/// standing there. The engine must agree with it on every legal move and every resulting position.
private struct ReferenceLudo {
    enum Spot: Hashable { case yard, square(Board.Cell), home }
    struct Token: Hashable {
        var spot: Spot
        var steps: Int                       // steps taken since entering (0 at start)
        var guest: PlayerColor? = nil         // whose lane it stands in after a home kick
    }

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
        if enemyPair(cell, me) { return false }
        return true
    }
    func victims(_ cell: Board.Cell, _ me: PlayerColor) -> [(PlayerColor, Int)] {
        guard !safe(cell) else { return [] }   // lane squares are never safe squares
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
                if rules.entryRolls.contains(r) && mayEndOn(route[0], me) { out.insert([i, -1, 0, -1, 0, 0]) }
            case .square(let here) where t.guest != nil:
                // A guest walks back down the lane it kicked its way into, then on along its route.
                let lane = Board.lane(t.guest!), depth = lane.firstIndex(of: here)! + 1
                if r < depth {
                    if mayEndOn(lane[depth - r - 1], me) { out.insert([i, t.steps, t.steps, t.guest!.rawValue, depth - r, 4]) }
                } else {
                    let target = t.steps + (r - depth)
                    var blocked = false
                    if rules.stacking == .wall {
                        for s in t.steps..<target where s <= 50 && enemyPair(route[s], me) { blocked = true }
                    }
                    if target <= 56 && !blocked && (target == 56 || mayEndOn(route[target], me)) { out.insert([i, t.steps, target, -1, 0, 4]) }
                }
            case .square:
                if rules.homeKick && t.steps <= 50 {
                    for other in players where other != me {
                        // The square from which `other` turns into its lane, if still ahead on our route.
                        guard let e = route[0...50].firstIndex(of: Self.route(other)[50]), e >= t.steps else { continue }
                        let depth = r - (e - t.steps)
                        guard (1...5).contains(depth) else { continue }
                        var blocked = false
                        if rules.stacking == .wall && e > t.steps {
                            for s in (t.steps + 1)...e where enemyPair(route[s], me) { blocked = true }
                        }
                        if !blocked && !victims(Board.lane(other)[depth - 1], me).isEmpty {
                            out.insert([i, t.steps, e, other.rawValue, depth, 3])
                        }
                    }
                }
                let target = t.steps + r
                if target <= 56 {
                    var blocked = false
                    if rules.stacking == .wall {
                        for s in (t.steps + 1)..<target where s <= 50 && enemyPair(route[s], me) { blocked = true }
                    }
                    let ok = target == 56 || mayEndOn(route[target], me)
                    if !blocked && ok { out.insert([i, t.steps, target, -1, 0, 1]) }
                }
                if rules.backKick && t.steps <= 50 && r <= t.steps {
                    let back = t.steps - r
                    var blocked = false
                    if rules.stacking == .wall {
                        for s in (back + 1)..<t.steps where enemyPair(route[s], me) { blocked = true }
                    }
                    if !blocked && !victims(route[back], me).isEmpty { out.insert([i, t.steps, back, -1, 0, 2]) }
                }
                // Side kicks: stop by the roll (forwards or backwards), then two squares straight across
                // a lane square (any colour's, our own included), onto a lone opponent; it must be empty.
                // Only from the track: a token in its own home lane never steps back out of it.
                var stops: [(Int, Int)] = []
                if rules.forwardSideKick && t.steps <= 50 && t.steps + r <= 50 {
                    var blocked = false
                    if rules.stacking == .wall { for s in (t.steps + 1)..<(t.steps + r) where enemyPair(route[s], me) { blocked = true } }
                    if !blocked && mayEndOn(route[t.steps + r], me) { stops.append((t.steps + r, 5)) }
                }
                if rules.backSideKick && t.steps <= 50 && r <= t.steps {
                    var blocked = false
                    if rules.stacking == .wall { for s in (t.steps - r + 1)..<t.steps where enemyPair(route[s], me) { blocked = true } }
                    if !blocked && mayEndOn(route[t.steps - r], me) { stops.append((t.steps - r, 6)) }
                }
                for (stop, code) in stops {
                    let at = route[stop]
                    for (dc, dr) in [(0, 2), (0, -2), (2, 0), (-2, 0)] {
                        let mid = Board.Cell(at.column + dc / 2, at.row + dr / 2), far = Board.Cell(at.column + dc, at.row + dr)
                        guard PlayerColor.allCases.contains(where: { Board.lane($0).contains(mid) }),
                              onTrack(far), who(on: mid).isEmpty, mayEndOn(far, me), !victims(far, me).isEmpty,
                              let to = route[0...50].firstIndex(of: far) else { continue }
                        out.insert([i, t.steps, to, -1, 0, code])
                    }
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

    mutating func play(token i: Int, to target: Int, guestOf owner: PlayerColor? = nil, depth: Int = 0) {
        let me = toMove, r = roll!, route = Self.route(me)
        var earned = false
        if target == 56 {
            tokens[me]![i] = Token(spot: .home, steps: 56); earned = true
        } else if let owner {
            let cell = Board.lane(owner)[depth - 1]
            for (c, j) in victims(cell, me) { tokens[c]![j] = Token(spot: .yard, steps: -1); earned = true }
            tokens[me]![i] = Token(spot: .square(cell), steps: target, guest: owner)
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
    func guests(_ c: PlayerColor) -> [Int] {
        tokens[c]!.map { t in
            guard let g = t.guest, case let .square(cell) = t.spot else { return 0 }
            return g.rawValue * 10 + Board.lane(g).firstIndex(of: cell)! + 1
        }
    }
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
        RuleSet(homeKick: true),
        RuleSet(stacking: .notAllowed, homeKick: true),
        RuleSet(kickOrHomeEarnsRoll: false, stacking: .safe, backKick: false, startSquaresSafe: true, homeKick: true),
        RuleSet(forwardSideKick: true, backSideKick: true),
        RuleSet(homeKick: true, forwardSideKick: true, backSideKick: true),
        RuleSet(stacking: .notAllowed, backKick: false, starSquaresSafe: true, homeKick: true, forwardSideKick: true, backSideKick: false),
    ]

    @Test("Random games: the same legal moves, positions, turns and winner, roll by roll", arguments: ruleSets)
    func sameGames(rules: RuleSet) throws {
        var played: [Move.Kind: Int] = [:]
        for seed in 0..<80 {
            var rng = LCG(s: UInt64(seed) &* 2654435761 &+ 7)
            let players = Array(PlayerColor.allCases.prefix(2 + seed % 3))
            var engine = GameState(players: players, rules: rules)
            var ref = ReferenceLudo(players: players, rules: rules)
            var rolls = 0
            while !engine.isOver && rolls < 20_000 {
                let v = Int.random(in: 1...6, using: &rng)
                engine.roll(v); ref.doRoll(v); rolls += 1
                let kinds: [Move.Kind: Int] = [.enter: 0, .forward: 1, .backKick: 2, .homeKick: 3, .walkOut: 4, .sideKickForward: 5, .sideKickBack: 6]
                let legal = Set(engine.legalMoves().map { [$0.token, $0.from, $0.to, $0.visit?.owner.rawValue ?? -1, $0.visit?.depth ?? 0, kinds[$0.kind]!] })
                try #require(legal == ref.moves(), "seed \(seed) roll \(rolls): engine \(legal) vs reference \(ref.moves())")
                if let pick = engine.legalMoves().randomElement(using: &rng) {
                    played[pick.kind, default: 0] += 1
                    try engine.apply(pick); ref.play(token: pick.token, to: pick.to, guestOf: pick.visit?.owner, depth: pick.visit?.depth ?? 0)
                }
                for c in PlayerColor.allCases {
                    try #require(engine.tokens(of: c) == ref.progress(c), "seed \(seed) roll \(rolls) \(c)")
                    let engineGuests = (0..<4).map { i in engine.visit(of: c, token: i).map { $0.owner.rawValue * 10 + $0.depth } ?? 0 }
                    try #require(engineGuests == ref.guests(c), "seed \(seed) roll \(rolls) \(c) visits")
                }
                try #require(engine.toMove == ref.toMove && engine.winner == ref.winner, "seed \(seed) roll \(rolls)")
            }
            #expect(engine.winner != nil)
        }
        // The comparison only proves something if the rules it covers actually happened.
        if rules.homeKick {
            #expect(played[.homeKick, default: 0] > 0 && played[.walkOut, default: 0] > 0, "home kicks played: \(played)")
        }
        if rules.backKick { #expect(played[.backKick, default: 0] > 0, "\(played)") }
        if rules.forwardSideKick { #expect(played[.sideKickForward, default: 0] > 0, "side kicks played: \(played)") }
        if rules.backSideKick { #expect(played[.sideKickBack, default: 0] > 0, "\(played)") }
    }

    /// Back kicks above all: when one is offered it is played (half the time; always kicking makes a
    /// game last for ever), so the comparison sees hundreds of them in every rule set that has them (stacking modes, safe squares, the other kicks on and off).
    static let backKickRuleSets: [RuleSet] = [
        .ghana,
        RuleSet(stacking: .safe), RuleSet(stacking: .notAllowed),
        RuleSet(startSquaresSafe: true, starSquaresSafe: true),
        RuleSet(kickOrHomeEarnsRoll: false, threeSixesForfeit: false),
        RuleSet(homeKick: false, forwardSideKick: false, backSideKick: false),
    ]

    @Test("Back-kick-heavy random games: engine and reference agree on every move", arguments: backKickRuleSets)
    func backKickHeavyGames(rules: RuleSet) throws {
        var backKicks = 0
        let kinds: [Move.Kind: Int] = [.enter: 0, .forward: 1, .backKick: 2, .homeKick: 3, .walkOut: 4, .sideKickForward: 5, .sideKickBack: 6]
        for seed in 0..<30 {
            var rng = LCG(s: UInt64(seed) &* 40503 &+ 11)
            let players = Array(PlayerColor.allCases.prefix(2 + seed % 3))
            var engine = GameState(players: players, rules: rules)
            var ref = ReferenceLudo(players: players, rules: rules)
            var rolls = 0
            while !engine.isOver && rolls < 20_000 {
                let v = Int.random(in: 1...6, using: &rng)
                engine.roll(v); ref.doRoll(v); rolls += 1
                let moves = engine.legalMoves()
                let legal = Set(moves.map { [$0.token, $0.from, $0.to, $0.visit?.owner.rawValue ?? -1, $0.visit?.depth ?? 0, kinds[$0.kind]!] })
                try #require(legal == ref.moves(), "seed \(seed) roll \(rolls): engine \(legal) vs reference \(ref.moves())")
                let kick = Bool.random(using: &rng) ? moves.first(where: { $0.kind == .backKick }) : nil
                if let pick = kick ?? moves.randomElement(using: &rng) {
                    if pick.kind == .backKick { backKicks += 1 }
                    try engine.apply(pick); ref.play(token: pick.token, to: pick.to, guestOf: pick.visit?.owner, depth: pick.visit?.depth ?? 0)
                }
                for c in PlayerColor.allCases {
                    try #require(engine.tokens(of: c) == ref.progress(c), "seed \(seed) roll \(rolls) \(c)")
                }
                try #require(engine.toMove == ref.toMove && engine.winner == ref.winner, "seed \(seed) roll \(rolls)")
            }
            #expect(engine.winner != nil)
        }
        #expect(backKicks > 150, "back kicks played: \(backKicks)")
    }
}
