import Foundation

/// What a room needs to know about a game: how the host applies an intent, and when a guest
/// takes a snapshot. Each app supplies one (for example over `OwareMatch`).
public protocol RoomRules: Sendable {
    associatedtype Match: Codable & Sendable & Equatable
    associatedtype Intent: Codable & Sendable
    /// Seat 0 is the host.
    var seatCount: Int { get }
    /// The match after `seat` asks for `intent`; throws if the rules refuse it.
    func applying(_ intent: Intent, from seat: Int, to match: Match) throws -> Match
    /// Whether a guest holding `current` should take `snapshot` (later, not stale or repeated).
    func shouldReplace(_ current: Match, with snapshot: Match) -> Bool
}

public enum Refusal: Codable, Sendable, Equatable {
    case roomFull
    case declined
    /// The phones run different versions of the room protocol; whoever is older should update.
    case needsUpdate(hostVersion: Int)
}

public enum RoomMessage<Match: Codable & Sendable, Intent: Codable & Sendable>: Codable, Sendable {
    /// `rejoin` is the token from an earlier `welcome`, to take the same seat back.
    case hello(name: String, rejoin: UUID?)
    case welcome(seat: Int, token: UUID, names: [Int: String], snapshot: Match)
    case refused(Refusal)
    case intent(Intent)
    case snapshot(Match)
    case ping
    case bye
}

public enum RoomEvent<Match: Sendable & Equatable>: Sendable, Equatable {
    /// Host: someone asks to join. Answer with `accept` or `decline`.
    case joinRequest(PeerID, name: String)
    /// A seat was taken: on the host, by a guest; on a guest, its own seat.
    case seated(seat: Int, name: String)
    /// Guest: the host said no, or cannot talk to this phone.
    case refused(Refusal)
    case snapshot(Match)
    /// Nothing heard from that seat for a while.
    case reconnecting(seat: Int)
    case back(seat: Int)
    /// That seat has gone silent too long. On a guest, seat 0 means the host's phone.
    case seatLost(seat: Int)
    /// That seat left on purpose (said goodbye): no point waiting for it.
    case left(seat: Int)
}

/// Seats, the host's checks, snapshots and rejoining, over any transport (docs/MULTIPLAYER.md §2).
///
/// The host is in charge: guests send intents, the host applies them with `RoomRules` and sends
/// everyone the whole match. The host's own moves go through the same path.
@MainActor
public final class Room<Rules: RoomRules> {
    public typealias Match = Rules.Match
    public typealias Intent = Rules.Intent
    typealias Message = RoomMessage<Match, Intent>

    public enum Role: Sendable, Equatable { case host, guest }

    public struct Seat: Sendable, Equatable {
        public var name: String
        public var isReconnecting = false
    }

    /// A ping goes out this often; a seat silent for `quietAfter` is reconnecting, and gone
    /// after `lostAfter` (10 s: the owner found waiting longer for a lost phone too long).
    public static var heartbeatInterval: Double { 2 }
    public static var quietAfter: Double { 4 }
    public static var lostAfter: Double { 10 }

    public let role: Role
    public let rules: Rules
    public let name: String
    public private(set) var match: Match?
    public private(set) var mySeat: Int?
    public private(set) var seats: [Int: Seat] = [:]
    /// Host: people waiting for an answer, by peer.
    public private(set) var pending: [PeerID: String] = [:]
    public var onEvent: (@MainActor (RoomEvent<Match>) -> Void)?

    private var transport: any MatchTransport
    private let clock: any RoomClock
    private let protocolVersion: Int
    private var listener: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var sequence = 0
    private var filter = SequenceFilter()
    private var peerForSeat: [Int: PeerID] = [:]
    private var lastHeard: [Int: Double] = [:]
    /// Host: each guest seat's rejoin token.
    private var tokens: [Int: UUID] = [:]
    /// Guest: the host, and the token to take this seat back.
    private var hostPeer: PeerID?
    private var token: UUID?
    /// Guest: moves sent while not connected to the host, sent once it has us back.
    private var waiting: [Intent] = []
    /// Guest: on a new connection, not yet let back in by the host.
    private var awaitingWelcome = false
    private var stopped = false

    /// Opens a room with the host in seat 0.
    public init(hosting match: Match, name: String, rules: Rules, transport: any MatchTransport,
                clock: any RoomClock = SystemClock(), protocolVersion: Int = MatchKit.protocolVersion) {
        role = .host
        self.rules = rules
        self.name = name
        self.match = match
        self.transport = transport
        self.clock = clock
        self.protocolVersion = protocolVersion
        mySeat = 0
        seats[0] = Seat(name: name)
        listen()
    }

    /// Joins the room at the other end of `transport` once it connects.
    public init(joiningAs name: String, rules: Rules, transport: any MatchTransport,
                clock: any RoomClock = SystemClock(), protocolVersion: Int = MatchKit.protocolVersion) {
        role = .guest
        self.rules = rules
        self.name = name
        self.transport = transport
        self.clock = clock
        self.protocolVersion = protocolVersion
        listen()
    }

