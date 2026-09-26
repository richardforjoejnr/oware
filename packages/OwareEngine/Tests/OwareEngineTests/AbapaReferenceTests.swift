import Testing
@testable import OwareEngine

/// A second, deliberately plain implementation of Abapa written straight from the rules, kept
/// apart from the engine. Thousands of random games are played through both; every position,
/// capture and result must agree. If the engine ever drifts from the rules, this fails.
private struct ReferenceAbapa {
    var houses = Array(repeating: 4, count: 12)
    var stores = [0, 0]
    var toMove = 0                     // 0 = south (houses 0–5), 1 = north (6–11)
    var over = false
    var seen: [String: Int] = [:]

    init() { seen[key] = 1 }

    var key: String { houses.map(String.init).joined(separator: ",") + "|" + (toMove == 0 ? "A" : "B") }
    func side(_ p: Int) -> Range<Int> { p == 0 ? 0..<6 : 6..<12 }
    func seedsOn(_ p: Int) -> Int { side(p).reduce(0) { $0 + houses[$1] } }

    /// Sowing from `origin` drops a seed on the opponent's row when it has at least as many seeds
    /// as there are houses left before that row.
    func feeds(_ origin: Int) -> Bool { houses[origin] >= side(toMove).upperBound - origin }

    var legal: [Int] {
        guard !over else { return [] }
        let mine = side(toMove).filter { houses[$0] > 0 }
        if seedsOn(1 - toMove) == 0 {
            let feeding = mine.filter(feeds)
            if !feeding.isEmpty { return feeding }
        }
        return mine
    }

    mutating func sweep(_ p: Int) {
        for h in side(p) { stores[p] += houses[h]; houses[h] = 0 }
    }

    mutating func play(_ origin: Int) {
        let me = toMove, them = 1 - toMove
        // Feeding obligation: if the other row is empty and nothing can feed it, the mover keeps
        // their own seeds and the game ends.
        if seedsOn(them) == 0 && !feeds(origin) {
            sweep(me); over = true; return
        }
        // Sow anticlockwise, skipping the origin on every lap.
        var seeds = houses[origin]; houses[origin] = 0
        var i = origin
        while seeds > 0 {
            i = (i + 1) % 12
            if i == origin { continue }
            houses[i] += 1; seeds -= 1
        }
        // Capture backwards from the last house while on their row and holding 2 or 3.
        var taken: [Int] = []
        var w = i
        while side(them).contains(w) && (houses[w] == 2 || houses[w] == 3) { taken.append(w); w -= 1 }
        if !taken.isEmpty {
            let left = side(them).filter { !taken.contains($0) }.reduce(0) { $0 + houses[$1] }
            if left == 0 {
                // Grand slam: allowed, capture forfeited.
            } else {
                for h in taken { stores[me] += houses[h]; houses[h] = 0 }
            }
        }
        toMove = them
        if stores[me] >= 25 { over = true; return }
        if houses.reduce(0, +) == 0 { over = true; return }
        if legal.isEmpty {
            // Only reachable with feeding switched off; mirrors the engine: the last mover takes the rest.
            if seedsOn(toMove) == 0 { sweep(me) } else { sweep(0); sweep(1) }
            over = true; return
        }
        seen[key, default: 0] += 1
        if seen[key]! >= 3 { sweep(0); sweep(1); over = true }
    }
}

@Suite("Engine agrees with an independent Abapa reference")
struct AbapaReferenceTests {
    private struct LCG: RandomNumberGenerator {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
    }

    @Test("Two thousand random games: identical positions, stores and results", arguments: [1, 2, 3, 4])
    func randomGamesAgree(seed: UInt64) throws {
        var rng = LCG(s: seed)
        var games = 0, plies = 0, captures = 0, forfeits = 0
        while games < 500 {
            var engine = GameState.initial
            var reference = ReferenceAbapa()
            while !engine.isOver {
                let moves = engine.legalMoves()
                let refMoves = reference.legal.map { $0 - reference.side(reference.toMove).lowerBound }.sorted()
                #expect(moves.map(\.house).sorted() == refMoves, "legal moves differ at ply \(plies)\n\(engine)")
                guard let move = moves.randomElement(using: &rng) else { break }
                let events = try engine.apply(move)
                reference.play(move.absoluteIndex)
                captures += events.filter { if case .capture = $0 { return true } else { return false } }.count
                forfeits += events.filter { if case .grandSlamForfeited = $0 { return true } else { return false } }.count
                #expect(engine.houses == reference.houses, "houses differ after \(move) at ply \(plies)\n\(engine)")
                #expect(engine.stores == reference.stores, "stores differ after \(move) at ply \(plies)\n\(engine)")
                #expect(engine.isOver == reference.over, "game-over differs after \(move) at ply \(plies)\n\(engine)")
                plies += 1
            }
            #expect(engine.totalSeeds == 48)
            games += 1
        }
        // The random games must actually exercise the interesting rules.
        #expect(captures > 1_000)
        #expect(forfeits > 0)
    }

    @Test("Hand-checked position: A6 with one seed captures B1 holding 2")
    func handChecked() throws {
        var houses = Array(repeating: 0, count: 12)
        houses[5] = 1        // A6
        houses[6] = 2        // B1 → becomes 3, captured
        houses[7] = 4        // B2 keeps north alive
        houses[0] = 3
        var s = GameState(houses: houses)
        try s.apply(Move(player: .south, house: 5))
        #expect(s.stores[0] == 3)
        #expect(s.houses[6] == 0)
        #expect(s.houses[7] == 4)
        #expect(s.sideToMove == .north)
    }
}
