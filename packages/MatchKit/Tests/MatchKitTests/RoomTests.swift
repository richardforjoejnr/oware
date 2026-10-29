import Foundation
import Testing
@testable import MatchKit

/// A tiny game for testing rooms: players take turns adding numbers. Seat 0 moves first.
struct Tally: Codable, Sendable, Equatable {
    var game = 1
    var numbers: [Int] = []
    var note = ""
}

enum TallyIntent: Codable, Sendable, Equatable {
    case add(Int)
    /// Any seat, any time: a small message that makes the match `bytes` larger, too large to send.
    case grow(bytes: Int)
}

struct TallyRules: RoomRules {
    struct NotYourTurn: Error {}
    let seatCount = 2

    func applying(_ intent: TallyIntent, from seat: Int, to match: Tally) throws -> Tally {
        var next = match
        switch intent {
        case let .add(n):
            guard seat == match.numbers.count % seatCount else { throw NotYourTurn() }
            next.numbers.append(n)
        case let .grow(bytes):
            next.note = String(repeating: "x", count: bytes)
        }
        return next
    }

    func shouldReplace(_ current: Tally, with snapshot: Tally) -> Bool {
        snapshot.game > current.game
            || (snapshot.game == current.game && snapshot.numbers.count > current.numbers.count
                && snapshot.numbers.starts(with: current.numbers))
    }
}

typealias TallyRoom = Room<TallyRules>

@MainActor
@Suite("Rooms on the in-memory transport")
struct RoomTests {
    /// Lets the rooms' listening tasks run until `condition` holds.
    private func eventually(_ what: Comment, _ condition: () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("timed out waiting: \(what)")
    }

    /// Lets queued messages arrive, for checking that something did *not* happen.
    private func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    @MainActor private struct Table {
        let clock = ManualClock()
        let hostLink = LoopbackTransport()
        let host: TallyRoom
        var hostEvents: [RoomEvent<Tally>] { hostLog.events }
        let hostLog = EventLog()

        @MainActor init() {
            host = TallyRoom(hosting: Tally(), name: "Kofi", rules: TallyRules(), transport: hostLink, clock: clock)
            host.onEvent = { [hostLog] in hostLog.events.append($0) }
        }

        /// A guest who has connected and said hello, not yet accepted.
        @MainActor func guest(_ name: String, protocolVersion: Int = MatchKit.protocolVersion) -> (TallyRoom, LoopbackTransport, EventLog) {
            let link = LoopbackTransport()
            let log = EventLog()
            let room = TallyRoom(joiningAs: name, rules: TallyRules(), transport: link, clock: clock, protocolVersion: protocolVersion)
            room.onEvent = { log.events.append($0) }
            hostLink.connect(link)
            return (room, link, log)
        }
    }

    @MainActor final class EventLog {
        var events: [RoomEvent<Tally>] = []
    }

    /// A host and a seated guest.
    private func seated() async -> (Table, TallyRoom, LoopbackTransport, EventLog) {
        let table = Table()
        let (guest, link, log) = table.guest("Ama")
        await eventually("join request") { table.host.pending.values.contains("Ama") }
        let peer = table.host.pending.first { $0.value == "Ama" }!.key
        await table.host.accept(peer)
        await eventually("guest seated") { guest.mySeat == 1 && guest.match != nil }
        return (table, guest, link, log)
    }

    // MARK: Joining

    @Test func theHostIsAskedAndAccepts() async {
        let table = Table()
        let (guest, _, log) = table.guest("Ama")
        await eventually("join request") { table.hostEvents.contains { if case .joinRequest(_, "Ama") = $0 { true } else { false } } }
        #expect(guest.mySeat == nil, "nobody is seated before the host says yes")

        await table.host.accept(table.host.pending.keys.first!)
        await eventually("welcome") { guest.mySeat == 1 }
        #expect(guest.match == Tally())
        #expect(guest.seats[0]?.name == "Kofi" && guest.seats[1]?.name == "Ama")
        #expect(table.host.seats[1]?.name == "Ama")
        #expect(table.hostEvents.contains(.seated(seat: 1, name: "Ama")))
        #expect(log.events.contains(.seated(seat: 1, name: "Ama")))
        #expect(table.host.pending.isEmpty)
    }

    @Test func theHostCanSayNo() async {
        let table = Table()
        let (guest, _, log) = table.guest("Ama")
        await eventually("join request") { !table.host.pending.isEmpty }
        await table.host.decline(table.host.pending.keys.first!)
        await eventually("refusal") { log.events.contains(.refused(.declined)) }
        #expect(guest.mySeat == nil)
        #expect(table.host.seats[1] == nil)
    }

