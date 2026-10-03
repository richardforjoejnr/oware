import Foundation
import Testing
@testable import LudoEngine

/// Properties that must hold after every roll and move of every random game, under every rule set.
@Suite("Rule invariants")
struct InvariantTests {
    struct LCG: RandomNumberGenerator {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
    }

    static let ruleSets = ReferenceTestsRuleSets.all

    /// Plays seeded random games, calling `check` with the state before, the events and the state after.
    static func play(_ rules: RuleSet, games: Int = 50, check: (GameState, [GameEvent], GameState, Move?) throws -> Void) throws {
        for seed in 0..<games {
            var rng = LCG(s: UInt64(seed) &* 40503 &+ 11)
            var g = GameState(players: Array(PlayerColor.allCases.prefix(2 + seed % 3)), rules: rules)
            var n = 0
            while !g.isOver && n < 20_000 {
                n += 1
                var before = g
                let rolled = g.roll(Int.random(in: 1...6, using: &rng))
                try check(before, rolled, g, nil)
                if let m = g.legalMoves().randomElement(using: &rng) {
                    before = g
                    let events = try g.apply(m)
                    try check(before, events, g, m)
                }
            }
        }
    }

    @Test("Every token stays on the board, -1…56, four per colour; non-players never move", arguments: ruleSets)
    func tokensInRange(rules: RuleSet) throws {
        try Self.play(rules) { _, _, after, _ in
            for c in PlayerColor.allCases {
                let t = after.tokens(of: c)
                try #require(t.count == 4 && t.allSatisfy { (Board.yard...Board.home).contains($0) })
                if !after.players.contains(c) { try #require(t.allSatisfy { $0 == Board.yard }) }
            }
        }
    }

    @Test("Visitors stand only in other players' lanes, at those lanes' entrances on their own journey", arguments: ruleSets.filter(\.homeKick))
    func visitors(rules: RuleSet) throws {
        try Self.play(rules) { _, _, after, _ in
            for c in after.players {
                for i in 0..<4 {
                    guard let v = after.visit(of: c, token: i) else { continue }
                    try #require(v.owner != c && after.players.contains(v.owner) && (1...5).contains(v.depth))
                    try #require(after.tokens(of: c)[i] == GameState.progress(of: c, atTrackIndex: Board.entranceIndex(v.owner)))
                    try #require(!after.occupants(at: Board.entranceIndex(v.owner)).contains { $0.color == c && $0.token == i },
                                 "a visitor is in the lane, not on the track")
                }
            }
        }
    }

    @Test("No two colours ever share an unsafe track square", arguments: ruleSets)
    func noSharedSquares(rules: RuleSet) throws {
        try Self.play(rules) { _, _, after, _ in
            for i in 0..<Board.trackLength where !after.isSafe(i) {
                try #require(Set(after.occupants(at: i).map(\.color)).count <= 1, "square \(i)")
            }
        }
    }

    @Test("One token per square really means one: never two of a colour together")
    func oneTokenPerSquare() throws {
        try Self.play(RuleSet(stacking: .notAllowed)) { _, _, after, _ in
            for c in after.players {
                let spots = after.tokens(of: c).filter { $0 >= 0 && $0 < Board.home }
                try #require(Set(spots).count == spots.count, "\(c): \(spots)")
            }
        }
    }

