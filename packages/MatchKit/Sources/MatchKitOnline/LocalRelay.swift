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

    private var rooms: [String: Room] = [:]
    private var sockets: [Int: Socket] = [:]
    /// Connection → room and seat.
    private var places: [Int: (code: String, seat: Int)] = [:]
    private var nextConnection = 0
    private var codes: [String]
    private var reachable = true
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

    /// Online play is switched off: `create` and `join` are refused.
    public func setPaused(_ on: Bool) { paused = on }

    /// Breaks one phone's connection, as its network would.
    public func cut(_ peer: PeerID, in code: String) {
        guard let seat = Self.seat(of: peer), let id = rooms[code]?.seats[seat]?.connection else { return }
        cut(id)
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
            guard let room = rooms[code], !room.isClosed else { return send(.refused(.notFound), to: id) }
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
            guard let room = rooms[code], !room.isClosed, let seat = room.seats.first(where: { $0.value.token == token })?.key else {
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
            guard let place = places[id], let room = rooms[place.code] else { return send(.refused(.invalid), to: id) }
            guard !room.isClosed else { return }
            for (seat, other) in room.seats where seat != place.seat && (to == nil || to == Self.peer(seat)) {
                if let connection = other.connection { send(.data(text, from: Self.peer(place.seat)), to: connection) }
            }
        case .leave:
            count("leave")
            guard let place = places.removeValue(forKey: id) else { return send(.refused(.invalid), to: id) }
            if place.seat == 0 {
                rooms[place.code]?.isClosed = true
            } else {
                rooms[place.code]?.seats[place.seat] = nil
            }
            tell(place.code, about: place.seat, .left)
        case .ping:
            count("ping")
            send(.pong, to: id)
        case .roll:
            count("roll")
            send(.refused(.invalid), to: id)
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
