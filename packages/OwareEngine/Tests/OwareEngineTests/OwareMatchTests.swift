import Foundation
import Testing
@testable import OwareEngine

@Suite("A match played on two phones")
struct OwareMatchTests {
    private struct LCG: RandomNumberGenerator {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
    }

    /// A random game played to the end, as the houses played.
    private func randomGame(_ rules: RuleSet, seed: UInt64, maxPlies: Int = .max) throws -> [Int] {
        var rng = LCG(s: seed)
        var state = GameState.initial(rules: rules)
        var houses: [Int] = []
        while !state.isOver, houses.count < maxPlies, let move = state.legalMoves().randomElement(using: &rng) {
            try state.apply(move)
            houses.append(move.absoluteIndex)
        }
        return houses
    }

    @Test("A whole random game survives the round trip between phones and replays to the same position",
          arguments: [RuleSet.abapa, RuleSet.namNam])
    func roundTrip(rules: RuleSet) throws {
        var rng = LCG(s: 3)
        // Each message is replayed in full, so keep games short enough to stay fast.
        for _ in 0..<4 {
            var match = OwareMatch(rules: rules)
            var local = GameState.initial(rules: rules)
            var plies = 0
            while !local.isOver, plies < 150, let move = local.legalMoves().randomElement(using: &rng) {
                match = try OwareMatch.decode(try match.playing(move.absoluteIndex).encoded())
                try local.apply(move)
                plies += 1
            }
            #expect(try match.state() == local)
            #expect(try match.playerToMove() == (local.isOver ? nil : local.sideToMove))
            #expect(try match.encoded().count < OwareMatch.maxEncodedBytes)
        }
    }

    @Test("Illegal moves are refused when played and when received")
    func illegalMovesRefused() throws {
        let match = OwareMatch(rules: .abapa)
        #expect(throws: OwareMatch.Failure.illegalMove(ply: 0, house: 6)) { try match.playing(6) }   // B1 on South's turn
        #expect(throws: OwareMatch.Failure.illegalMove(ply: 0, house: 12)) { try match.playing(12) }
        let tampered = OwareMatch(rules: .abapa, houses: [0, 0])   // A1 then A1 again, on North's turn
        #expect(throws: OwareMatch.Failure.illegalMove(ply: 1, house: 0)) { try OwareMatch.decode(try JSONEncoder().encode(tampered)) }
    }

