import Foundation
import MatchKit

/// A relay inside the app: the same rooms, seats and messages as the one on AWS, in memory. For
/// tests, UI tests and the demo player, as `LoopbackTransport` is for nearby play. It speaks the
/// wire format in `shared/vectors/relay-v1` through real `OnlineTransport`s.
public actor LocalRelay {
    private struct Seat {
        var token: String
        var connection: Int?
    }

    private struct Room {
        var game: RelayRequest.Game
        var seatCount: Int
        var seats: [Int: Seat] = [:]
        var isClosed = false
    }

    private final class Socket: RelaySocket, @unchecked Sendable {
        let incoming: AsyncStream<String>
        let out: AsyncStream<String>.Continuation
        let id: Int
        weak var relay: LocalRelay?
        private let lock = NSLock()
        private var closed = false

        init(id: Int, relay: LocalRelay) {
            self.id = id
            self.relay = relay
            (incoming, out) = AsyncStream.makeStream()
        }

        func send(_ text: String) async throws {
            guard !lock.sync({ closed }), let relay else { throw CancellationError() }
            await relay.receive(text, on: id)
        }

        func close() {
            let first: Bool = lock.sync {
                defer { closed = true }
                return !closed
            }
            guard first else { return }
            out.finish()
            let relay = relay, id = id
            Task { await relay?.disconnected(id) }
        }

        /// The relay's end: the connection is gone.
        func end() {
            lock.sync { closed = true }
            out.finish()
        }
    }

    struct Unreachable: Error {}

    /// A notification the real relay would have sent through Apple.
    public struct Invitation: Sendable, Equatable {
        public var code: String
        /// Who asks: their player number, and the name they play under.
        public var from: String
        public var name: String
        public var to: String

        public init(code: String, from: String, name: String, to: String) {
            self.code = code
            self.from = from
            self.name = name
            self.to = to
        }
    }

    private struct Player {
        var secret: String
        var push: RelayRequest.Push?
    }

    private var players: [String: Player] = [:]
    /// "blocker>blocked".
    private var blocks: Set<String> = []
    /// Every invitation sent, in order.
    public private(set) var invitations: [Invitation] = []
    private var onInvitation: (@Sendable (Invitation) -> Void)?

    /// Stands in for the notification arriving on the other phone.
    public func whenInvited(_ handler: @escaping @Sendable (Invitation) -> Void) { onInvitation = handler }

    /// A player who can be invited, as if their phone had registered (the demo's Ama).
    public func know(player: String, secret: String, push: RelayRequest.Push?) {
        players[player] = Player(secret: secret, push: push)
    }

    private var rooms: [String: Room] = [:]
    private var sockets: [Int: Socket] = [:]
    /// Connection → room and seat.
    private var places: [Int: (code: String, seat: Int)] = [:]
    private var nextConnection = 0
    private var codes: [String]
    private var reachable = true
    /// Messages between phones arrive a little late and not always in the order sent, as they
    /// can through the real relay (each is handled on its own, side by side).
    private var disorder = false
    private var paused = false
    /// Every message the relay took in, by `type` (for counting what a game costs).
    public private(set) var received: [String: Int] = [:]

    /// - Parameter codes: the codes rooms get, in order; random after that.
    public init(codes: [String] = ["K7M2QD"]) {
        self.codes = codes
    }

    /// A connection to this relay, for `OnlineTransport(dial:)`.
    public nonisolated var dial: OnlineTransport.Dial {
        { [weak self] in
            guard let self else { throw Unreachable() }
            return try await self.connect()
        }
    }

    /// No signal: new connections fail, and with `cutting` the ones there are break.
    public func setReachable(_ on: Bool, cutting: Bool = false) {
        reachable = on
        if !on, cutting { for id in Array(sockets.keys) { cut(id) } }
    }

    /// Room messages take a random moment each, so two sent close together can swap places.
    public func setDisorder(_ on: Bool) { disorder = on }

    /// Online play is switched off: `create` and `join` are refused.
    public func setPaused(_ on: Bool) { paused = on }

    /// Breaks one phone's connection, as its network would.
    public func cut(_ peer: PeerID, in code: String) {
        guard let seat = Self.seat(of: peer), let id = rooms[code]?.seats[seat]?.connection else { return }
        cut(id)
    }

    /// Forgets one phone's connection while leaving it open, as the real relay did when it was
    /// wrongly told the phone had gone. The phone's next message is refused with `notFound`.
    public func forget(_ peer: PeerID, in code: String) {
        guard let seat = Self.seat(of: peer), let id = rooms[code]?.seats[seat]?.connection else { return }
        places[id] = nil
        rooms[code]?.seats[seat]?.connection = nil
        tell(code, about: seat, .dropped)
    }

    /// A room from before, with nobody connected: `tokens` are its seats' tokens in order, the
    /// creator's first. For a relay that starts empty with the app (the demo), so a saved game
    /// can be rejoined. Does nothing if the room is there already.
    public func restore(code: String, game: RelayRequest.Game, tokens: [String]) {
        guard rooms[code] == nil, (2...4).contains(tokens.count) else { return }
        codes.removeAll { $0 == code }
        let seats = Dictionary(uniqueKeysWithValues: tokens.enumerated().map { ($0.offset, Seat(token: $0.element, connection: nil)) })
        rooms[code] = Room(game: game, seatCount: tokens.count, seats: seats)
    }

    public func hasRoom(_ code: String) -> Bool { rooms[code].map { !$0.isClosed } ?? false }

    // MARK: - Connections

    private func connect() throws -> any RelaySocket {
        guard reachable else { throw Unreachable() }
        nextConnection += 1
        let socket = Socket(id: nextConnection, relay: self)
        sockets[socket.id] = socket
        return socket
    }

    private func cut(_ id: Int) {
        sockets[id]?.end()
        disconnected(id)
    }

    private func disconnected(_ id: Int) {
        sockets[id] = nil
        guard let place = places.removeValue(forKey: id), rooms[place.code]?.seats[place.seat]?.connection == id else { return }
        rooms[place.code]?.seats[place.seat]?.connection = nil
        tell(place.code, about: place.seat, .dropped)
    }

    private func receive(_ text: String, on id: Int) {
        guard let request = try? JSONDecoder().decode(RelayRequest.self, from: Data(text.utf8)) else {
            return send(.refused(.invalid), to: id)
        }
        switch request {
        case let .create(game, seats, _, _):
            count("create")
            guard !paused else { return send(.refused(.paused), to: id) }
            guard places[id] == nil, (2...4).contains(seats) else { return send(.refused(.invalid), to: id) }
            let code = newCode()
            let token = Self.token()
            rooms[code] = Room(game: game, seatCount: seats, seats: [0: Seat(token: token, connection: id)])
            places[id] = (code, 0)
            send(.room(code: code, peer: Self.peer(0), token: token, peers: []), to: id)
        case let .join(code, game, _):
            count("join")
            guard !paused else { return send(.refused(.paused), to: id) }
            guard places[id] == nil else { return send(.refused(.invalid), to: id) }
            guard let room = rooms[code] else { return send(.refused(.notFound), to: id) }
            guard !room.isClosed else { return send(.refused(.ended), to: id) }
            guard room.game == game else { return send(.refused(.needsUpdate), to: id) }
            guard let seat = (1..<room.seatCount).first(where: { room.seats[$0] == nil }) else {
                return send(.refused(.full), to: id)
            }
            let token = Self.token()
            rooms[code]?.seats[seat] = Seat(token: token, connection: id)
            places[id] = (code, seat)
            send(.room(code: code, peer: Self.peer(seat), token: token, peers: here(code, except: seat)), to: id)
            tell(code, about: seat, .joined)
        case let .rejoin(code, token):
            count("rejoin")
            guard places[id] == nil else { return send(.refused(.invalid), to: id) }
            guard let room = rooms[code] else { return send(.refused(.notFound), to: id) }
            guard !room.isClosed else { return send(.refused(.ended), to: id) }
            guard let seat = room.seats.first(where: { $0.value.token == token })?.key else {
                return send(.refused(.notFound), to: id)
            }
            // The old connection may not have been noticed dead yet: this one takes the seat over.
            if let old = room.seats[seat]?.connection, old != id {
                places[old] = nil
                sockets[old]?.end()
                sockets[old] = nil
            }
            rooms[code]?.seats[seat]?.connection = id
            places[id] = (code, seat)
            send(.room(code: code, peer: Self.peer(seat), token: token, peers: here(code, except: seat)), to: id)
            tell(code, about: seat, .joined)
        case let .data(text, to):
            count("data")
            // Not in a room on this connection (any more).
            guard let place = places[id], let room = rooms[place.code] else { return send(.refused(.notFound), to: id) }
            guard !room.isClosed else { return }
            for (seat, other) in room.seats where seat != place.seat && (to == nil || to == Self.peer(seat)) {
                guard let connection = other.connection else { continue }
                let event = RelayEvent.data(text, from: Self.peer(place.seat))
                if disorder {
                    let wait = UInt64.random(in: 0...6_000_000)
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: wait)
                        await self?.send(event, to: connection)
                    }
                } else {
                    send(event, to: connection)
                }
            }
        case .leave:
            count("leave")
            guard let place = places.removeValue(forKey: id) else { return send(.refused(.notFound), to: id) }
            if place.seat == 0 {
                rooms[place.code]?.isClosed = true
            } else {
                rooms[place.code]?.seats[place.seat] = nil
            }
            tell(place.code, about: place.seat, .left)
        case .health:
            count("health")
            send(.health(open: !paused), to: id)
        case .ping:
            count("ping")
            send(.pong, to: id)
        case .roll:
            count("roll")
            send(.refused(.invalid), to: id)
        case let .register(_, player, secret, push):
            count("register")
            // The first phone to register a player number owns it.
            if let known = players[player], known.secret != secret { return send(.refused(.invalid), to: id) }
            players[player] = Player(secret: secret, push: push)
            send(.registered, to: id)
        case let .invite(player, secret, to, name):
            count("invite")
            // Only into the room this connection made.
            guard let place = places[id], place.seat == 0, to != player, players[player]?.secret == secret else {
                return send(.refused(.invalid), to: id)
            }
            guard rooms[place.code]?.isClosed == false else { return send(.refused(.ended), to: id) }
            // One answer for unknown, notifications off and blocked.
            guard players[to]?.push != nil, !blocks.contains("\(to)>\(player)") else { return send(.refused(.unreachable), to: id) }
            let invitation = Invitation(code: place.code, from: player, name: name, to: to)
            invitations.append(invitation)
            send(.invited(to: to), to: id)
            onInvitation?(invitation)
        case let .block(_, player, secret, who, on):
            count("block")
            guard players[player]?.secret == secret else { return send(.refused(.invalid), to: id) }
            if on { blocks.insert("\(player)>\(who)") } else { blocks.remove("\(player)>\(who)") }
            send(.blocked(who: who, on: on), to: id)
        case let .decline(code, player):
            count("decline")
            guard let room = rooms[code], !room.isClosed, let creator = room.seats[0]?.connection else { return }
            send(.declined(player: player), to: creator)
        }
    }

    // MARK: - Helpers

    private func count(_ type: String) { received[type, default: 0] += 1 }

    private func send(_ event: RelayEvent, to id: Int) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        sockets[id]?.out.yield(String(decoding: data, as: UTF8.self))
    }

    private func tell(_ code: String, about seat: Int, _ state: RelayEvent.PeerState) {
        guard let room = rooms[code] else { return }
        for (other, place) in room.seats where other != seat {
            if let connection = place.connection { send(.peer(Self.peer(seat), state), to: connection) }
        }
    }

    private func here(_ code: String, except seat: Int) -> [PeerID] {
        (rooms[code]?.seats ?? [:]).filter { $0.key != seat && $0.value.connection != nil }.keys.sorted().map(Self.peer)
    }

    private func newCode() -> String {
        if !codes.isEmpty { return codes.removeFirst() }
        var generator = SystemRandomNumberGenerator()
        while true {
            let code = String((0..<RoomCode.length).map { _ in RoomCode.alphabet.randomElement(using: &generator)! })
            if rooms[code] == nil { return code }
        }
    }

    private static func token() -> String { UUID().uuidString + UUID().uuidString }
    private static func peer(_ seat: Int) -> PeerID { PeerID("p\(seat)") }
    private static func seat(of peer: PeerID) -> Int? { Int(peer.raw.dropFirst()) }
}
