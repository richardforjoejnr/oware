import Foundation
import Testing
@testable import OwareEngine

/// Properties that must hold after every move of every game, under both rule sets and every
/// Abapa grand-slam option. Each property is checked at every ply of many random games.
@Suite("Rule invariants")
struct RuleInvariantTests {
    private struct LCG: RandomNumberGenerator {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
    }

    static let ruleSets: [RuleSet] = [
        .abapa,
        RuleSet(grandSlam: .illegalMove),
        RuleSet(grandSlam: .captureEndsGame),
        .namNam,
    ]

    private func name(_ r: RuleSet) -> String { "\(r.variant.rawValue)/\(r.grandSlam.rawValue)" }

    /// Plays `games` random games and hands each (before, move, events, after) to `check`.
    private func forEachMove(_ rules: RuleSet, seed: UInt64, games: Int,
                             _ check: (GameState, Move, [MoveEvent], GameState) throws -> Void) throws {
        var rng = LCG(s: seed)
        for _ in 0..<games {
            var s = GameState.initial(rules: rules)
            var plies = 0
            while !s.isOver && plies < 5_000 {
                guard let move = s.legalMoves().randomElement(using: &rng) else { break }
                let before = s
                let events = try s.apply(move)
                try check(before, move, events, s)
                plies += 1
            }
            #expect(s.isOver, "\(name(rules)): a random game must finish")
        }
    }

    @Test("48 seeds, never negative, never more than 48 in a store", arguments: ruleSets)
    func seedsAreConserved(rules: RuleSet) throws {
        try forEachMove(rules, seed: 1, games: 80) { _, move, _, after in
            #expect(after.totalSeeds == 48, "\(name(rules)) after \(move)\n\(after)")
            #expect(after.houses.allSatisfy { $0 >= 0 } && after.stores.allSatisfy { (0...48).contains($0) })
        }
    }

    @Test("Every seed that moves is accounted for by the events", arguments: ruleSets)
    func eventsAccountForEverySeed(rules: RuleSet) throws {
        try forEachMove(rules, seed: 2, games: 80) { before, move, events, after in
            var lifted = 0, sown = 0
            var won = [0, 0]
            var roundResult: RoundResult?
            for e in events {
                switch e {
                case let .pickUp(_, seeds), let .relay(_, seeds): lifted += seeds
                case .sow: sown += 1
                case let .capture(_, seeds, by): won[by.rawValue] += seeds
                case let .sweep(player, seeds): won[player.rawValue] += seeds
                case let .roundOver(r): roundResult = r
                default: break
                }
            }
            // Seeds lifted but not sown were still in hand when the last four were taken.
            let inHand = lifted - sown
            #expect(inHand >= 0)
            if inHand > 0 {
                #expect(rules.variant == .namNam && roundResult != nil, "only the last four can bank seeds from the hand")
            }
            // Store gains: compare with the round's totals when the round ended (stores are reset).
            let endStores = roundResult.map { [$0.southSeeds, $0.northSeeds] } ?? after.stores
            let gained = [endStores[0] - before.stores[0], endStores[1] - before.stores[1]]
            let lastFourTaker = events.reversed().compactMap { if case let .capture(_, _, by) = $0 { return by } else { return nil } }.first
            var expected = won
            if inHand > 0, let taker = lastFourTaker { expected[taker.rawValue] += inHand }
            #expect(gained == expected, "\(name(rules)) \(move): stores gained \(gained), events say \(expected)\n\(before)")
        }
    }

    @Test("Legal moves play; everything else is refused with the right reason", arguments: ruleSets)
    func legalityIsExact(rules: RuleSet) throws {
        try forEachMove(rules, seed: 3, games: 40) { before, _, _, _ in
            let legal = Set(before.legalMoves())
            for house in 0..<12 {
                for player in Player.allCases {
                    let move = Move(player: player, absoluteHouse: house)
                    var copy = before
                    if legal.contains(move) {
                        #expect(throws: Never.self) { try copy.apply(move) }
                        continue
                    }
                    do {
                        try copy.apply(move)
                        Issue.record("\(name(rules)): \(move) was not offered but played\n\(before)")
                    } catch let error as MoveError {
                        switch error {
                        case .notYourTurn: #expect(player != before.sideToMove)
                        case .notYourHouse: #expect(before.territory[house] != player)
                        case .emptyHouse: #expect(before.houses[house] == 0)
                        case .mustFeedOpponent: #expect(before.sideIsEmpty(player.opponent))
                        case .grandSlamNotAllowed: #expect(rules.grandSlam == .illegalMove)
                        case .gameIsOver: Issue.record("game was not over")
                        }
                        #expect(copy == before, "a refused move must not change the position")
                    }
                }
            }
        }
    }

    @Test("A game that is not over always has a move, and only from the mover's own houses", arguments: ruleSets)
    func alwaysAMove(rules: RuleSet) throws {
        try forEachMove(rules, seed: 4, games: 80) { _, _, _, after in
            if after.isOver {
                #expect(after.legalMoves().isEmpty)
            } else {
                let moves = after.legalMoves()
                #expect(!moves.isEmpty, "\(name(rules)): stuck position\n\(after)")
                #expect(moves.allSatisfy { $0.player == after.sideToMove && after.territory[$0.absoluteIndex] == $0.player && after.houses[$0.absoluteIndex] > 0 })
            }
        }
    }

