import MatchKit
import OwareEngine
import XCTest
@testable import Oware

/// Asking for another game on two phones: the other player can say Rematch or Not now, and a
/// request nobody answers lapses after a minute. The phone in charge decides, as for moves.
@MainActor
final class RematchTests: XCTestCase {
    private let clock = ManualClock()
    private let rules = OwareRoomRules()

    private func until(_ what: @autoclosure () -> String, timeout: TimeInterval = 5, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { return XCTFail("timed out waiting: \(what())") }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func settle() async { try? await Task.sleep(nanoseconds: 50_000_000) }

    /// Time goes by with both phones there, each pinging the other as their heartbeats do.
    private func pass(_ seconds: Double, _ p: Pair) async {
        var left = seconds
        while left > 0 {
            let step = min(left, 3)
            clock.advance(by: step)
            left -= step
            await p.guestLink.tick()
            try? await Task.sleep(nanoseconds: 3_000_000)
            await p.hostLink.tick()
            try? await Task.sleep(nanoseconds: 3_000_000)
        }
    }

    /// A finished game (North resigned), both phones ready, nobody has asked for another.
    private func finished() throws -> OwareTable {
        var table = OwareTable.opening(OwareMatch(rules: .abapa))
        table.ready = [.south, .north]
        return try rules.applying(.game(.resign), from: 1, to: table)
    }

    // MARK: The rules, on the phone in charge

    func testNotNowClearsTheRequestAndSaysWhoDeclined() throws {
        let asked = try rules.applying(.game(.rematch), from: 0, to: finished())
        XCTAssertEqual(asked.rematchAsked, [.south])
        let declined = try rules.applying(.declineRematch, from: 1, to: asked)
        XCTAssertEqual(declined.rematchAsked, [])
        XCTAssertEqual(declined.rematchDeclinedBy, .north)
        XCTAssertEqual(declined.match, asked.match, "the finished game stays as it was")
        XCTAssertEqual(declined.rematchRound, asked.rematchRound + 1)
    }

    func testAfterNotNowEitherPlayerMayAskAgain() throws {
        var table = try rules.applying(.game(.rematch), from: 0, to: finished())
        table = try rules.applying(.declineRematch, from: 1, to: table)
        let again = try rules.applying(.game(.rematch), from: 0, to: table)
        XCTAssertEqual(again.rematchAsked, [.south])
        XCTAssertNil(again.rematchDeclinedBy, "a new request is not an old answer")
        let other = try rules.applying(.game(.rematch), from: 1, to: table)
        XCTAssertEqual(other.rematchAsked, [.north])

        let started = try rules.applying(.game(.rematch), from: 1, to: again)
        XCTAssertEqual(started.match.game, 2, "both asked: the next game")
        XCTAssertEqual(started.rematchAsked, [])
        XCTAssertNil(started.rematchDeclinedBy)
    }

    func testNotNowMeansNothingUnlessTheOtherPlayerAsked() throws {
        let nobody = try finished()
        XCTAssertEqual(try rules.applying(.declineRematch, from: 1, to: nobody), nobody)
        let mine = try rules.applying(.game(.rematch), from: 1, to: nobody)
        XCTAssertEqual(try rules.applying(.declineRematch, from: 1, to: mine), mine, "you cannot decline your own request")
    }

    func testARequestLapsesForWhoeverAsked() throws {
        let asked = try rules.applying(.game(.rematch), from: 1, to: finished())
        let lapsed = try XCTUnwrap(OwareRoomRules.lapsing(asked))
        XCTAssertEqual(lapsed.rematchAsked, [])
        XCTAssertEqual(lapsed.rematchLapsedFor, .north)
        XCTAssertNil(lapsed.rematchDeclinedBy)
        XCTAssertEqual(lapsed.rematchRound, asked.rematchRound + 1)
        XCTAssertNil(OwareRoomRules.lapsing(try finished()), "nothing asked, nothing to lapse")

        let again = try rules.applying(.game(.rematch), from: 0, to: lapsed)
        XCTAssertEqual(again.rematchAsked, [.south], "either may ask again")
        XCTAssertNil(again.rematchLapsedFor)
    }

    /// A phone takes a snapshot only if it carries the game further. A request that was answered
    /// or lapsed is further on than the request, though fewer players are asking.
    func testASnapshotWithTheRequestEndedReplacesTheRequest() throws {
        let asked = try rules.applying(.game(.rematch), from: 0, to: finished())
        let declined = try rules.applying(.declineRematch, from: 1, to: asked)
        XCTAssertTrue(rules.shouldReplace(asked, with: declined))
        XCTAssertFalse(rules.shouldReplace(declined, with: asked), "the request arriving late does not bring it back")
        let again = try rules.applying(.game(.rematch), from: 0, to: declined)
        XCTAssertTrue(rules.shouldReplace(declined, with: again))
        XCTAssertFalse(rules.shouldReplace(again, with: asked), "the same asker, an older request")
    }

    // MARK: On the wire (room protocol version 2, shared/vectors/room-v2)

    /// A table with nothing declined or lapsed is written exactly as before, so a phone on the
    /// build before this one reads it; and a table from that build, without the new keys, is read.
    func testTheNewValuesAreLeftOutUntilTheyMeanSomething() throws {
        let asked = try rules.applying(.game(.rematch), from: 0, to: finished())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(asked)) as? [String: Any])
        XCTAssertNil(json["rematchDeclinedBy"])
        XCTAssertNil(json["rematchLapsedFor"])
        XCTAssertNil(json["rematchRound"])
        XCTAssertEqual(Set(json.keys), ["match", "rematchAsked", "paces", "ready", "stateHash", "isOutOfStep"])
        XCTAssertEqual(try JSONDecoder().decode(OwareTable.self, from: JSONEncoder().encode(asked)), asked)