    // MARK: - Asking

    /// Host: seats someone who asked. Anyone else waiting is refused once the room is full.
    public func accept(_ peer: PeerID) async {
        guard role == .host, let guestName = pending.removeValue(forKey: peer), let match else { return }
        guard let seat = (1..<rules.seatCount).first(where: { seats[$0] == nil }) else {
            await post(.refused(.roomFull), to: peer)
            return
        }
        let seatToken = UUID()
        tokens[seat] = seatToken
        seats[seat] = Seat(name: guestName)
        peerForSeat[seat] = peer
        lastHeard[seat] = clock.now
        await post(.welcome(seat: seat, token: seatToken, names: names, snapshot: match), to: peer)
        onEvent?(.seated(seat: seat, name: guestName))
        if isFull {
            for other in pending.keys {
                pending[other] = nil
                await post(.refused(.roomFull), to: other)
            }
        }
    }

    public func decline(_ peer: PeerID) async {
        guard role == .host, pending.removeValue(forKey: peer) != nil else { return }
        await post(.refused(.declined), to: peer)
    }

    /// Host: sends away someone already seated, before the game (Not now after letting them in).
    /// They are told no, as if declined, and the seat is free for the next one to ask.
    public func dismiss(seat: Int) async {
        guard role == .host, seat != 0, let peer = peerForSeat[seat] else { return }
        seats[seat] = nil
        tokens[seat] = nil
        peerForSeat[seat] = nil
        lastHeard[seat] = nil
        await post(.refused(.declined), to: peer)
    }

    // MARK: - Playing

    /// Host: applies the intent from seat 0 and sends everyone the result; throws if the rules
    /// refuse it. Guest: sends it to the host, whose snapshot comes back as an event.
    public func send(_ intent: Intent) async throws {
        switch role {
        case .host:
            guard let current = match else { return }
            let next = try rules.applying(intent, from: 0, to: current)
            try checkSize(.snapshot(next))
            match = next
            onEvent?(.snapshot(next))
            await post(.snapshot(next), to: nil)
        case .guest:
            guard let hostPeer, !awaitingWelcome else {
                waiting.append(intent)
                return
            }
            await post(.intent(intent), to: hostPeer)
        }
    }

    /// Host: starts a new match with everyone seated (a rematch both players agreed to).
    public func replaceMatch(with next: Match) async {
        guard role == .host else { return }
        match = next
        onEvent?(.snapshot(next))
        await post(.snapshot(next), to: nil)
    }

    // MARK: - Connection

    /// Sends a ping and checks who has gone quiet. `startHeartbeat()` calls it every 2 s; tests
    /// call it by hand with a `ManualClock`.
    public func tick() async {
        guard !stopped else { return }
        await post(.ping, to: role == .host ? nil : hostPeer)
        let now = clock.now
        for (seat, heard) in lastHeard where seat != mySeat {
            let silence = now - heard
            if silence >= Self.lostAfter {
                lose(seat)
            } else if silence >= Self.quietAfter, seats[seat]?.isReconnecting == false {
                seats[seat]?.isReconnecting = true
                onEvent?(.reconnecting(seat: seat))
            }
        }
    }

