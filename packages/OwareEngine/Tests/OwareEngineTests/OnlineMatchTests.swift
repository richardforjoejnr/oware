import Foundation
import Testing
@testable import OwareEngine

@Suite("Online match data")
struct OnlineMatchTests {
    private struct LCG: RandomNumberGenerator {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
    }

    @Test("A whole random game survives the round trip between phones and replays to the same position",
          arguments: [RuleSet.abapa, RuleSet.namNam])
    func roundTrip(rules: RuleSet) throws {
        var rng = LCG(s: 3)
        // Each message is replayed in full, so keep games short enough to stay fast.
        for _ in 0..<4 {
            var match = OnlineMatch(rules: rules)
            var local = GameState.initial(rules: rules)
            var plies = 0
            while !local.isOver, plies < 150, let move = local.legalMoves().randomElement(using: &rng) {
                match = try OnlineMatch.decode(try match.playing(move.absoluteIndex).encoded())
                try local.apply(move)
                plies += 1
            }
            #expect(try match.state() == local)
            #expect(try match.playerToMove() == (local.isOver ? nil : local.sideToMove))
            #expect(try match.encoded().count < OnlineMatch.maxEncodedBytes)
        }
    }

    @Test("Illegal moves are refused when played and when received")
    func illegalMovesRefused() throws {
        let match = OnlineMatch(rules: .abapa)
        #expect(throws: OnlineMatch.Failure.illegalMove(ply: 0, house: 6)) { try match.playing(6) }   // B1 on South's turn
        #expect(throws: OnlineMatch.Failure.illegalMove(ply: 0, house: 12)) { try match.playing(12) }
        let tampered = OnlineMatch(rules: .abapa, houses: [0, 0])   // A1 then A1 again, on North's turn
        #expect(throws: OnlineMatch.Failure.illegalMove(ply: 1, house: 0)) { try OnlineMatch.decode(try JSONEncoder().encode(tampered)) }
    }

    @Test("A match from a newer app version is refused, not misread")
    func newerFormatRefused() throws {
        var future = OnlineMatch(rules: .namNam)
        future.version = OnlineMatch.formatVersion + 1
        #expect(throws: OnlineMatch.Failure.newerFormat(OnlineMatch.formatVersion + 1)) {
            try OnlineMatch.decode(try JSONEncoder().encode(future))
        }
    }

    @Test("Resigning ends the match for the other player, and nothing can be played after")
    func resigning() throws {
        let match = try OnlineMatch(rules: .namNam).playing(0).resigning(.north)
        #expect(try match.state().outcome == .win(.south, .agreement))
        #expect(throws: OnlineMatch.Failure.gameIsOver) { try match.playing(6) }
    }

    @Test("Turns follow the rules, including Nam-Nam's extra move to feed")
    func turns() throws {
        let match = try OnlineMatch(rules: .abapa).playing(0)
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
        let online = try OnlineMatch.decode(OnlineMatch(rules: .namNam, houses: houses).encoded())
        let state = try online.state()
        let mover = try #require(state.lastMove?.player)
        #expect(try online.playerToMove() == mover, "the mover sows again to feed")
        #expect(state.sideIsEmpty(mover.opponent))
    }
}
