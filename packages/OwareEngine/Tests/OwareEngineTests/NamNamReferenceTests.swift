import Testing
@testable import OwareEngine

/// A second, deliberately plain Nam-Nam written from the rules and kept apart from the engine.
/// Thousands of random games (from the opening and from shifted territories) are played through
/// both; every position, store, owner, round and result must agree.
///
/// The rules, as the app plays them:
/// - Sow anticlockwise from a house you own, skipping the house you lifted from.
/// - If the last seed lands in a house that already held seeds, lift them all and keep sowing.
/// - Whenever a house reaches four it is captured at once: by its owner, except that the sower
///   takes a four made by their last seed on the other player's territory.
/// - When a capture leaves four seeds (on the board plus in hand), the capturer takes them too
///   and the round ends.
/// - If the other player has no seeds you must feed them when you can; you move again when they
///   are empty after your move. If nobody can be fed, the player to move keeps their side and the
///   round ends. A position seen three times ends the round with each side keeping its own.
/// - After a round each player owns one house per four seeds won, counted from A1; a spare house
///   goes to the player who won more seeds that round.
///   Round 2 starts with North, round 3 with South, and so on. Owning all twelve houses wins;
///   the round cap decides on houses.
struct ReferenceNamNam {
    var houses = Array(repeating: 4, count: 12)
    var stores = [0, 0]
    var owner = (0..<12).map { $0 < 6 ? 0 : 1 }
    var toMove = 0
    var round = 1
    var lastCapturer: Int?
    var history: [(south: Int, north: Int, southHouses: Int, northHouses: Int)] = []
    var result: (winner: Int?, reason: String)?
    var seen: [String: Int] = [:]
    let maxRounds: Int

    init(maxRounds: Int = 20) {
        self.maxRounds = maxRounds
        seen[key] = 1
    }

    init(houses: [Int], stores: [Int], southHouses: Int, toMove: Int, maxRounds: Int = 20) {
        self.maxRounds = maxRounds
        self.houses = houses
        self.stores = stores
        self.owner = (0..<12).map { $0 < southHouses ? 0 : 1 }
        self.toMove = toMove
        seen[key] = 1
    }

    var over: Bool { result != nil }
    var key: String { houses.map(String.init).joined(separator: ",") + "|" + (toMove == 0 ? "A" : "B") }
    func mine(_ p: Int) -> [Int] { (0..<12).filter { owner[$0] == p } }
    func seedsOf(_ p: Int) -> Int { mine(p).reduce(0) { $0 + houses[$1] } }

    struct Sown { var houses: [Int]; var stores: [Int]; var dropsOn: Set<Int>; var lastCapturer: Int?; var settled: Bool }

    func sow(from start: Int, by me: Int) -> Sown {
        var h = houses, st = stores
        var drops = Set<Int>()
        var capturer = lastCapturer
        var hand = h[start]; h[start] = 0
        var lapStart = start, pos = start
        var relays = 0
        var seenRelays = Set<[Int]>()
        while true {
            var capturedLast = false
            var landedOnSeeds = false
            while hand > 0 {
                pos = (pos + 1) % 12
                if pos == lapStart { continue }
                landedOnSeeds = h[pos] > 0
                h[pos] += 1; hand -= 1
                drops.insert(pos)
                capturedLast = false
                if h[pos] == 4 {
                    let taker = owner[pos] == me || hand == 0 ? me : owner[pos]
                    h[pos] = 0; st[taker] += 4; capturer = taker
                    capturedLast = true
                    let left = h.reduce(0, +) + hand
                    if left == 4 {
                        st[taker] += left
                        h = Array(repeating: 0, count: 12)
                        return Sown(houses: h, stores: st, dropsOn: drops, lastCapturer: taker, settled: true)
                    }
                }
            }
            // The engine stops a relay chain after 500 laps (it cannot happen in real play).
            // A relay that returns to a position already seen would loop for ever: the turn ends.
            if landedOnSeeds && !capturedLast && relays < GameState.maxRelayLaps && seenRelays.insert(h + [pos]).inserted {
                relays += 1
                hand = h[pos]; h[pos] = 0; lapStart = pos
            } else {
                return Sown(houses: h, stores: st, dropsOn: drops, lastCapturer: capturer, settled: false)
            }
        }
    }