    @Test("A move does what it says: the token goes to `to`, and every kicked token goes home to its yard", arguments: ruleSets)
    func eventsAccount(rules: RuleSet) throws {
        try Self.play(rules) { before, events, after, move in
            guard let move else { return }
            let me = before.toMove
            try #require(after.tokens(of: me)[move.token] == move.to)
            for case let .kicked(c, token, at, by) in events {
                try #require(by == me && c != me)
                try #require(after.tokens(of: c)[token] == Board.yard)
                let was = before.tokens(of: c)[token]
                try #require(was >= 0 && was <= Board.lastTrackProgress && Board.trackIndex(c, progress: was) == at)
            }
            for case let .kickedInLane(c, token, lane, depth, by) in events {
                try #require(by == me && c != me && after.tokens(of: c)[token] == Board.yard && after.visit(of: c, token: token) == nil)
                try #require(before.laneOccupants(lane, depth: depth).contains { $0.color == c && $0.token == token })
            }
            // Nothing else changed.
            for c in PlayerColor.allCases where c != me {
                let kicked = Set(events.compactMap { e -> Int? in
                    if case let .kicked(k, t, _, _) = e, k == c { return t }
                    if case let .kickedInLane(k, t, _, _, _) = e, k == c { return t }
                    return nil
                })
                for i in 0..<4 where !kicked.contains(i) { try #require(after.tokens(of: c)[i] == before.tokens(of: c)[i]) }
            }
            for i in 0..<4 where i != move.token { try #require(after.tokens(of: me)[i] == before.tokens(of: me)[i]) }
        }
    }

    @Test("Turns pass clockwise; a 6 or an earned roll keeps the turn", arguments: ruleSets)
    func turnOrder(rules: RuleSet) throws {
        try Self.play(rules) { before, events, after, _ in
            guard !after.isOver else { return }
            let mover = before.toMove
            if events.contains(where: { if case .rollAgain = $0 { true } else { false } }) {
                try #require(after.toMove == mover)
            } else if events.contains(where: { if case .turn = $0 { true } else { false } }) {
                let i = after.players.firstIndex(of: mover)!
                try #require(after.toMove == after.players[(i + 1) % after.players.count])
            } else {
                try #require(after.toMove == mover && after.pendingRoll != nil, "a roll waiting to be played")
            }
        }
    }

    @Test("A wall is never passed or landed on by an opponent")
    func wallsHold() throws {
        try Self.play(.ghana) { before, _, _, move in
            guard let move, move.kind == .forward else { return }
            let me = before.toMove
            let first = max(move.from, 0) + 1, last = min(move.to, Board.lastTrackProgress)
            guard first <= last else { return }
            for p in first...last {
                let square = Board.trackIndex(me, progress: p)
                let others = before.occupants(at: square).filter { $0.color != me }
                let pair = Dictionary(grouping: others, by: \.color).values.contains { $0.count >= 2 }
                try #require(!pair, "passed or landed on a wall at \(square)")
            }
        }
    }

    @Test("With the rule on, three sixes never change the board", arguments: ruleSets.filter(\.threeSixesForfeit))
    func threeSixesUndo(rules: RuleSet) throws {
        // Script: a third 6 must leave the board as the turn found it.
        var g = GameState(players: [.red, .yellow], rules: rules)
        g.roll(6); if let m = g.legalMoves().first { try g.apply(m) }
        g.roll(6); if let m = g.legalMoves().first { try g.apply(m) }
        #expect(g.tokens(of: .red).contains { $0 != Board.yard }, "two sixes have moved something")
        g.roll(6)
        #expect(g.toMove == .yellow)
        #expect(g.tokens(of: .red).allSatisfy { $0 == Board.yard }, "every move of the turn undone")
    }

    @Test("The same rolls and choices always give the same game", arguments: ruleSets)
    func deterministic(rules: RuleSet) throws {
        func run() throws -> GameState {
            var rng = LCG(s: 4242)
            var g = GameState(players: PlayerColor.allCases, rules: rules)
            for _ in 0..<600 where !g.isOver {
                g.roll(Int.random(in: 1...6, using: &rng))
                if let m = g.legalMoves().randomElement(using: &rng) { try g.apply(m) }
            }
            return g
        }
        #expect(try run() == run())
    }

    @Test("A game saved at any point resumes exactly", arguments: ruleSets)
    func savesResume(rules: RuleSet) throws {
        var n = 0
        try Self.play(rules, games: 10) { _, _, after, _ in
            n += 1
            guard n % 7 == 0 else { return }
            let back = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(after))
            try #require(back == after)
            try #require(back.legalMoves() == after.legalMoves())
        }
    }
}

/// The rule sets the reference and invariant tests share.
enum ReferenceTestsRuleSets {
    static let all = ReferenceTests.ruleSets
}

@Suite("Damaged saves")
struct CorruptSaveTests {
    #if canImport(Darwin)
    static let appleFoundation = true
    #else
    static let appleFoundation = false
    #endif

    func json(_ g: GameState) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(g)) as! [String: Any]
    }
    func decodes(_ object: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return false }
        return (try? JSONDecoder().decode(GameState.self, from: data)) != nil
    }

    @Test("A good save loads")
    func good() throws {
        var g = GameState(players: [.red, .yellow, .black])
        g.roll(6)
        #expect(decodes(try json(g)))
    }

    @Test("Damaged saves are refused, not loaded")
    func damaged() throws {
        let good = try json(GameState(players: [.red, .yellow]))
        var cases: [(String, [String: Any])] = []
        func with(_ key: String, _ value: Any) -> [String: Any] { var d = good; d[key] = value; return d }
        cases.append(("token off the board", with("progress", [[57, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]])))
        cases.append(("three tokens", with("progress", [[-1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]])))
        cases.append(("one player", with("players", [0])))
        cases.append(("same colour twice", with("players", [0, 0])))
        cases.append(("not clockwise", with("players", [1, 0])))
        cases.append(("mover not playing", with("toMove", 3)))
        cases.append(("a roll of 7", with("pendingRoll", 7)))
        cases.append(("three sixes carried", with("sixesInARow", 3)))
        cases.append(("winner with tokens out", with("winner", 0)))
        cases.append(("unknown colour", with("toMove", 9)))
        for (what, object) in cases { #expect(!decodes(object), "\(what)") }
    }

    // Apple platforms only: on Linux, Foundation's JSON parser itself traps on some malformed escape
    // sequences (a swift-corelibs-foundation bug) instead of throwing. The app runs on iOS, where
    // the parser throws and this test checks our own validation.
    @Test("Random damage never crashes: it is refused or loads as a playable game", .enabled(if: Self.appleFoundation))
    func randomDamage() throws {
        var g = GameState(players: PlayerColor.allCases)
        g.roll(6)
        let data = try JSONEncoder().encode(g)
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            var bytes = [UInt8](data)
            for _ in 0..<Int.random(in: 1...4, using: &rng) {
                bytes[Int.random(in: 0..<bytes.count, using: &rng)] = UInt8.random(in: 32...126, using: &rng)
            }
            if var loaded = try? JSONDecoder().decode(GameState.self, from: Data(bytes)) {
                // It loaded, so it must play on without trapping.
                for m in loaded.legalMoves() { var copy = loaded; _ = try? copy.apply(m) }
                if loaded.pendingRoll == nil && !loaded.isOver { loaded.roll(3) }
            }
        }
    }
}