    @Test("A match from a newer app version is refused, not misread")
    func newerFormatRefused() throws {
        var future = OwareMatch(rules: .namNam)
        future.version = OwareMatch.formatVersion + 1
        #expect(OwareMatch.formatVersion == 2)
        #expect(throws: OwareMatch.Failure.newerFormat(3)) {
            try OwareMatch.decode(try JSONEncoder().encode(future))
        }
    }

    @Test("A version 1 match, from before nearby play, still decodes")
    func version1Decodes() throws {
        let json = #"{"version":1,"rules":\#(String(decoding: try JSONEncoder().encode(RuleSet.abapa), as: UTF8.self)),"houses":[2,8]}"#
        let match = try OwareMatch.decode(Data(json.utf8))
        #expect(match.houses == [2, 8])
        #expect(match.starter == .south)
        #expect(match.game == 1)
        #expect(try match.playerToMove() == .south)
        // The old name still works until every caller has moved.
        let old: OnlineMatch = match
        #expect(old.rules == .abapa)
    }

    @Test("Resigning ends the match for the other player, and nothing can be played after")
    func resigning() throws {
        let match = try OwareMatch(rules: .namNam).playing(0).resigning(.north)
        #expect(try match.state().outcome == .win(.south, .agreement))
        #expect(throws: OwareMatch.Failure.gameIsOver) { try match.playing(6) }
    }

    @Test("Turns follow the rules, including Nam-Nam's extra move to feed")
    func turns() throws {
        let match = try OwareMatch(rules: .abapa).playing(0)
        #expect(try match.playerToMove() == .north)

        // Find a Nam-Nam game where a move empties the opponent's side, so the mover goes again,
        // then check the match data agrees.
        var rng = LCG(s: 11)
        var played: [Int]?
        for _ in 0..<200 where played == nil {
            var local = GameState.initial(rules: .namNam)
            var houses: [Int] = []
            while !local.isOver, let move = local.legalMoves().randomElement(using: &rng) {
                let round = local.round
                try local.apply(move)
                houses.append(move.absoluteIndex)
                if !local.isOver, local.round == round, local.sideToMove == move.player {
                    played = houses
                    break
                }
            }
        }
        let houses = try #require(played, "some random game should need an extra move to feed")
        let online = try OwareMatch.decode(OwareMatch(rules: .namNam, houses: houses).encoded())
        let state = try online.state()
        let mover = try #require(state.lastMove?.player)
        #expect(try online.playerToMove() == mover, "the mover sows again to feed")
        #expect(state.sideIsEmpty(mover.opponent))
    }

    // MARK: - Intents: what a phone asks the host to do

    @Test("North can start, and South then waits")
    func northStarts() throws {
        let match = OwareMatch(rules: .abapa, starter: .north)
        #expect(try match.playerToMove() == .north)
        #expect(throws: OwareMatch.Failure.notYourTurn) { try match.applying(.play(house: 0), from: .south) }
        let next = try match.applying(.play(house: 6), from: .north)
        #expect(next.houses == [6])
        #expect(try next.playerToMove() == .south)
        #expect(try OwareMatch.decode(next.encoded()) == next)
    }

    @Test("A move on the other player's turn is refused")
    func wrongTurn() throws {
        let match = OwareMatch(rules: .abapa)
        #expect(throws: OwareMatch.Failure.notYourTurn) { try match.applying(.play(house: 6), from: .north) }
    }

    @Test("A move from an empty house is refused")
    func emptyHouse() throws {
        let match = try OwareMatch(rules: .abapa).playing(0).playing(6)   // A1 is empty now
        #expect(throws: OwareMatch.Failure.illegalMove(ply: 2, house: 0)) { try match.applying(.play(house: 0), from: .south) }
    }

    @Test("A move that leaves the other player with nothing, when they could be fed, is refused")
    func feedingRule() throws {
        // Play random games until a player must feed the other, then try a move that would not.
        var rng = LCG(s: 5)
        var found = false
        for _ in 0..<300 where !found {
            var m = OwareMatch(rules: .abapa)
            while let s = try? m.state(), !s.isOver {
                let mover = s.sideToMove
                if s.sideIsEmpty(mover.opponent),
                   let starving = mover.houseRange.first(where: { s.houses[$0] > 0 && !s.isLegal(Move(player: mover, absoluteHouse: $0)) }) {
                    #expect(throws: OwareMatch.Failure.illegalMove(ply: m.houses.count, house: starving)) {
                        try m.applying(.play(house: starving), from: mover)
                    }
                    found = true
                    break
                }
                guard let move = s.legalMoves().randomElement(using: &rng) else { break }
                m = try m.applying(.play(house: move.absoluteIndex), from: mover)
            }
        }
        #expect(found, "some random Abapa game should reach a position where a player must be fed")
    }

    @Test("Resigning, from either player on either turn, ends it for the other side")
    func resignIntent() throws {
        let match = try OwareMatch(rules: .abapa).playing(0)
        let resigned = try match.applying(.resign, from: .south)   // North to move; South resigns anyway
        #expect(try resigned.state().outcome == .win(.north, .agreement))
        #expect(try resigned.playerToMove() == nil)
        #expect(throws: OwareMatch.Failure.gameIsOver) { try resigned.applying(.resign, from: .north) }
    }

    @Test("A rematch is a fresh match with the other starter and a new id")
    func rematch() throws {
        let match = OwareMatch(rules: .namNam, starter: .south)
        #expect(throws: OwareMatch.Failure.gameNotOver) { try match.applying(.rematch, from: .north) }
        let over = try match.playing(0).resigning(.north)
        let next = try over.applying(.rematch, from: .north)
        #expect(next.starter == .north)
        #expect(next.matchID != over.matchID)
        #expect(next.game == over.game + 1)
        #expect(next.houses.isEmpty && next.resignedBy == nil)
        #expect(next.rules == .namNam)
        #expect(try next.playerToMove() == .north)
        let again = try next.resigning(.south).applying(.rematch, from: .south)
        #expect(again.starter == .south)
    }

    @Test("A whole Nam-Nam game replays to the same position as the game record")
    func namNamMatchesRecord() throws {
        let houses = try randomGame(.namNam, seed: 21)
        let match = OwareMatch(rules: .namNam, houses: houses)
        var moves: [Move] = []
        var replay = GameState.initial(rules: .namNam)
        for house in houses {
            let move = Move(player: replay.sideToMove, absoluteHouse: house)
            moves.append(move)
            try replay.apply(move)
        }
        let record = GameRecord(rules: .namNam, moves: moves)
        let state = try match.state()
        #expect(state.isOver)
        #expect(state == (try record.replay()))
    }

    @Test("Even the longest game fits in one message", arguments: [RuleSet.abapa, RuleSet.namNam])
    func longestGameFits(rules: RuleSet) throws {
        var longest: [Int] = []
        for seed in UInt64(1)...6 {
            let houses = try randomGame(rules, seed: seed)
            if houses.count > longest.count { longest = houses }
        }
        // Pad to far more moves than any real game, as the worst case for size.
        let worst = Array(repeating: 11, count: max(longest.count, 4_000))
        let size = try JSONEncoder().encode(OwareMatch(rules: rules, houses: worst)).count
        #expect(size < OwareMatch.maxEncodedBytes)
        #expect(try OwareMatch(rules: rules, houses: longest).encoded().count < OwareMatch.maxEncodedBytes)
    }

    // MARK: - Snapshots: what the host sends back

    @Test("A snapshot is taken only if it carries on the match the phone already has")
    func snapshotsMoveForward() throws {
        let start = OwareMatch(rules: .abapa)
        let one = try start.playing(2)
        let two = try one.playing(8)
        #expect(two.supersedes(one))
        #expect(two.supersedes(start))
        #expect(!one.supersedes(two), "a stale snapshot is ignored")
        #expect(!one.supersedes(one), "a repeat is ignored")

        let resigned = try one.resigning(.south)
        #expect(resigned.supersedes(one))
        #expect(!one.supersedes(resigned))

        // A different game at the same point does not carry on this one.
        let other = try start.playing(3)
        #expect(!other.supersedes(one))
        var foreign = OwareMatch(rules: .abapa, houses: [2, 8, 3])
        foreign.matchID = UUID()
        #expect(!foreign.supersedes(one))

        // A rematch replaces the finished game, but an old game never replaces the rematch.
        let rematch = try resigned.applying(.rematch, from: .north)
        #expect(rematch.supersedes(resigned))
        #expect(!two.supersedes(rematch))
    }
}