    func feeds(_ house: Int, by p: Int) -> Bool {
        sow(from: house, by: p).dropsOn.contains { owner[$0] != p }
    }

    func legal(for p: Int) -> [Int] {
        guard !over else { return [] }
        let options = mine(p).filter { houses[$0] > 0 }
        if seedsOf(1 - p) == 0 {
            let feeding = options.filter { feeds($0, by: p) }
            if !feeding.isEmpty { return feeding }
        }
        return options
    }
    var legal: [Int] { legal(for: toMove) }

    mutating func keepOwn(_ p: Int) {
        for h in mine(p) { stores[p] += houses[h]; houses[h] = 0 }
    }

    mutating func play(_ house: Int) {
        let me = toMove, them = 1 - toMove
        if seedsOf(them) == 0 && !feeds(house, by: me) {
            keepOwn(me); settleRound(); return
        }
        let s = sow(from: house, by: me)
        houses = s.houses; stores = s.stores; lastCapturer = s.lastCapturer
        if houses.reduce(0, +) == 0 { settleRound(); return }
        toMove = seedsOf(them) == 0 ? me : them
        let options = legal
        if options.isEmpty || (seedsOf(them) == 0 && !options.contains { feeds($0, by: toMove) }) {
            keepOwn(toMove); settleRound(); return
        }
        seen[key, default: 0] += 1
        if seen[key]! >= 3 { keepOwn(0); keepOwn(1); settleRound() }
    }

    mutating func agree() {
        guard !over else { return }
        keepOwn(0); keepOwn(1); settleRound()
    }

    mutating func settleRound() {
        let s = stores[0], n = stores[1]
        var sh = s / 4, nh = n / 4
        if sh + nh == 11 {
            precondition(s != n, "a spare house needs uneven remainders, so the totals differ")
            if s > n { sh += 1 } else { nh += 1 }
        }
        history.append((s, n, sh, nh))
        if sh == 12 || nh == 12 { result = (sh == 12 ? 0 : 1, "territory"); return }
        if round >= maxRounds { result = (sh == nh ? nil : (sh > nh ? 0 : 1), "roundLimit"); return }
        owner = (0..<12).map { $0 < sh ? 0 : 1 }
        houses = Array(repeating: 4, count: 12)
        stores = [0, 0]
        round += 1
        lastCapturer = nil
        toMove = round % 2 == 1 ? 0 : 1
        seen = [key: 1]
    }
}

@Suite("Engine agrees with an independent Nam-Nam reference")
struct NamNamReferenceTests {
    private struct LCG: RandomNumberGenerator {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
    }

    private func expectSame(_ engine: GameState, _ ref: ReferenceNamNam, _ context: @autoclosure () -> String) {
        #expect(engine.houses == ref.houses, "houses differ \(context())\n\(engine)")
        #expect(engine.stores == ref.stores, "stores differ \(context())\n\(engine)")
        #expect(engine.territory.map(\.rawValue) == ref.owner, "territory differs \(context())\n\(engine)")
        #expect(engine.round == ref.round, "round differs \(context())")
        #expect(engine.isOver == ref.over, "game-over differs \(context())\n\(engine)")
        if !engine.isOver { #expect(engine.sideToMove.rawValue == ref.toMove, "side to move differs \(context())\n\(engine)") }
        #expect(engine.roundHistory.count == ref.history.count, "round count differs \(context())")
        if let a = engine.roundHistory.last, let b = ref.history.last {
            #expect([a.southSeeds, a.northSeeds, a.southHouses, a.northHouses] == [b.south, b.north, b.southHouses, b.northHouses],
                    "round result differs \(context())")
        }
        if let outcome = engine.outcome, let r = ref.result {
            #expect(outcome.winner?.rawValue == r.winner, "winner differs \(context())")
            #expect(outcome.reason.rawValue == r.reason, "end reason differs \(context())")
        }
    }

