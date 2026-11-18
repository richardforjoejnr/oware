import Foundation
import MatchKit
import Testing
@testable import MatchKitOnline

/// A tiny game: players take turns adding numbers. Seat 0 moves first.
struct Sum: Codable, Sendable, Equatable {
    var numbers: [Int] = []
}

struct SumRules: RoomRules {
    struct NotYourTurn: Error {}
    let seatCount = 2

    func applying(_ intent: Int, from seat: Int, to match: Sum) throws -> Sum {
        guard seat == match.numbers.count % seatCount else { throw NotYourTurn() }
        return Sum(numbers: match.numbers + [intent])
    }

    func shouldReplace(_ current: Sum, with snapshot: Sum) -> Bool {
        snapshot.numbers.count > current.numbers.count && snapshot.numbers.starts(with: current.numbers)
    }
}

typealias SumRoom = Room<SumRules>

@MainActor
final class Log {
    var events: [RoomEvent<Sum>] = []
}

/// Waits for `condition`, for as long as two seconds. The transports run on their own tasks, so
/// this polls on the clock rather than counting yields.
@MainActor
func eventually(_ what: Comment, _ condition: () async -> Bool) async {
    for _ in 0..<400 {
        if await condition() { return }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    Issue.record("timed out waiting: \(what)")
}

/// Long enough for anything on its way to arrive, for checking that something did not happen.
func settle() async { try? await Task.sleep(nanoseconds: 60_000_000) }

@MainActor
@Suite("Phones in a room through the relay")
struct OnlineTransportTests {
    static let game = RelayRequest.Game(name: "sum", protocolVersion: MatchKit.protocolVersion, formatVersion: 1)
    /// No waiting between tries.
    static let noSleep: OnlineTransport.Sleep = { _ in await Task.yield() }

    let relay = LocalRelay()
    let clock = ManualClock()

    private func create(seats: Int = 2) -> OnlineTransport {
        OnlineTransport(entry: .create(game: Self.game, seats: seats, proof: nil), install: "ama", dial: relay.dial,
                        sleep: Self.noSleep)
    }

    private func join(_ code: String = "K7M2QD", game: RelayRequest.Game = game, install: String = "kofi") -> OnlineTransport {
        OnlineTransport(entry: .join(code: RoomCode(code)!, game: game), install: install, dial: relay.dial, sleep: Self.noSleep)
    }

    private func isOpen(_ transport: OnlineTransport) -> Bool {
        if case .open = transport.status { return true }
        return false
    }

    /// Ama's game with Kofi seated in it.
    private func seated() async -> (host: SumRoom, guest: SumRoom, hostLink: OnlineTransport, guestLink: OnlineTransport,
                                    hostLog: Log, guestLog: Log) {
        let hostLink = create()
        let host = SumRoom(hosting: Sum(), name: "Ama", rules: SumRules(), transport: hostLink, clock: clock, timing: .online)
        let hostLog = Log()
        host.onEvent = { hostLog.events.append($0) }
        await eventually("the room is made") { isOpen(hostLink) }
        let guestLink = join()
        let guest = SumRoom(joiningAs: "Kofi", rules: SumRules(), transport: guestLink, clock: clock, timing: .online)
        let guestLog = Log()
        guest.onEvent = { guestLog.events.append($0) }
        await eventually("Kofi asks to join") { !host.pending.isEmpty }
        await host.accept(host.pending.keys.first!)
        await eventually("Kofi is seated") { guest.mySeat == 1 }
        return (host, guest, hostLink, guestLink, hostLog, guestLog)
    }

    // MARK: Getting in

    @Test func startingAGameGivesACodeToShare() async {
        let link = create()
        await eventually("open") { isOpen(link) }
        #expect(link.seat?.code == "K7M2QD")
        #expect(link.me == Relay.creator)
        #expect(link.seat?.token.isEmpty == false)
        link.close()
    }

    @Test func aFriendJoinsWithTheCodeAndTheyPlay() async throws {
        let table = await seated()
        #expect(table.guestLink.me == PeerID("p1"))
        try await table.host.send(4)
        await eventually("Kofi sees the move") { table.guest.match?.numbers == [4] }
        try await table.guest.send(7)
        await eventually("Ama sees his") { table.host.match?.numbers == [4, 7] }
        await eventually("and so does he") { table.guest.match?.numbers == [4, 7] }
    }

    @Test func aWrongCodeIsRefused() async {
        let link = join("ZZZZZZ")
        await eventually("refused") { link.status == .refused(.notFound) }
    }

    @Test func aThirdPhoneFindsTheRoomFull() async {
        _ = await seated()
        let third = join(install: "yaw")
        await eventually("refused") { third.status == .refused(.full) }
    }

    @Test func anotherVersionOfTheAppIsToldToUpdate() async {
        let host = create()
        await eventually("open") { isOpen(host) }
        let newer = RelayRequest.Game(name: "sum", protocolVersion: MatchKit.protocolVersion + 1, formatVersion: 1)
        let link = join(game: newer)
        await eventually("refused") { link.status == .refused(.needsUpdate) }
        host.close()
    }

    @Test func whenOnlinePlayIsRestingNobodyStartsAGame() async {
        await relay.setPaused(true)
        let link = create()
        await eventually("refused") { link.status == .refused(.paused) }
    }

    @Test func withNoInternetItGivesUpAndSaysSo() async {
        await relay.setReachable(false)
        let link = create()
        await eventually("unreachable") { link.status == .unreachable }
    }

    // MARK: Connections that break

    /// Kofi walks into a lift. Ama is told at once; her move while he is away reaches him when
    /// his phone is back, without either of them doing anything.
    @Test func aGuestWhoseConnectionBreaksComesBackToTheSameGame() async throws {
        let table = await seated()
        await relay.cut(PeerID("p1"), in: "K7M2QD")
        await eventually("Ama sees him reconnecting") { table.hostLog.events.contains(.reconnecting(seat: 1)) }
        try await table.host.send(4)
        await eventually("he is back") { table.hostLog.events.contains(.back(seat: 1)) }
        await eventually("with her move") { table.guest.match?.numbers == [4] }
        #expect(table.guestLink.me == PeerID("p1"), "the same seat")
        try await table.guest.send(7)
        await eventually("and play goes on") { table.host.match?.numbers == [4, 7] }
        let rejoins = await relay.received["rejoin"]
        #expect(rejoins == 1)
    }

    /// The phone in charge loses its connection: the game is still there when it is back.
    @Test func theCreatorsConnectionBreaksAndTheGameGoesOn() async throws {
        let table = await seated()
        try await table.host.send(4)
        await eventually("first move") { table.guest.match?.numbers == [4] }
        await relay.cut(Relay.creator, in: "K7M2QD")
        await eventually("Kofi sees her reconnecting") { table.guestLog.events.contains(.reconnecting(seat: 0)) }
        await eventually("she is back") { table.guestLog.events.contains(.back(seat: 0)) }
        try await table.guest.send(7)
        await eventually("his move is played") { table.host.match?.numbers == [4, 7] }
        await eventually("and he sees it") { table.guest.match?.numbers == [4, 7] }
    }

    /// A move made with no signal is not lost: it goes when the connection is back.
    @Test func aMoveMadeWithNoSignalIsSentWhenItReturns() async throws {
        let table = await seated()
        try await table.host.send(4)
        await eventually("first move") { table.guest.match?.numbers == [4] }
        await relay.setReachable(false, cutting: true)
        await eventually("Kofi's phone knows") { table.guestLog.events.contains(.reconnecting(seat: 0)) }
        #expect(table.guestLink.status == .reconnecting)
        try await table.guest.send(7)
        await settle()
        #expect(table.host.match?.numbers == [4])
        await relay.setReachable(true)
        await eventually("his move is played") { table.host.match?.numbers == [4, 7] }
        await eventually("and he sees it") { table.guest.match?.numbers == [4, 7] }
    }

    /// Seen on AWS: the relay was told a phone had gone when it had not, and forgot it. The
    /// phone's connection was still open, so nothing told it. Its next message is refused as
    /// "not in a room", and it takes its seat back by itself.
    @Test func aPhoneTheRelayForgotTakesItsSeatBack() async throws {
        let table = await seated()
        try await table.host.send(4)
        await eventually("first move") { table.guest.match?.numbers == [4] }
        await relay.forget(PeerID("p1"), in: "K7M2QD")
        await eventually("Ama sees him reconnecting") { table.hostLog.events.contains(.reconnecting(seat: 1)) }

        clock.advance(by: 10)
        await table.guest.tick()   // his next ping is the message that is refused
        await eventually("his phone takes its seat back") { await relay.received["rejoin"] == 1 }
        await eventually("and Ama sees him back") { table.hostLog.events.contains(.back(seat: 1)) }
        #expect(table.guestLink.me == PeerID("p1"))
        try await table.guest.send(7)
        await eventually("play goes on") { table.host.match?.numbers == [4, 7] }
        await eventually("on both phones") { table.guest.match?.numbers == [4, 7] }
    }

    @Test func aGameWhoseRoomHasGoneIsNotRejoined() async {
        let gone = OnlineTransport.Seat(code: "K7M2QD", peer: PeerID("p1"), token: "old")
        let link = OnlineTransport(entry: .rejoin(gone), install: "kofi", dial: relay.dial, sleep: Self.noSleep)
        await eventually("refused") { link.status == .refused(.notFound) }
    }

    // MARK: The app is closed and opened again

    /// What a phone keeps: its place at the relay, its room, and the match.
    private struct Kept {
        let seat: OnlineTransport.Seat
        let room: RoomSave
        let match: Sum
    }

    /// The app is closed: the connection goes, with no goodbye to the relay or the room.
    private func closeApp(_ room: SumRoom, _ link: OnlineTransport) throws -> Kept {
        let kept = Kept(seat: try #require(link.seat), room: try #require(room.save), match: try #require(room.match))
        link.abandon()
        room.stop()
        return kept
    }

    private func openApp(_ kept: Kept) -> (SumRoom, OnlineTransport, Log) {
        let link = OnlineTransport(entry: .rejoin(kept.seat), install: "x", dial: relay.dial, sleep: Self.noSleep)
        let room = SumRoom(resuming: kept.room, match: kept.match, rules: SumRules(), transport: link, clock: clock, timing: .online)
        let log = Log()
        room.onEvent = { log.events.append($0) }
        return (room, link, log)
    }

    @Test func closingTheAppDoesNotLeaveTheRoom() async throws {
        let table = await seated()
        _ = try closeApp(table.guest, table.guestLink)
        await eventually("Ama sees him reconnecting") { table.hostLog.events.contains(.reconnecting(seat: 1)) }
        await settle()
        #expect(!table.hostLog.events.contains(.left(seat: 1)), "he has not left")
        let leaves = await relay.received["leave"]
        #expect(leaves == nil, "the relay was not told he left")
    }

    @Test func theGuestClosesTheAppAndComesBackToTheSameGame() async throws {
        let table = await seated()
        try await table.host.send(4)
        await eventually("first move") { table.guest.match?.numbers == [4] }
        let kept = try closeApp(table.guest, table.guestLink)
        await eventually("Ama sees him reconnecting") { table.hostLog.events.contains(.reconnecting(seat: 1)) }

        let (guest, link, log) = openApp(kept)
        await eventually("his seat at the relay") { isOpen(link) }
        #expect(link.me == PeerID("p1"))
        await eventually("Ama has him back") { table.hostLog.events.contains(.back(seat: 1)) }
        await eventually("and he has her") { log.events.contains(.back(seat: 0)) }
        try await guest.send(7)
        await eventually("play goes on") { table.host.match?.numbers == [4, 7] }
    }

    @Test func theCreatorClosesTheAppAndIsInChargeAgain() async throws {
        let table = await seated()
        try await table.host.send(4)
        await eventually("first move") { table.guest.match?.numbers == [4] }
        let kept = try closeApp(table.host, table.hostLink)
        await eventually("Kofi sees her reconnecting") { table.guestLog.events.contains(.reconnecting(seat: 0)) }
        // He plays while she is away: held until she is back.
        try await table.guest.send(7)

        let (host, link, log) = openApp(kept)
        await eventually("her seat at the relay") { isOpen(link) }
        #expect(link.me == Relay.creator)
        await eventually("Kofi is back in his seat") { log.events.contains(.back(seat: 1)) }
        await eventually("his move reaches her") { host.match?.numbers == [4, 7] }
        try await host.send(9)
        await eventually("and hers reaches him") { table.guest.match?.numbers == [4, 7, 9] }
    }

    @Test func bothCloseTheAppAndTheGameGoesOnWhenBothAreBack() async throws {
        let table = await seated()
        try await table.host.send(4)
        await eventually("first move") { table.guest.match?.numbers == [4] }
        let hers = try closeApp(table.host, table.hostLink), his = try closeApp(table.guest, table.guestLink)

        // He is back first, and waits in the room.
        let (guest, guestLink, guestLog) = openApp(his)
        await eventually("his seat at the relay") { isOpen(guestLink) }
        #expect(guest.seats[0]?.isReconnecting == true)
        let (host, _, hostLog) = openApp(hers)
        await eventually("she has him") { hostLog.events.contains(.back(seat: 1)) }
        await eventually("he has her") { guestLog.events.contains(.back(seat: 0)) }
        try await guest.send(7)
        await eventually("play goes on") { host.match?.numbers == [4, 7] && guest.match?.numbers == [4, 7] }
    }

    /// The relay inside the app is new each time the app starts: it is given the room again.
    @Test func theRelayInTheAppCanBeGivenARoomAgain() async throws {
        let fresh = LocalRelay()
        await fresh.restore(code: "K7M2QD", game: Self.game, tokens: ["mine", "hers"])
        let exists = await fresh.hasRoom("K7M2QD")
        #expect(exists)
        let seat = OnlineTransport.Seat(code: "K7M2QD", peer: Relay.creator, token: "mine")
        let link = OnlineTransport(entry: .rejoin(seat), install: "x", dial: fresh.dial, sleep: Self.noSleep)
        await eventually("in") { isOpen(link) }
        let other = OnlineTransport(entry: .rejoin(.init(code: "K7M2QD", peer: PeerID("p1"), token: "hers")), install: "y",
                                    dial: fresh.dial, sleep: Self.noSleep)
        await eventually("the other too") { isOpen(other) }
        #expect(other.me == PeerID("p1"))
        // Giving it again changes nothing for phones already in it.
        await fresh.restore(code: "K7M2QD", game: Self.game, tokens: ["mine", "hers"])
        #expect(isOpen(link))
    }

    // MARK: Asking someone played before

    static let ama = RelayPlayer(id: "7c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f", secret: "amas-secret", game: "sum")
    static let kofi = RelayPlayer(id: "1a2b3c4d5e6f708192a3b4c5d6e7f809", secret: "kofis-secret", game: "sum")
    static let push = RelayRequest.Push(token: "9f1c2a7b3d4e5f60", env: .sandbox)

    /// Kofi's phone can be notified: it has told the relay who it is and where notifications go.
    private func kofiRegisters(push: RelayRequest.Push? = push) async {
        let answer = await RelayCall.ask(.register(game: "sum", player: Self.kofi.id, secret: Self.kofi.secret, push: push), dial: relay.dial)
        #expect(answer == .registered)
    }

    @Test func someonePlayedBeforeIsInvitedToTheGameJustStarted() async {
        await kofiRegisters()
        let link = create()
        await eventually("open") { isOpen(link) }
        let answer = await link.invite(Self.kofi.id, name: "Ama", from: Self.ama, push: nil)
        #expect(answer == .sent)
        let sent = await relay.invitations
        #expect(sent == [.init(code: "K7M2QD", from: Self.ama.id, name: "Ama", to: Self.kofi.id)],
                "his phone is given the code, and who asks")
        link.close()
    }

    @Test func someoneWhoCannotBeNotifiedIsUnreachable() async {
        let link = create()
        await eventually("open") { isOpen(link) }
        // Never heard of.
        var answer = await link.invite(Self.kofi.id, name: "Ama", from: Self.ama, push: nil)
        #expect(answer == .refused(.unreachable))
        // Known, but notifications are off on his phone.
        await kofiRegisters(push: nil)
        answer = await link.invite(Self.kofi.id, name: "Ama", from: Self.ama, push: nil)
        #expect(answer == .refused(.unreachable))
        let sent = await relay.invitations
        #expect(sent.isEmpty)
        link.close()
    }

    @Test func aBlockedPlayerIsToldOnlyThatTheOtherCannotBeReached() async {
        await kofiRegisters()
        let blocked = await RelayCall.ask(.block(game: "sum", player: Self.kofi.id, secret: Self.kofi.secret, who: Self.ama.id, on: true),
                                          dial: relay.dial)
        #expect(blocked == .blocked(who: Self.ama.id, on: true))
        let link = create()
        await eventually("open") { isOpen(link) }
        var answer = await link.invite(Self.kofi.id, name: "Ama", from: Self.ama, push: nil)
        #expect(answer == .refused(.unreachable), "the same answer as for someone never heard of")

        // He changes his mind.
        _ = await RelayCall.ask(.block(game: "sum", player: Self.kofi.id, secret: Self.kofi.secret, who: Self.ama.id, on: false), dial: relay.dial)
        answer = await link.invite(Self.kofi.id, name: "Ama", from: Self.ama, push: nil)
        #expect(answer == .sent)
        link.close()
    }

    @Test func aBlockNeedsThePlayersOwnSecret() async {
        await kofiRegisters()
        let answer = await RelayCall.ask(.block(game: "sum", player: Self.kofi.id, secret: "a guess", who: Self.ama.id, on: true), dial: relay.dial)
        #expect(answer == .refused(.invalid))
        // Nor can someone else take his player number.
        let taken = await RelayCall.ask(.register(game: "sum", player: Self.kofi.id, secret: "a guess", push: Self.push), dial: relay.dial)
        #expect(taken == .refused(.invalid))
    }

    @Test func onlyThePhoneThatMadeTheGameInvitesToIt() async {
        await kofiRegisters()
        let table = await seated()
        let answer = await table.guestLink.invite(Self.kofi.id, name: "Kofi", from: Self.ama, push: nil)
        #expect(answer == .refused(.invalid))
        // And nobody is invited before there is a game.
        let early = create()
        early.close()
        let none = await early.invite(Self.kofi.id, name: "Ama", from: Self.ama, push: nil)
        #expect(none == .noAnswer)
    }

    @Test func notNowReachesThePhoneThatIsWaiting() async {
        await kofiRegisters()
        let link = create()
        await eventually("open") { isOpen(link) }
        _ = await link.invite(Self.kofi.id, name: "Ama", from: Self.ama, push: nil)
        var declines = link.declines.makeAsyncIterator()
        await RelayCall.tell(.decline(code: "K7M2QD", player: Self.kofi.id), dial: relay.dial)
        let who = await declines.next()
        #expect(who == Self.kofi.id)
        link.close()
    }

    @Test func aGameThatHasClosedHasEndedAndIsNotAWrongCode() async {
        let table = await seated()
        await table.host.leave()
        await eventually("the room is closed") { await !relay.hasRoom("K7M2QD") }
        let late = join(install: "yaw")
        await eventually("refused") { late.status == .refused(.ended) }
    }

    // MARK: Leaving

    @Test func whenTheCreatorLeavesTheOtherIsToldAndTheRoomCloses() async {
        let table = await seated()
        await table.host.leave()
        await eventually("Kofi is told") { table.guestLog.events.contains(.left(seat: 0)) }
        await eventually("the room is closed") { await !relay.hasRoom("K7M2QD") }
    }

    /// The room's own goodbye can be lost (it races the relay's `leave`): the relay's word that a
    /// phone left on purpose is enough. Nobody is left watching "Reconnecting".
    @Test func aCreatorWhoLeftIsSeenToLeaveThoughItsGoodbyeWasLost() async {
        let table = await seated()
        table.host.stop()   // the relay is told; the room says nothing
        await eventually("Kofi is told she left") { table.guestLog.events.contains(.left(seat: 0)) }
        #expect(!table.guestLog.events.contains(.reconnecting(seat: 0)))
    }

    @Test func aGuestWhoLeftIsSeenToLeaveThoughItsGoodbyeWasLost() async {
        let table = await seated()
        table.guest.stop()
        await eventually("Ama is told he left") { table.hostLog.events.contains(.left(seat: 1)) }
        #expect(!table.hostLog.events.contains(.reconnecting(seat: 1)))
    }

    /// Someone who leaves before the game and comes straight back holds the same place at the
    /// relay: they are heard as someone new, not ignored as the one who left.
    @Test func aGuestWhoLeftCanComeStraightBack() async {
        let table = await seated()
        await table.guest.leave()
        await eventually("Ama is told") { table.hostLog.events.contains(.left(seat: 1)) }
        let again = join()
        let guest = SumRoom(joiningAs: "Kofi", rules: SumRules(), transport: again, clock: clock, timing: .online)
        await eventually("Kofi asks again") { !table.host.pending.isEmpty }
        await table.host.accept(table.host.pending.keys.first!)
        await eventually("and is seated") { guest.mySeat == 1 }
    }

    @Test func leavingIsToldOnceWhenBothGoodbyesArrive() async {
        let table = await seated()
        await table.host.leave()
        await eventually("Kofi is told") { table.guestLog.events.contains(.left(seat: 0)) }
        await settle()
        #expect(table.guestLog.events.filter { $0 == .left(seat: 0) }.count == 1)
    }

    @Test func whenTheGuestLeavesTheCreatorIsTold() async {
        let table = await seated()
        await table.guest.leave()
        await eventually("Ama is told") { table.hostLog.events.contains(.left(seat: 1)) }
        let stillThere = await relay.hasRoom("K7M2QD")
        #expect(stillThere, "her room is still there for someone else")
    }

    // MARK: Four phones

    /// In a four-seat room the guests never hear each other: each talks only to the phone in charge.
    @Test func guestsSeeOnlyThePhoneInCharge() async throws {
        let host = create(seats: 4)
        await eventually("open") { isOpen(host) }
        let kofi = join(install: "kofi"), yaw = join(install: "yaw"), esi = join(install: "esi")
        for link in [kofi, yaw, esi] { await eventually("joined") { isOpen(link) } }
        #expect(Set([kofi, yaw, esi].map(\.me.raw)) == ["p1", "p2", "p3"])

        var heardByYaw: [TransportEvent] = []
        let listening = Task { for await event in yaw.events { heardByYaw.append(event) } }
        try await kofi.send(Data("from kofi".utf8), to: nil)
        try await host.send(Data("from ama".utf8), to: nil)
        await eventually("Yaw hears Ama") { heardByYaw.contains { if case .received = $0 { true } else { false } } }
        await settle()
        listening.cancel()
        for event in heardByYaw {
            switch event {
            case let .connected(peer), let .disconnected(peer), let .left(peer), let .received(_, peer):
                #expect(peer == Relay.creator)
            }
        }
        [host, kofi, yaw, esi].forEach { $0.close() }
    }

    // MARK: Is it there

    /// What an app asks when it opens: is online play there, and is this game open?
    @Test func theRelaySaysWhetherAGameIsOpen() async {
        #expect(await RelayCall.ask(.health(game: "oware"), dial: relay.dial) == .health(open: true))
        await relay.setPaused(true)
        #expect(await RelayCall.ask(.health(game: "oware"), dial: relay.dial) == .health(open: false))
        await relay.setPaused(false)
        await relay.setReachable(false)
        #expect(await RelayCall.ask(.health(game: "oware"), dial: relay.dial, wait: 0.2) == nil, "down: no answer")
        await relay.setReachable(true)
    }

    // MARK: Limits

    @Test func aMessageTooLargeForTheRelayIsNotSent() async {
        let link = create()
        await eventually("open") { isOpen(link) }
        let big = Data(String(repeating: "x", count: Relay.maxFrameBytes).utf8)
        await #expect(throws: Framer.Failure.self) { try await link.send(big, to: nil) }
        link.close()
    }
}

#if canImport(Darwin)
/// The same game through a real relay: `RELAY_URL=ws://localhost:8787 swift test` with
/// `npm run dev` running in the AWS repo's `apps/lelu-play`, or a deployed stage's address.
@MainActor
@Suite("Through a real relay", .enabled(if: ProcessInfo.processInfo.environment["RELAY_URL"] != nil))
struct LiveRelayTests {
    @Test func twoPhonesPlayAndOneReconnects() async throws {
        let url = try #require(URL(string: ProcessInfo.processInfo.environment["RELAY_URL"] ?? ""))
        let game = RelayRequest.Game(name: "oware", protocolVersion: MatchKit.protocolVersion, formatVersion: 2)
        let hostLink = OnlineTransport(entry: .create(game: game, seats: 2, proof: nil), install: UUID().uuidString,
                                       dial: OnlineTransport.dial(url), retryDelays: [0.2])
        let host = SumRoom(hosting: Sum(), name: "Ama", rules: SumRules(), transport: hostLink, timing: .online)
        func longer(_ what: Comment, _ condition: () -> Bool) async {
            for _ in 0..<2_000 {
                if condition() { return }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            Issue.record("timed out waiting: \(what)")
        }
        await longer("the room is made") { hostLink.seat != nil }
        let code = try #require(RoomCode(hostLink.seat?.code ?? ""), "the relay's code is one a player can type")
        let guestLink = OnlineTransport(entry: .join(code: code, game: game), install: UUID().uuidString,
                                        dial: OnlineTransport.dial(url), retryDelays: [0.2])
        let guest = SumRoom(joiningAs: "Kofi", rules: SumRules(), transport: guestLink, timing: .online)
        let log = Log()
        guest.onEvent = { log.events.append($0) }
        await longer("Kofi asks") { !host.pending.isEmpty }
        await host.accept(host.pending.keys.first!)
        await longer("seated") { guest.mySeat == 1 }
        try await host.send(4)
        await longer("first move") { guest.match?.numbers == [4] }

        guestLink.dropConnection()
        await longer("Kofi's phone notices") { log.events.contains(.reconnecting(seat: 0)) }
        await longer("and is back in his seat") { log.events.contains(.back(seat: 0)) }
        try await guest.send(7)
        await longer("his move after reconnecting") { host.match?.numbers == [4, 7] }
        await longer("comes back to him") { guest.match?.numbers == [4, 7] }
        await guest.leave()
        await host.leave()
    }
}
#endif
