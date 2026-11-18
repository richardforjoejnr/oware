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

/// How patient a room is. Each transport brings its own: phones side by side notice a break in
/// seconds, while mobile data is slower to come back and every ping through the relay is paid for.
public struct RoomTiming: Sendable, Equatable {
    /// A ping goes out this often.
    public var heartbeatInterval: Double
    /// A seat silent this long is shown as reconnecting.
    public var quietAfter: Double
    /// A seat silent this long is given up, or, when seats are kept, the player is asked what to do.
    public var lostAfter: Double
    /// A seat silent for `lostAfter` stays that player's: it is reported (`seatLost`), and again
    /// after as long again, and the player decides whether to wait. Online, where a phone can be
    /// off the network for minutes and the app closed meanwhile (docs/ONLINE_PLAY.md §5).
    public var keepsSeats: Bool

    public init(heartbeatInterval: Double, quietAfter: Double, lostAfter: Double, keepsSeats: Bool = false) {
        self.heartbeatInterval = heartbeatInterval
        self.quietAfter = quietAfter
        self.lostAfter = lostAfter
        self.keepsSeats = keepsSeats
    }

    /// 15 s: the owner found a minute too long and 10 s too short.
    public static let nearby = RoomTiming(heartbeatInterval: 2, quietAfter: 4, lostAfter: 15)
    /// docs/ONLINE_PLAY.md §5, Connections.
    public static let online = RoomTiming(heartbeatInterval: 10, quietAfter: 25, lostAfter: 90, keepsSeats: true)
}

/// What a phone keeps so its game can carry on after the app was closed (docs/ONLINE_PLAY.md §5):
/// enough, with the match, to make the room again with `Room(resuming:)`. The tokens are secrets:
/// whoever holds one is that seat.
public struct RoomSave: Codable, Sendable, Equatable {
    /// This phone's seat. Seat 0 is the phone in charge.
    public var seat: Int
    public var names: [Int: String]
    /// The phone in charge: every other seat's token. Any other phone: its own.
    public var tokens: [Int: UUID]
    /// The number on this phone's last message.
    public var sequence: Int

    public init(seat: Int, names: [Int: String], tokens: [Int: UUID], sequence: Int) {
        self.seat = seat
        self.names = names
        self.tokens = tokens
        self.sequence = sequence
    }
}

public enum Refusal: Sendable, Equatable {
    case roomFull
    case declined
    /// The phones run different versions of the room protocol; whoever is older should update.
    case needsUpdate(hostVersion: Int)
}

/// What the phones in one game send each other, inside an `Envelope`. The JSON is written by
/// hand (below) and pinned by the examples in `shared/vectors/room-v2`.
public enum RoomMessage<Match: Codable & Sendable, Intent: Codable & Sendable>: Sendable {
    /// `rejoin` is the token from an earlier `welcome`, to take the same seat back.
    case hello(name: String, rejoin: UUID?)
    case welcome(seat: Int, token: UUID, names: [Int: String], snapshot: Match)
    case refused(Refusal)
    case intent(Intent)
    case snapshot(Match)
    case ping
    case bye
    /// The sender's player number, so the other player can ask for another game later. Sent once
    /// seated, and only by a phone that has one. An app from before this was added drops it.
    case player(String)
}