    @Test func aSecondGuestIsToldTheRoomIsFull() async {
        let (table, _, _, _) = await seated()
        let (late, _, log) = table.guest("Yaw")
        await eventually("refusal") { log.events.contains(.refused(.roomFull)) }
        #expect(late.mySeat == nil)
        #expect(table.host.pending.isEmpty, "the host is not even asked")
    }

    @Test func twoAskingAtOnceTheSecondIsRefusedWhenTheFirstIsAccepted() async {
        let table = Table()
        let (amaRoom, _, _) = table.guest("Ama")
        let (yawRoom, _, yawLog) = table.guest("Yaw")
        defer { withExtendedLifetime((amaRoom, yawRoom)) {} }
        await eventually("two requests") { table.host.pending.count == 2 }
        let ama = table.host.pending.first { $0.value == "Ama" }!.key
        await table.host.accept(ama)
        await eventually("Yaw refused") { yawLog.events.contains(.refused(.roomFull)) }
        #expect(table.host.pending.isEmpty)
    }

    @Test func aNewerAppIsToldToWaitForTheOtherToUpdate() async {
        let table = Table()
        let (guest, _, log) = table.guest("Ama", protocolVersion: MatchKit.protocolVersion + 1)
        await eventually("refusal") { log.events.contains(.refused(.needsUpdate(hostVersion: MatchKit.protocolVersion))) }
        #expect(guest.mySeat == nil)
        #expect(table.host.pending.isEmpty, "the host is not asked about a phone it cannot talk to")
    }

    @Test func anOlderGuestRefusesANewerHost() async {
        let clock = ManualClock()
        let hostLink = LoopbackTransport()
        let host = TallyRoom(hosting: Tally(), name: "Kofi", rules: TallyRules(), transport: hostLink, clock: clock,
                             protocolVersion: MatchKit.protocolVersion + 1)
        let link = LoopbackTransport()
        let log = EventLog()
        let guest = TallyRoom(joiningAs: "Ama", rules: TallyRules(), transport: link, clock: clock)
        guest.onEvent = { log.events.append($0) }
        hostLink.connect(link)
        await eventually("join request") { !host.pending.isEmpty }
        await host.accept(host.pending.keys.first!)
        await eventually("refusal") { log.events.contains(.refused(.needsUpdate(hostVersion: MatchKit.protocolVersion + 1))) }
        #expect(guest.mySeat == nil && guest.match == nil)
    }

    // MARK: Play

    @Test func intentsGoToTheHostAndSnapshotsComeBack() async throws {
        let (table, guest, _, log) = await seated()
        try await table.host.send(.add(5))   // seat 0 moves first
        await eventually("guest sees the host's move") { guest.match?.numbers == [5] }

        try await guest.send(.add(7))
        await eventually("host applies the guest's move") { table.host.match?.numbers == [5, 7] }
        await eventually("guest sees its own move only once the host agrees") { guest.match?.numbers == [5, 7] }
        #expect(log.events.filter { if case .snapshot = $0 { true } else { false } }.count >= 2)
    }

