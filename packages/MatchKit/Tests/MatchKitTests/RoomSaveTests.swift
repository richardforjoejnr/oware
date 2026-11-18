import Foundation
import Testing
@testable import MatchKit

/// A game that survives the app closing (docs/ONLINE_PLAY.md §5): a room keeps a silent seat when
/// its timing says so, and a phone carries on from what it saved.
@MainActor
@Suite("Rooms that carry on after the app was closed")
struct RoomSaveTests {
    private func eventually(_ what: Comment, _ condition: () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("timed out waiting: \(what)")
    }

    private func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    @MainActor final class Log {
        var events: [RoomEvent<Tally>] = []
    }

    /// Patient, like online play: the seat is kept after `lostAfter`.
    static let keeping = RoomTiming(heartbeatInterval: 2, quietAfter: 4, lostAfter: 15, keepsSeats: true)

    @MainActor private struct Pair {
        let clock = ManualClock()
        let hostLink = LoopbackTransport(me: PeerID("p0"))
        let guestLink = LoopbackTransport(me: PeerID("p1"))
        let host: TallyRoom
        let guest: TallyRoom
        let hostLog = Log()
        let guestLog = Log()

        @MainActor init(timing: RoomTiming) {
            host = TallyRoom(hosting: Tally(), name: "Ama", rules: TallyRules(), transport: hostLink, clock: clock, timing: timing)
            guest = TallyRoom(joiningAs: "Kofi", rules: TallyRules(), transport: guestLink, clock: clock, timing: timing)
            host.onEvent = { [hostLog] in hostLog.events.append($0) }
            guest.onEvent = { [guestLog] in guestLog.events.append($0) }
            hostLink.connect(guestLink)
        }
    }

    /// Ama in charge, Kofi seated, one number each.
    private func playing(timing: RoomTiming = keeping) async throws -> Pair {
        let pair = Pair(timing: timing)
        await eventually("Kofi asks") { !pair.host.pending.isEmpty }
        await pair.host.accept(pair.host.pending.keys.first!)
        await eventually("Kofi seated") { pair.guest.mySeat == 1 }
        try await pair.host.send(.add(1))
        try await pair.guest.send(.add(2))
        await eventually("both have two numbers") { pair.host.match?.numbers == [1, 2] && pair.guest.match?.numbers == [1, 2] }
        return pair
    }

    // MARK: The seat is kept

    @Test func onlineTimingKeepsSeatsAndNearbyDoesNot() {
        #expect(RoomTiming.online.keepsSeats)
        #expect(!RoomTiming.nearby.keepsSeats)
    }

    @Test func aSeatSilentTooLongIsReportedButKept() async throws {
        let pair = try await playing()
        pair.guestLink.isQuiet = true
        pair.clock.advance(by: 16)
        await pair.host.tick()
        #expect(pair.hostLog.events.contains(.seatLost(seat: 1)), "the player is asked what to do")
        #expect(pair.host.seats[1]?.name == "Kofi", "the seat is still his")
        #expect(pair.host.seats[1]?.isReconnecting == true)

        // He comes back minutes later, on the same connection: the game carries on.
        pair.clock.advance(by: 300)
        pair.guestLink.isQuiet = false
        await pair.guest.tick()
        await eventually("Kofi is back") { pair.hostLog.events.contains(.back(seat: 1)) }
        try await pair.host.send(.add(3))
        await eventually("he gets the next number") { pair.guest.match?.numbers == [1, 2, 3] }
    }

    @Test func aKeptSeatIsReportedAgainAfterAnotherWait() async throws {
        let pair = try await playing()
        pair.guestLink.isQuiet = true
        pair.clock.advance(by: 16)
        await pair.host.tick()
        pair.clock.advance(by: 5)
        await pair.host.tick()
        #expect(pair.hostLog.events.filter { $0 == .seatLost(seat: 1) }.count == 1, "not on every ping")
        pair.clock.advance(by: 11)
        await pair.host.tick()
        #expect(pair.hostLog.events.filter { $0 == .seatLost(seat: 1) }.count == 2, "asked again after as long again")
    }

    @Test func aGuestKeepsItsSeatWhenThePhoneInChargeIsSilentTooLong() async throws {
        let pair = try await playing()
        pair.hostLink.isQuiet = true
        pair.clock.advance(by: 16)
        await pair.guest.tick()
        #expect(pair.guestLog.events.contains(.seatLost(seat: 0)))
        #expect(pair.guest.seats[0]?.name == "Ama")

        pair.hostLink.isQuiet = false
        await pair.host.tick()
        await eventually("Ama is back") { pair.guestLog.events.contains(.back(seat: 0)) }
    }