/// One object with a `type`, and that kind's values beside it:
/// `{"type": "hello", "name": "Kofi"}`, `{"type": "refused", "reason": "roomFull"}`.
extension RoomMessage: Codable {
    private enum Key: String, CodingKey {
        case type, name, rejoin, seat, token, names, snapshot, reason, hostVersion, intent, player
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "hello":
            self = .hello(name: try c.decode(String.self, forKey: .name), rejoin: try c.decodeIfPresent(UUID.self, forKey: .rejoin))
        case "welcome":
            let byText = try c.decode([String: String].self, forKey: .names)
            var names: [Int: String] = [:]
            for (seat, name) in byText {
                guard let seat = Int(seat) else {
                    throw DecodingError.dataCorruptedError(forKey: .names, in: c, debugDescription: "seat \(seat) is not a number")
                }
                names[seat] = name
            }
            self = .welcome(seat: try c.decode(Int.self, forKey: .seat), token: try c.decode(UUID.self, forKey: .token),
                            names: names, snapshot: try c.decode(Match.self, forKey: .snapshot))
        case "refused":
            let reason = try c.decode(String.self, forKey: .reason)
            switch reason {
            case "roomFull": self = .refused(.roomFull)
            case "declined": self = .refused(.declined)
            case "needsUpdate": self = .refused(.needsUpdate(hostVersion: try c.decode(Int.self, forKey: .hostVersion)))
            default: throw DecodingError.dataCorruptedError(forKey: .reason, in: c, debugDescription: "unknown reason \(reason)")
            }
        case "intent": self = .intent(try c.decode(Intent.self, forKey: .intent))
        case "snapshot": self = .snapshot(try c.decode(Match.self, forKey: .snapshot))
        case "ping": self = .ping
        case "bye": self = .bye
        case "player": self = .player(try c.decode(String.self, forKey: .player))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown message \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .hello(name, rejoin):
            try c.encode("hello", forKey: .type)
            try c.encode(name, forKey: .name)
            try c.encodeIfPresent(rejoin, forKey: .rejoin)
        case let .welcome(seat, token, names, snapshot):
            try c.encode("welcome", forKey: .type)
            try c.encode(seat, forKey: .seat)
            try c.encode(token, forKey: .token)
            try c.encode(Dictionary(uniqueKeysWithValues: names.map { (String($0.key), $0.value) }), forKey: .names)
            try c.encode(snapshot, forKey: .snapshot)
        case let .refused(refusal):
            try c.encode("refused", forKey: .type)
            switch refusal {
            case .roomFull: try c.encode("roomFull", forKey: .reason)
            case .declined: try c.encode("declined", forKey: .reason)
            case let .needsUpdate(hostVersion):
                try c.encode("needsUpdate", forKey: .reason)
                try c.encode(hostVersion, forKey: .hostVersion)
            }
        case let .intent(intent):
            try c.encode("intent", forKey: .type)
            try c.encode(intent, forKey: .intent)
        case let .snapshot(snapshot):
            try c.encode("snapshot", forKey: .type)
            try c.encode(snapshot, forKey: .snapshot)
        case .ping: try c.encode("ping", forKey: .type)
        case .bye: try c.encode("bye", forKey: .type)
        case let .player(player):
            try c.encode("player", forKey: .type)
            try c.encode(player, forKey: .player)
        }
    }
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
    /// That seat has gone silent too long. On a guest, seat 0 means the host's phone. Where seats
    /// are kept (`RoomTiming.keepsSeats`) the seat is still theirs, `back` may follow, and this
    /// is sent again after each further wait.
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

    public let role: Role
    public let rules: Rules
    public let name: String
    /// How often a ping goes out, and how long a silent seat is waited for.
    public let timing: RoomTiming
    public private(set) var match: Match?
    public private(set) var mySeat: Int?
    public private(set) var seats: [Int: Seat] = [:]
    /// Host: people waiting for an answer, by peer.
    public private(set) var pending: [PeerID: String] = [:]
    public var onEvent: (@MainActor (RoomEvent<Match>) -> Void)?
    /// This phone's player number, told to the others once seated. Set before anyone connects.
    public var player: String?
    /// The other seats' player numbers, as their phones gave them.
    public private(set) var players: [Int: String] = [:]
    /// A seat's player number has arrived.
    public var onPlayer: (@MainActor (_ seat: Int, _ player: String) -> Void)?

    private var transport: any MatchTransport
    private let clock: any RoomClock
    private let protocolVersion: Int
    private var listener: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var sequence = 0
    private var filter = SequenceFilter()
    private var peerForSeat: [Int: PeerID] = [:]
    private var lastHeard: [Int: Double] = [:]
    /// Seats are kept: when each silent seat was last reported.
    private var reportedLost: [Int: Double] = [:]
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
                clock: any RoomClock = SystemClock(), timing: RoomTiming = .nearby,
                protocolVersion: Int = MatchKit.protocolVersion) {
        role = .host
        self.rules = rules
        self.name = name
        self.match = match
        self.transport = transport
        self.clock = clock
        self.timing = timing
        self.protocolVersion = protocolVersion
        mySeat = 0
        seats[0] = Seat(name: name)
        listen()
    }

    /// Joins the room at the other end of `transport` once it connects.
    public init(joiningAs name: String, rules: Rules, transport: any MatchTransport,
                clock: any RoomClock = SystemClock(), timing: RoomTiming = .nearby,
                protocolVersion: Int = MatchKit.protocolVersion) {
        role = .guest
        self.rules = rules
        self.name = name
        self.transport = transport
        self.clock = clock
        self.timing = timing
        self.protocolVersion = protocolVersion
        listen()
    }

    /// Carries on a game this phone was in before the app closed: the same seat, names and
    /// tokens, and the match as it was saved. Nobody else has been heard from yet, so every other
    /// seat starts as reconnecting; a guest asks for its seat back as soon as the host connects.
    public init(resuming save: RoomSave, match: Match, rules: Rules, transport: any MatchTransport,
                clock: any RoomClock = SystemClock(), timing: RoomTiming = .online,
                protocolVersion: Int = MatchKit.protocolVersion) {
        role = save.seat == 0 ? .host : .guest
        self.rules = rules
        name = save.names[save.seat] ?? ""
        self.match = match
        self.transport = transport
        self.clock = clock
        self.timing = timing
        self.protocolVersion = protocolVersion
        mySeat = save.seat
        seats = save.names.mapValues { Seat(name: $0) }
        for seat in seats.keys where seat != save.seat {
            seats[seat]?.isReconnecting = true
            lastHeard[seat] = clock.now
        }
        if role == .host {
            tokens = save.tokens
        } else {
            token = save.tokens[save.seat]
            awaitingWelcome = true
        }
        // A phone that stayed in the game has counted this one's messages: carry on well past
        // the last it can have heard, or everything from here would be dropped as old.
        sequence = save.sequence + Self.resumeGap
        listen()
    }

    /// More messages than a phone sends between saving and the app closing.
    static var resumeGap: Int { 1_000_000 }

    /// What to keep so this phone can come back to the game; nil until it has a seat and a match.
    public var save: RoomSave? {
        guard let mySeat, match != nil else { return nil }
        let held = role == .host ? tokens : token.map { [mySeat: $0] } ?? [:]
        return RoomSave(seat: mySeat, names: names, tokens: held, sequence: sequence)
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
        await introduce(to: peer)
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

    /// Host: no more players, whatever seats are free (the game is under way). Whoever asked is
    /// told the room is full.
    public func turnAway(_ peer: PeerID) async {
        guard role == .host, pending.removeValue(forKey: peer) != nil else { return }
        await post(.refused(.roomFull), to: peer)
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

    /// Sends a ping and checks who has gone quiet. `startHeartbeat()` calls it every `timing.heartbeatInterval`; tests
    /// call it by hand with a `ManualClock`.
    public func tick() async {
        guard !stopped else { return }
        await post(.ping, to: role == .host ? nil : hostPeer)
        let now = clock.now
        for (seat, heard) in lastHeard where seat != mySeat {
            let silence = now - heard
            if silence >= timing.lostAfter {
                if timing.keepsSeats { reportLost(seat, now: now) } else { lose(seat) }
            } else if silence >= timing.quietAfter, seats[seat]?.isReconnecting == false {
                seats[seat]?.isReconnecting = true
                onEvent?(.reconnecting(seat: seat))
            }
        }
    }

    public func startHeartbeat() {
        heartbeat?.cancel()
        let interval = UInt64(timing.heartbeatInterval * 1_000_000_000)
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
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
            goodbyes.remove(peer)   // someone new may hold this place at the carrier
            switch role {
            case .guest:
                // The first connection, or the same host on a fresh one (online, after either
                // phone's link came back): ask for the seat again and take the match as it is now.
                guard hostPeer == nil || hostPeer == peer else { break }
                hostPeer = peer
                if token != nil { awaitingWelcome = true }
                await post(.hello(name: name, rejoin: token), to: peer)
            case .host:
                // A seated phone on a fresh connection may have missed moves.
                if seat(of: peer) != nil, let match { await post(.snapshot(match), to: peer) }
            }
        case let .disconnected(peer):
            pending[peer] = nil
            filter.forget(peer)
            // Guest: the link to the host is down. Moves made now are held until it has us back.
            if role == .guest, peer == hostPeer, token != nil { awaitingWelcome = true }
            if let seat = seat(of: peer) {
                peerForSeat[seat] = nil
                if seats[seat]?.isReconnecting == false {
                    seats[seat]?.isReconnecting = true
                    onEvent?(.reconnecting(seat: seat))
                }
            }
        case let .left(peer):
            // Whoever next holds this place at the carrier starts afresh.
            pending[peer] = nil
            filter.forget(peer)
            farewell(from: peer)
        case let .received(data, peer):
            await receive(data, from: peer)
        }
    }

    /// A phone has gone for good: by its own goodbye, or the carrier's word. Told once.
    private func farewell(from peer: PeerID) {
        guard goodbyes.insert(peer).inserted else { return }
        switch role {
        case .host: if let seat = seat(of: peer) { lose(seat, left: true) }
        case .guest: if hostPeer == nil || peer == hostPeer { lose(0, left: true) }
        }
    }

    private func receive(_ data: Data, from peer: PeerID) async {
        guard let header = try? JSONDecoder().decode(EnvelopeHeader.self, from: data) else { return }
        // Another version of the protocol, older or newer: the body cannot be trusted to mean the same.
        if header.protocolVersion != protocolVersion {
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
                await introduce(to: peer)
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
            farewell(from: peer)
        case let .player(theirs):
            if let seat = seat(of: peer) { met(seat, theirs) }
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
            if let hostPeer {
                Task {
                    await introduce(to: hostPeer)
                    for intent in held { await post(.intent(intent), to: hostPeer) }
                }
            }
        case let .refused(refusal):
            onEvent?(.refused(refusal))
        case let .snapshot(snapshot):
            take(snapshot)
        case .bye:
            if let hostPeer { farewell(from: hostPeer) } else { lose(0, left: true) }
        case let .player(theirs):
            if mySeat != nil { met(0, theirs) }
        case .hello, .intent, .ping:
            break
        }
    }

    // MARK: - Helpers

    private var isFull: Bool { (1..<rules.seatCount).allSatisfy { seats[$0] != nil } }

    private var names: [Int: String] { seats.mapValues(\.name) }

    /// Tells a phone just seated who this one is, if it has a player number.
    private func introduce(to peer: PeerID) async {
        if let player, !player.isEmpty { await post(.player(player), to: peer) }
    }

    private func met(_ seat: Int, _ theirs: String) {
        guard !theirs.isEmpty, theirs.count <= 64, players[seat] != theirs else { return }
        players[seat] = theirs
        onPlayer?(seat, theirs)
    }

    private func seat(of peer: PeerID) -> Int? {
        role == .guest ? (peer == hostPeer && mySeat != nil ? 0 : nil) : peerForSeat.first { $0.value == peer }?.key
    }

    /// True when the seat was reconnecting and is back.
    @discardableResult
    private func heard(_ seat: Int) -> Bool {
        lastHeard[seat] = clock.now
        reportedLost[seat] = nil
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

    /// The seat is kept: say it has been silent too long, now and after each further `lostAfter`.
    private func reportLost(_ seat: Int, now: Double) {
        if let last = reportedLost[seat], now - last < timing.lostAfter { return }
        reportedLost[seat] = now
        seats[seat]?.isReconnecting = true
        onEvent?(.seatLost(seat: seat))
    }

    /// Peers whose leaving has been told.
    private var goodbyes: Set<PeerID> = []

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
        reportedLost[seat] = nil
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