        let declined = try rules.applying(.declineRematch, from: 1, to: asked)
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(declined)) as? [String: Any])
        XCTAssertEqual(written["rematchDeclinedBy"] as? Int, 1)
        XCTAssertEqual(written["rematchRound"] as? Int, 1)
        XCTAssertEqual(try JSONDecoder().decode(OwareTable.self, from: JSONEncoder().encode(declined)), declined)
    }

    func testNotNowIsWrittenAsItsExample() throws {
        let data = try JSONEncoder().encode(TableIntent.declineRematch)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"type":"declineRematch"}"#)
        XCTAssertEqual(try JSONDecoder().decode(TableIntent.self, from: data), .declineRematch)
    }

    // MARK: Two phones

    private struct Pair {
        let host: GameSession
        let guest: GameSession
        let hostLink: MatchLink
        let guestLink: MatchLink
        let guestTransport: LoopbackTransport
    }

    /// Kofi (in charge, South) and Ama, their game just finished: Kofi resigned.
    private func afterAGame() async -> Pair {
        let host = TestSupport.session(), guest = TestSupport.session()
        let hostTransport = LoopbackTransport(), guestTransport = LoopbackTransport()
        let hostLink = MatchLink(hosting: OwareMatch(rules: .abapa), name: "Kofi", transport: hostTransport, clock: clock)
        let guestLink = MatchLink(joiningAs: "Ama", transport: guestTransport, clock: clock)
        host.startRemote(hostLink)
        guest.startRemote(guestLink)
        hostTransport.connect(guestTransport)
        await until("Ama asks to join") { hostLink.joinRequests.count == 1 }
        await hostLink.accept(hostLink.joinRequests[0].peer)
        await until("both seated") { host.remoteGame?.opponentName == "Ama" && guest.remoteGame?.opponentName == "Kofi" }
        await hostLink.ready()
        await guestLink.ready()
        await until("both ready") { host.isStarted && guest.isStarted }
        host.resign()
        await until("both over") { host.isGameOver && guest.isGameOver }
        return Pair(host: host, guest: guest, hostLink: hostLink, guestLink: guestLink, guestTransport: guestTransport)
    }

    func testTheOtherPlayerSeesWhoAskedAndCanAnswer() async {
        let p = await afterAGame()
        XCTAssertFalse(p.guest.canAnswerRematch, "nobody has asked")
        XCTAssertNil(p.guest.rematchRequest)
        p.host.requestRematch()
        await until("Ama sees the request") { p.guest.canAnswerRematch }
        XCTAssertEqual(p.guest.rematchRequest, "Kofi wants a rematch")
        XCTAssertFalse(p.host.canAnswerRematch, "it is Kofi's own request")
        XCTAssertNil(p.host.rematchRequest)
    }

    func testNotNowTellsTheAskerInPlainWordsAndTheyMayAskAgain() async {
        let p = await afterAGame()
        p.host.requestRematch()
        await until("Ama sees the request") { p.guest.canAnswerRematch }
        p.guest.declineRematch()
        await until("Kofi is told") { p.host.rematchNote == "Ama said not now" }
        XCTAssertEqual(p.host.rematchAsked, [], "the request is cleared")
        XCTAssertTrue(p.host.canAskRematch, "and may be made again")
        await until("cleared on Ama's phone too") { p.guest.rematchAsked.isEmpty }
        XCTAssertFalse(p.guest.canAnswerRematch)
        XCTAssertNil(p.guest.rematchNote, "the one who said it needs no telling")
        XCTAssertTrue(p.host.isGameOver && p.guest.isGameOver)

        p.host.requestRematch()
        await until("asked again") { p.guest.canAnswerRematch }
        XCTAssertNil(p.host.rematchNote, "the old answer goes when a new request is made")
        p.guest.requestRematch()
        await until("a new game") { !p.host.isGameOver && !p.guest.isGameOver }
    }

    func testTheGuestsRequestCanBeDeclinedByThePhoneInCharge() async {
        let p = await afterAGame()
        p.guest.requestRematch()
        await until("Kofi sees the request") { p.host.canAnswerRematch }
        p.host.declineRematch()
        await until("Ama is told") { p.guest.rematchNote == "Kofi said not now" }
        XCTAssertTrue(p.guest.canAskRematch)
    }

    func testARequestNobodyAnswersLapsesAfterAMinute() async {
        let p = await afterAGame()
        p.guest.requestRematch()
        await until("Kofi sees the request") { p.host.canAnswerRematch }

        await pass(59, p)
        await settle()
        XCTAssertEqual(p.guest.rematchAsked, [.north], "59 s: still asking")
        XCTAssertFalse(p.host.isReconnecting || p.guest.isReconnecting, "both are there all along")

        await pass(1, p)
        await until("the request lapses on Ama's phone") { p.guest.rematchAsked.isEmpty }
        XCTAssertEqual(p.guest.rematchNote, "Kofi did not answer. You can ask again.")
        XCTAssertTrue(p.guest.canAskRematch)
        XCTAssertFalse(p.host.canAnswerRematch, "nothing left to answer")
        XCTAssertNil(p.host.rematchNote)
        XCTAssertTrue(p.host.canAskRematch, "either may ask again")

        p.host.requestRematch()
        await until("Ama sees his") { p.guest.canAnswerRematch }
        XCTAssertNil(p.guest.rematchNote)
    }

    func testTheMinuteStartsAgainWithEachRequest() async {
        let p = await afterAGame()
        p.host.requestRematch()
        await until("asked") { p.guest.canAnswerRematch }
        await pass(40, p)
        p.guest.declineRematch()
        await until("declined") { p.host.rematchNote != nil }
        p.host.requestRematch()
        await until("asked again") { p.guest.canAnswerRematch }
        await pass(40, p)
        await settle()
        XCTAssertEqual(p.host.rematchAsked, [.south], "40 s into the second request, not 80 s into the first")
        await pass(20, p)
        await until("lapsed") { p.host.rematchNote == "Ama did not answer. You can ask again." }
    }

    func testARematchBothAgreedToIsNotLapsedLater() async {
        let p = await afterAGame()
        p.host.requestRematch()
        await until("asked") { p.guest.canAnswerRematch }
        p.guest.requestRematch()
        await until("a new game") { !p.host.isGameOver && !p.guest.isGameOver }
        await pass(61, p)
        await settle()
        XCTAssertNil(p.host.rematchNote)
        XCTAssertFalse(p.host.isGameOver)
    }

    /// No rematch with someone who is not there: gone for good, or reconnecting.
    func testRematchIsNotOfferedWhileTheOtherPlayerIsAway() async {
        let p = await afterAGame()
        XCTAssertTrue(p.host.canAskRematch)
        p.guestTransport.isQuiet = true
        clock.advance(by: 5)
        await p.hostLink.tick()
        XCTAssertTrue(p.host.isReconnecting)
        XCTAssertFalse(p.host.canAskRematch, "reconnecting")
        clock.advance(by: 11)
        await p.hostLink.tick()
        XCTAssertTrue(p.host.opponentGone)
        XCTAssertFalse(p.host.canAskRematch, "gone")
        XCTAssertFalse(p.host.canAnswerRematch)
    }

    func testARequestIsNotAnsweredOnceTheAskerHasLeft() async {
        let p = await afterAGame()
        p.host.requestRematch()
        await until("asked") { p.guest.canAnswerRematch }
        p.host.leaveNearbyGame()
        await until("Ama is told he left") { p.guest.opponentLeft }
        XCTAssertFalse(p.guest.canAnswerRematch)
        XCTAssertFalse(p.guest.canAskRematch)
        XCTAssertNil(p.guest.rematchRequest)
    }
}