    @Test func nearbyTimingStillGivesTheSeatUp() async throws {
        let pair = try await playing(timing: .nearby)
        pair.guestLink.isQuiet = true
        pair.clock.advance(by: 16)
        await pair.host.tick()
        #expect(pair.hostLog.events.contains(.seatLost(seat: 1)))
        #expect(pair.host.seats[1] == nil)
    }

    // MARK: Carrying on from a save

    @Test func aRoomHasNothingToSaveUntilItHasASeat() {
        let guest = TallyRoom(joiningAs: "Kofi", rules: TallyRules(), transport: LoopbackTransport())
        #expect(guest.save == nil)
    }

    @Test func theSaveHoldsTheSeatTheNamesAndTheTokens() async throws {
        let pair = try await playing()
        let hosts = try #require(pair.host.save), guests = try #require(pair.guest.save)
        #expect(hosts.seat == 0 && guests.seat == 1)
        #expect(hosts.names == [0: "Ama", 1: "Kofi"] && guests.names == hosts.names)
        #expect(guests.tokens.count == 1)
        #expect(hosts.tokens[1] == guests.tokens[1], "the phone in charge knows the token it gave out")
        let again = try JSONDecoder().decode(RoomSave.self, from: JSONEncoder().encode(hosts))
        #expect(again == hosts)
    }

    @Test func thePhoneInChargeCarriesOnFromItsSave() async throws {
        let pair = try await playing()
        let save = try #require(pair.host.save), match = try #require(pair.host.match)
        // Ama's app is closed: her connection goes without a goodbye.
        pair.hostLink.drop()
        await eventually("Kofi sees her go quiet") { pair.guestLog.events.contains(.reconnecting(seat: 0)) }

        // She opens it again: a new room from the save, on a new connection with the same name.
        let newLink = LoopbackTransport(me: PeerID("p0"))
        let log = Log()
        let host = TallyRoom(resuming: save, match: match, rules: TallyRules(), transport: newLink, clock: pair.clock, timing: Self.keeping)
        host.onEvent = { log.events.append($0) }
        #expect(host.role == .host && host.mySeat == 0)
        #expect(host.name == "Ama")
        #expect(host.match?.numbers == [1, 2])
        #expect(host.seats[1]?.name == "Kofi")
        #expect(host.seats[1]?.isReconnecting == true, "not heard from yet")

        newLink.connect(pair.guestLink)
        await eventually("Kofi is back in his seat") { log.events.contains(.back(seat: 1)) }
        await eventually("and has her back") { pair.guestLog.events.contains(.back(seat: 0)) }
        #expect(!log.events.contains { if case .joinRequest = $0 { true } else { false } }, "he is not asked to join again")

        try await host.send(.add(3))
        await eventually("the game goes on") { pair.guest.match?.numbers == [1, 2, 3] }
        try await pair.guest.send(.add(4))
        await eventually("both ways") { host.match?.numbers == [1, 2, 3, 4] }
    }

    @Test func aGuestCarriesOnFromItsSave() async throws {
        let pair = try await playing()
        let save = try #require(pair.guest.save), match = try #require(pair.guest.match)
        pair.guestLink.drop()
        await eventually("Ama sees him go quiet") { pair.hostLog.events.contains(.reconnecting(seat: 1)) }
        // She plays on while he is away.
        try await pair.host.send(.add(3))

        let newLink = LoopbackTransport(me: PeerID("p1"))
        let log = Log()
        let guest = TallyRoom(resuming: save, match: match, rules: TallyRules(), transport: newLink, clock: pair.clock, timing: Self.keeping)
        guest.onEvent = { log.events.append($0) }
        #expect(guest.role == .guest && guest.mySeat == 1)
        #expect(guest.match?.numbers == [1, 2], "the match as he saved it, until she answers")
        #expect(guest.seats[0]?.isReconnecting == true)

        pair.hostLink.connect(newLink)
        await eventually("he has his seat back") { pair.hostLog.events.contains(.back(seat: 1)) }
        await eventually("and catches up") { guest.match?.numbers == [1, 2, 3] }
        #expect(log.events.contains(.back(seat: 0)))
        #expect(!log.events.contains { if case .refused = $0 { true } else { false } })
        #expect(pair.host.pending.isEmpty, "he is let straight back in")

        try await guest.send(.add(4))
        await eventually("his move is taken") { pair.host.match?.numbers == [1, 2, 3, 4] }
    }

    @Test func aMoveMadeBeforeTheOtherPhoneIsBackIsSentOnceItIs() async throws {
        let pair = try await playing()
        let save = try #require(pair.guest.save)
        pair.guestLink.drop()
        try await pair.host.send(.add(3))
        var match = try #require(pair.guest.match)
        match.numbers = [1, 2, 3]

        let newLink = LoopbackTransport(me: PeerID("p1"))
        let guest = TallyRoom(resuming: save, match: match, rules: TallyRules(), transport: newLink, clock: pair.clock, timing: Self.keeping)
        try await guest.send(.add(4))
        await settle()
        #expect(pair.host.match?.numbers == [1, 2, 3], "nowhere to send it yet")
        pair.hostLink.connect(newLink)
        await eventually("sent when she has him back") { pair.host.match?.numbers == [1, 2, 3, 4] }
    }