    public func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.heartbeatInterval * 1_000_000_000))
                await self?.tick()
            }
        }
    }

    /// Guest: carries on over a new connection to the same host, asking for the same seat.
    public func reconnect(over newTransport: any MatchTransport) {
        guard role == .guest else { return }
        listener?.cancel()
        transport.close()
        transport = newTransport
        hostPeer = nil
        awaitingWelcome = true
        filter = SequenceFilter()
        listen()
    }

    /// Says goodbye and stops.
    public func leave() async {
        await post(.bye, to: role == .host ? nil : hostPeer)
        stop()
    }

    public func stop() {
        stopped = true
        heartbeat?.cancel()
        listener?.cancel()
        transport.close()
    }

    // MARK: - Receiving

    private func listen() {
        let events = transport.events
        listener = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: TransportEvent) async {
        switch event {
        case let .connected(peer):
            if role == .guest, hostPeer == nil {
                hostPeer = peer
                await post(.hello(name: name, rejoin: token), to: peer)
            }
        case let .disconnected(peer):
            pending[peer] = nil
            filter.forget(peer)
            if let seat = seat(of: peer) {
                peerForSeat[seat] = nil
                if seats[seat]?.isReconnecting == false {
                    seats[seat]?.isReconnecting = true
                    onEvent?(.reconnecting(seat: seat))
                }
            }
        case let .received(data, peer):
            await receive(data, from: peer)
        }
    }

    private func receive(_ data: Data, from peer: PeerID) async {
        guard let header = try? JSONDecoder().decode(EnvelopeHeader.self, from: data) else { return }
        if header.protocolVersion > protocolVersion {
            switch role {
            case .host: await post(.refused(.needsUpdate(hostVersion: protocolVersion)), to: peer)
            case .guest: if peer == hostPeer { onEvent?(.refused(.needsUpdate(hostVersion: header.protocolVersion))) }
            }
            return
        }
        guard let envelope = try? JSONDecoder().decode(Envelope<Message>.self, from: data),
              filter.accept(envelope.sequence, from: peer) else { return }
        if let seat = seat(of: peer), heard(seat), role == .host, let match {
            // Back from a quiet spell: it may have missed moves.
            await post(.snapshot(match), to: peer)
        }
        switch role {
        case .host: await hostReceives(envelope.body, from: peer)
        case .guest: if peer == hostPeer { guestReceives(envelope.body) }
        }
    }

    private func hostReceives(_ message: Message, from peer: PeerID) async {
        switch message {
        case let .hello(guestName, rejoin):
            if let rejoin, let seat = tokens.first(where: { $0.value == rejoin })?.key, let match {
                peerForSeat[seat] = peer
                heard(seat)
                await post(.welcome(seat: seat, token: rejoin, names: names, snapshot: match), to: peer)
            } else if isFull {
                await post(.refused(.roomFull), to: peer)
            } else {
                pending[peer] = guestName
                onEvent?(.joinRequest(peer, name: guestName))
            }
        case let .intent(intent):
            guard let seat = seat(of: peer), let current = match else { return }
            if let next = try? rules.applying(intent, from: seat, to: current), (try? checkSize(.snapshot(next))) != nil {
                match = next
                onEvent?(.snapshot(next))
                await post(.snapshot(next), to: nil)
            } else {
                // Refused: send the match as it stands, so the guest's screen catches up.
                await post(.snapshot(current), to: peer)
            }
        case .bye:
            if let seat = seat(of: peer) { lose(seat, left: true) }
        case .snapshot, .welcome, .refused, .ping:
            break   // only the host decides what the match is
        }
    }

    private func guestReceives(_ message: Message) {
        switch message {
        case let .welcome(seat, seatToken, seatNames, snapshot):
            let rejoining = token == seatToken
            mySeat = seat
            token = seatToken
            seats = seatNames.mapValues { Seat(name: $0) }
            heard(0)
            if rejoining { onEvent?(.back(seat: 0)) } else { onEvent?(.seated(seat: seat, name: name)) }
            take(snapshot)
            awaitingWelcome = false
            let held = waiting
            waiting = []
            if let hostPeer { Task { for intent in held { await post(.intent(intent), to: hostPeer) } } }
        case let .refused(refusal):
            onEvent?(.refused(refusal))
        case let .snapshot(snapshot):
            take(snapshot)
        case .bye:
            lose(0, left: true)
        case .hello, .intent, .ping:
            break
        }
    }

    // MARK: - Helpers

    private var isFull: Bool { (1..<rules.seatCount).allSatisfy { seats[$0] != nil } }

    private var names: [Int: String] { seats.mapValues(\.name) }

    private func seat(of peer: PeerID) -> Int? {
        role == .guest ? (peer == hostPeer && mySeat != nil ? 0 : nil) : peerForSeat.first { $0.value == peer }?.key
    }

    /// True when the seat was reconnecting and is back.
    @discardableResult
    private func heard(_ seat: Int) -> Bool {
        lastHeard[seat] = clock.now
        guard seats[seat]?.isReconnecting == true else { return false }
        seats[seat]?.isReconnecting = false
        onEvent?(.back(seat: seat))
        return true
    }

    private func take(_ snapshot: Match) {
        if let match {
            guard match != snapshot, rules.shouldReplace(match, with: snapshot) else { return }
        }
        match = snapshot
        onEvent?(.snapshot(snapshot))
    }

    private func lose(_ seat: Int, left: Bool = false) {
        guard seats[seat] != nil || (role == .guest && seat == 0) else { return }
        if role == .host {
            seats[seat] = nil
            tokens[seat] = nil
            peerForSeat[seat] = nil
        } else {
            seats[seat] = nil
        }
        lastHeard[seat] = nil
        onEvent?(left ? .left(seat: seat) : .seatLost(seat: seat))
    }

    private func encode(_ message: Message) throws -> Data {
        sequence += 1
        let data = try JSONEncoder().encode(Envelope(protocolVersion: protocolVersion, sequence: sequence, body: message))
        guard data.count <= Framer.maxMessageBytes else { throw Framer.Failure.tooLarge(data.count) }
        return data
    }

    private func checkSize(_ message: Message) throws {
        let data = try JSONEncoder().encode(Envelope(protocolVersion: protocolVersion, sequence: sequence + 1, body: message))
        guard data.count <= Framer.maxMessageBytes else { throw Framer.Failure.tooLarge(data.count) }
    }

    private func post(_ message: Message, to peer: PeerID?) async {
        guard !stopped, let data = try? encode(message) else { return }
        // To everyone, the host means everyone seated, not people still waiting for an answer.
        if role == .host, peer == nil {
            for target in peerForSeat.values { try? await transport.send(data, to: target) }
        } else {
            try? await transport.send(data, to: peer)
        }
    }
}