    @Test("The preview of a move matches what the move does", arguments: ruleSets)
    func previewMatchesPlay(rules: RuleSet) throws {
        try forEachMove(rules, seed: 5, games: 60) { before, move, events, after in
            let preview = try #require(before.preview(move))
            let captured = events.reduce(0) { total, e in
                if case let .capture(_, seeds, by) = e, by == move.player { return total + seeds }
                return total
            }
            let sweptOrRound = events.contains { if case .sweep = $0 { return true }; if case .roundOver = $0 { return true }; return false }
            if !sweptOrRound {
                #expect(preview.path.count == events.filter { if case .sow = $0 { return true } else { return false } }.count)
                #expect(preview.resultingHouses == after.houses, "\(name(rules)) \(move)\n\(before)")
                #expect(preview.capturedSeeds == captured)
            }
            #expect(before.preview(move) == preview, "previewing must not change the position")
        }
    }

    @Test("applying(_:) leaves the original untouched and agrees with apply(_:)", arguments: ruleSets)
    func applyingIsPure(rules: RuleSet) throws {
        try forEachMove(rules, seed: 6, games: 40) { before, move, events, after in
            let result = try before.applying(move)
            #expect(result.state == after)
            #expect(result.events == events)
        }
    }

    @Test("The same moves from the same start always give the same game", arguments: ruleSets)
    func deterministic(rules: RuleSet) throws {
        var rng = LCG(s: 7)
        for _ in 0..<30 {
            var s = GameState.initial(rules: rules)
            var moves: [Move] = []
            while !s.isOver, let m = s.legalMoves().randomElement(using: &rng) { try s.apply(m); moves.append(m) }
            var replay = GameState.initial(rules: rules)
            for m in moves { try replay.apply(m) }
            #expect(replay == s)
        }
    }

    @Test("A game saved at any point resumes exactly", arguments: ruleSets)
    func savesResume(rules: RuleSet) throws {
        var rng = LCG(s: 8)
        for _ in 0..<20 {
            var s = GameState.initial(rules: rules)
            var ply = 0
            while !s.isOver, let m = s.legalMoves().randomElement(using: &rng) {
                if ply % 5 == 0 {
                    let restored = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(s))
                    #expect(restored == s)
                    #expect(restored.legalMoves() == s.legalMoves())
                    var a = s, b = restored
                    #expect(try a.apply(m) == b.apply(m))
                    #expect(a == b)
                }
                try s.apply(m)
                ply += 1
            }
        }
    }

    @Test("Results match the scores", arguments: ruleSets)
    func resultsMatchScores(rules: RuleSet) throws {
        try forEachMove(rules, seed: 9, games: 80) { _, _, events, after in
            guard let outcome = after.outcome else { return }
            #expect(events.last == .gameOver(outcome), "the last event announces the result")
            if rules.variant == .abapa {
                let (a, b) = (after.stores[0], after.stores[1])
                #expect(outcome.winner == (a == b ? nil : (a > b ? .south : .north)))
                if outcome.reason == .reachedWinningSeeds { #expect(max(a, b) >= 25) }
                if outcome.reason != .reachedWinningSeeds { #expect(max(a, b) <= 25 || outcome.reason == .grandSlam || outcome.reason == .noLegalMoves || outcome.reason == .opponentCouldNotBeFed || outcome.reason == .repetition || outcome.reason == .boardEmpty) }
            } else {
                let last = try #require(after.roundHistory.last)
                #expect(last.southHouses + last.northHouses == 12)
                switch outcome.reason {
                case .territory: #expect(max(last.southHouses, last.northHouses) == 12)
                case .roundLimit:
                    #expect(after.round == rules.maxRounds)
                    #expect(outcome.winner == (last.southHouses == last.northHouses ? nil : (last.southHouses > last.northHouses ? .south : .north)))
                default: Issue.record("unexpected Nam-Nam ending \(outcome)")
                }
            }
        }
    }

    @Test("Nam-Nam rounds: territory from A1, houses match the seeds won, fresh board, alternating starter")
    func namNamRoundInvariants() throws {
        try forEachMove(.namNam, seed: 10, games: 80) { before, _, events, after in
            for case let .roundOver(r) in events {
                #expect(r.southSeeds + r.northSeeds == 48)
                #expect(r.southHouses + r.northHouses == 12)
                #expect(abs(r.southHouses * 4 - r.southSeeds) < 4, "houses are the seeds won, in fours")
                if r.southSeeds > r.northSeeds { #expect(r.southHouses >= r.northHouses) }
                if r.northSeeds > r.southSeeds { #expect(r.northHouses >= r.southHouses) }
                #expect(r.round == before.round)
                if !after.isOver {
                    #expect(after.round == before.round + 1)
                    #expect(after.territory == (0..<12).map { $0 < r.southHouses ? .south : .north })
                    #expect(after.houses == Array(repeating: 4, count: 12) && after.stores == [0, 0])
                    #expect(after.sideToMove == (after.round % 2 == 1 ? .south : .north))
                }
            }
            if !events.contains(where: { if case .roundOver = $0 { return true } else { return false } }) {
                #expect(after.territory == before.territory, "territory only changes between rounds")
                #expect(after.round == before.round)
            }
        }
    }

    @Test("Abapa: captures only on the other row, only 2s and 3s, only by the last seed and the houses before it")
    func abapaCaptureShape() throws {
        try forEachMove(.abapa, seed: 11, games: 150) { before, move, events, _ in
            let taken = events.compactMap { if case let .capture(h, s, _) = $0 { return (h, s) } else { return nil } }
            guard !taken.isEmpty else { return }
            let landing = events.compactMap { if case let .sow(h, _) = $0 { return h } else { return nil } }.last!
            #expect(taken.map(\.0) == Array(stride(from: landing, through: landing - taken.count + 1, by: -1)), "a contiguous run back from the landing house")
            #expect(taken.allSatisfy { !move.player.owns($0.0) && ($0.1 == 2 || $0.1 == 3) })
            _ = before
        }
    }
}

extension RuleSet: CustomTestStringConvertible {
    public var testDescription: String { "\(variant.rawValue)/\(grandSlam.rawValue)" }
}