    /// The other phone was never told this one went (it stayed in the game): its count of this
    /// phone's messages is high, and a room starting again from 1 would be taken for old news.
    @Test func aRoomCarryingOnIsHeardByAPhoneThatNeverSawItGo() async throws {
        let pair = try await playing()
        for _ in 0..<80 { await pair.host.tick() }
        let save = try #require(pair.host.save), match = try #require(pair.host.match)
        pair.hostLink.isQuiet = true   // gone, and Kofi's phone is told nothing

        let newLink = LoopbackTransport(me: PeerID("p0"))
        let host = TallyRoom(resuming: save, match: match, rules: TallyRules(), transport: newLink, clock: pair.clock, timing: Self.keeping)
        newLink.connect(pair.guestLink)
        await eventually("Kofi asks for his seat on the new connection") { host.seats[1]?.isReconnecting == false }
        try await host.send(.add(3))
        await eventually("and hears her") { pair.guest.match?.numbers == [1, 2, 3] }
    }

    @Test func aTokenFromAnotherGameIsNotLetIn() async throws {
        let pair = try await playing()
        var save = try #require(pair.guest.save)
        save.tokens[1] = UUID()
        pair.guestLink.drop()
        let newLink = LoopbackTransport(me: PeerID("p1"))
        let log = Log()
        let stranger = TallyRoom(resuming: save, match: Tally(), rules: TallyRules(), transport: newLink, clock: pair.clock, timing: Self.keeping)
        stranger.onEvent = { log.events.append($0) }
        pair.hostLink.connect(newLink)
        await eventually("refused: the seat is Kofi's") { log.events.contains(.refused(.roomFull)) }
    }

    // MARK: An intent this version does not know

    /// A newer app may ask for something this one has no word for (a later kind of intent). The
    /// message is dropped: nothing changes and nothing breaks, and the game goes on.
    @Test func anIntentThisPhoneCannotReadIsDropped() async throws {
        let pair = try await playing()
        let unknown = #"{"protocolVersion":2,"sequence":900,"body":{"type":"intent","intent":{"somethingNew":{}}}}"#
        try await pair.guestLink.send(Data(unknown.utf8), to: PeerID("p0"))
        await settle()
        #expect(pair.host.match?.numbers == [1, 2])
        try await pair.host.send(.add(3))
        try await pair.guest.send(.add(4))
        await eventually("the game goes on") { pair.host.match?.numbers == [1, 2, 3, 4] }
    }

    // MARK: Player numbers

    /// Each phone tells the other its player number once seated, so either can ask the other
    /// for another game later (docs/ONLINE_PLAY.md §6).
    @Test func phonesTellEachOtherTheirPlayerNumbers() async throws {
        let pair = Pair(timing: Self.keeping)
        pair.host.player = "aaaa"
        pair.guest.player = "bbbb"
        var heard: [Int: String] = [:]
        pair.host.onPlayer = { heard[$0] = $1 }
        await eventually("Kofi asks") { !pair.host.pending.isEmpty }
        await pair.host.accept(pair.host.pending.keys.first!)
        await eventually("each knows the other's") { pair.host.players[1] == "bbbb" && pair.guest.players[0] == "aaaa" }
        #expect(heard == [1: "bbbb"])
    }

    @Test func aPhoneWithNoPlayerNumberSaysNothing() async throws {
        let pair = try await playing()
        await settle()
        #expect(pair.host.players.isEmpty && pair.guest.players.isEmpty)
    }

    @Test func playerNumbersAreToldAgainToARoomCarryingOn() async throws {
        let pair = try await playing()
        pair.guest.player = "bbbb"
        let save = try #require(pair.host.save), match = try #require(pair.host.match)
        pair.hostLink.drop()
        let newLink = LoopbackTransport(me: PeerID("p0"))
        let host = TallyRoom(resuming: save, match: match, rules: TallyRules(), transport: newLink, clock: pair.clock, timing: Self.keeping)
        host.player = "aaaa"
        newLink.connect(pair.guestLink)
        await eventually("each knows the other's") { host.players[1] == "bbbb" && pair.guest.players[0] == "aaaa" }
    }

    @Test func somethingTooLongToBeAPlayerNumberIsNotKept() async throws {
        let pair = try await playing()
        let long = String(repeating: "a", count: 65)
        let message = #"{"protocolVersion":2,"sequence":900,"body":{"type":"player","player":"\#(long)"}}"#
        try await pair.guestLink.send(Data(message.utf8), to: PeerID("p0"))
        await settle()
        #expect(pair.host.players.isEmpty)
    }
}