    /// Plays one game through both, move for move. Returns plies played.
    @discardableResult
    private func playBoth(_ engine: inout GameState, _ ref: inout ReferenceNamNam, rng: inout LCG, label: String) throws -> Int {
        var plies = 0
        while !engine.isOver && plies < 5_000 {
            let moves = engine.legalMoves()
            #expect(moves.map(\.absoluteIndex).sorted() == ref.legal.sorted(), "legal moves differ \(label) ply \(plies)\n\(engine)")
            guard let move = moves.randomElement(using: &rng) else { break }
            try engine.apply(move)
            ref.play(move.absoluteIndex)
            expectSame(engine, ref, "\(label) after \(move) at ply \(plies)")
            #expect(engine.totalSeeds == 48 || engine.isOver && engine.totalSeeds == 48)
            plies += 1
        }
        #expect(engine.isOver, "\(label) did not finish")
        return plies
    }

    @Test("Random games from the opening: identical positions, stores, territory and results", arguments: [21, 22, 23, 24])
    func randomGamesAgree(seed: UInt64) throws {
        var rng = LCG(s: seed)
        var rounds = 0, plies = 0
        for game in 0..<60 {
            var engine = GameState.initial(rules: .namNam)
            var ref = ReferenceNamNam()
            plies += try playBoth(&engine, &ref, rng: &rng, label: "seed \(seed) game \(game)")
            rounds += engine.roundHistory.count
        }
        #expect(rounds > 60, "games should run several rounds")
        #expect(plies > 1_000)
    }

    @Test("Random mid-game positions with shifted territory agree too", arguments: [31, 32, 33])
    func shiftedTerritoryAgrees(seed: UInt64) throws {
        var rng = LCG(s: seed)
        for game in 0..<150 {
            let southHouses = Int.random(in: 1...11, using: &rng)
            // Scatter 48 seeds: some already won (in fours), the rest on the board.
            let won = Int.random(in: 0...6, using: &rng) * 4
            var houses = Array(repeating: 0, count: 12)
            for _ in 0..<(48 - won) { houses[Int.random(in: 0..<12, using: &rng)] += 1 }
            let southWon = Int.random(in: 0...(won / 4), using: &rng) * 4
            let stores = [southWon, won - southWon]
            let toMove = Int.random(in: 0...1, using: &rng)
            let territory: [Player] = (0..<12).map { $0 < southHouses ? .south : .north }
            var engine = GameState(houses: houses, stores: stores, sideToMove: toMove == 0 ? .south : .north,
                                   rules: .namNam, territory: territory)
            var ref = ReferenceNamNam(houses: houses, stores: stores, southHouses: southHouses, toMove: toMove)
            // A random scatter can leave the side to move with nothing to sow; skip those.
            guard !engine.legalMoves().isEmpty else { continue }
            try playBoth(&engine, &ref, rng: &rng, label: "seed \(seed) start \(game)")
        }
    }

    @Test("A short round cap ends games on houses in both implementations", arguments: [41, 42])
    func roundCapAgrees(seed: UInt64) throws {
        var rng = LCG(s: seed)
        for game in 0..<40 {
            var engine = GameState.initial(rules: RuleSet(variant: .namNam, maxRounds: 2))
            var ref = ReferenceNamNam(maxRounds: 2)
            try playBoth(&engine, &ref, rng: &rng, label: "cap game \(game)")
            #expect(engine.round <= 2)
        }
    }

    @Test("Agreeing to stop settles the round the same way")
    func agreementAgrees() throws {
        var rng = LCG(s: 51)
        for game in 0..<100 {
            var engine = GameState.initial(rules: .namNam)
            var ref = ReferenceNamNam()
            let stopAt = Int.random(in: 1...40, using: &rng)
            var plies = 0
            while !engine.isOver && plies < stopAt {
                guard let move = engine.legalMoves().randomElement(using: &rng) else { break }
                try engine.apply(move); ref.play(move.absoluteIndex); plies += 1
            }
            _ = engine.endByAgreement(); ref.agree()
            expectSame(engine, ref, "agreement in game \(game)")
        }
    }
}