    @Test func theHostRefusesAMoveOutOfTurn() async throws {
        let (table, guest, _, _) = await seated()
        try await guest.send(.add(9))   // seat 0 is to move
        await settle()
        #expect(table.host.match?.numbers == [])
        #expect(guest.match?.numbers == [])
        await #expect(throws: TallyRules.NotYourTurn.self) {
            try await table.host.send(.add(1))
            try await table.host.send(.add(2))   // now seat 1 is to move
        }
    }

    @Test func aGuestsSnapshotIsIgnored() async throws {
        let (table, _, link, _) = await seated()
        // A guest (broken, or tampered with) tries to tell the host what the match is.
        let forged = Envelope(protocolVersion: MatchKit.protocolVersion, sequence: 99,
                              body: RoomMessage<Tally, TallyIntent>.snapshot(Tally(numbers: [1, 2, 3])))
        try await link.send(JSONEncoder().encode(forged), to: nil)
        await settle()
        #expect(table.host.match == Tally())
    }

    @Test func messagesTooLargeForOnlineAreNotSent() async throws {
        let (table, guest, _, _) = await seated()
        await #expect(throws: Framer.Failure.self) {
            try await table.host.send(.grow(bytes: Framer.maxMessageBytes))
        }
        #expect(table.host.match == Tally(), "the host keeps the match it can still send")

        // From a guest, the host refuses it the same way.
        try await guest.send(.grow(bytes: Framer.maxMessageBytes))
        await settle()
        #expect(table.host.match == Tally())
    }

    // MARK: Connection

    @Test func silenceMeansReconnectingThenTheSeatEnds() async throws {
        let (table, guest, link, log) = await seated()
        link.isQuiet = true   // the guest walks out of range

        table.clock.advance(by: 5)
        await table.host.tick()
        #expect(table.host.seats[1]?.isReconnecting == false, "5 s of silence is fine")

        table.clock.advance(by: 1.5)
        await table.host.tick()
        #expect(table.host.seats[1]?.isReconnecting == true)
        #expect(table.hostEvents.contains(.reconnecting(seat: 1)))
        await guest.tick()
        #expect(guest.seats[0]?.isReconnecting == true, "the guest sees the host go quiet too")
        #expect(log.events.contains(.reconnecting(seat: 0)))

        table.clock.advance(by: 54)   // 60.5 s in all
        await table.host.tick()
        #expect(table.host.seats[1] == nil)
        #expect(table.hostEvents.contains(.seatLost(seat: 1)))
        await guest.tick()
        #expect(log.events.contains(.seatLost(seat: 0)))
    }

    @Test func pingsKeepAQuietGameAlive() async throws {
        let (table, guest, _, _) = await seated()
        for _ in 0..<40 {   // 80 s with nobody moving
            table.clock.advance(by: 2)
            await guest.tick()
            await table.host.tick()
            await settle()
        }
        #expect(table.host.seats[1]?.isReconnecting == false)
        #expect(guest.seats[0]?.isReconnecting == false)
    }

    /// The host moved while the guest was out of range: when the guest is heard again, the host
    /// sends the match as it stands, or both phones would wait for each other.
    @Test func aGuestBackFromAQuietSpellCatchesUp() async throws {
        let (table, guest, link, log) = await seated()
        link.isQuiet = true
        try await table.host.send(.add(5))   // missed
        table.clock.advance(by: 7)
        await table.host.tick()
        #expect(table.host.seats[1]?.isReconnecting == true)

        link.isQuiet = false
        await guest.tick()   // the guest's ping is heard
        await eventually("the host is back for the guest") { table.hostEvents.contains(.back(seat: 1)) }
        await eventually("the guest has the move it missed") { guest.match?.numbers == [5] }
        #expect(log.events.contains(.snapshot(Tally(numbers: [5]))))
    }

    @Test func rejoiningInTimeGetsTheSameSeatAndTheLatestMatch() async throws {
        let (table, guest, link, log) = await seated()
        link.close()   // the guest's app was in the background and its connection dropped
        await eventually("host notices") { table.host.seats[1]?.isReconnecting == true }

        try await table.host.send(.add(4))   // the host moves while the guest is away
        table.clock.advance(by: 30)
        await table.host.tick()
        #expect(table.host.seats[1] != nil)

        let back = LoopbackTransport()
        guest.reconnect(over: back)
        table.hostLink.connect(back)
        await eventually("same seat, latest match") { guest.match?.numbers == [4] }
        #expect(guest.mySeat == 1)
        #expect(table.host.seats[1]?.isReconnecting == false)
        #expect(table.hostEvents.contains(.back(seat: 1)))
        #expect(table.host.pending.isEmpty, "rejoining does not ask the host again")
        #expect(log.events.contains(.back(seat: 0)) || log.events.contains(.seated(seat: 1, name: "Ama")))

        try await guest.send(.add(8))
        await eventually("play carries on") { table.host.match?.numbers == [4, 8] }
    }

    @Test func rejoiningTooLateAsksAgain() async throws {
        let (table, guest, link, _) = await seated()
        link.close()
        table.clock.advance(by: 61)
        await table.host.tick()
        #expect(table.host.seats[1] == nil)

        let back = LoopbackTransport()
        guest.reconnect(over: back)
        table.hostLink.connect(back)
        await eventually("asked again") { table.host.pending.values.contains("Ama") }
    }

    @Test func leavingEndsTheSeatAtOnce() async throws {
        let (table, guest, _, _) = await seated()
        await guest.leave()
        await eventually("seat ended") { table.host.seats[1] == nil }
        #expect(table.hostEvents.contains(.seatLost(seat: 1)))
    }
}
