import Foundation
import MatchKit

/// One WebSocket connection to the relay, as the transport needs it. The app uses
/// `URLSessionRelaySocket`; tests and the demo use `LocalRelay`'s.
public protocol RelaySocket: Sendable {
    /// Messages as they arrive. Finishes when the connection ends, however it ends.
    var incoming: AsyncStream<String> { get }
    func send(_ text: String) async throws
    func close()
}

/// Who a phone is to the relay when it asks someone for another game, or may be asked: its
/// player number, which other phones are given, and the secret that goes only to the relay.
public struct RelayPlayer: Sendable, Equatable {
    public var id: String
    public var secret: String
    /// The relay's name for the game: `oware`.
    public var game: String

    public init(id: String, secret: String, game: String) {
        self.id = id
        self.secret = secret
        self.game = game
    }
}

/// Phones in one game over the internet: a `MatchTransport` that talks to the relay
/// (docs/ONLINE_PLAY.md §5).
///
/// The relay gives every phone in a room a name that stays the same when it reconnects (`p0` made
/// the room), so this transport is a pipe that mends itself: when the connection breaks it dials
/// again and takes its seat back with the token. While it is down the room is told its peers are
/// `disconnected`, and `connected` again whenever either end's link is new, so the room holds a
/// guest's moves meanwhile and catches up after (`Room`).
public final class OnlineTransport: MatchTransport, @unchecked Sendable {
    public typealias Dial = @Sendable () async throws -> any RelaySocket
    public typealias Sleep = @Sendable (Double) async -> Void

    /// How this phone comes into the room.
    public enum Entry: Sendable, Equatable {
        case create(game: RelayRequest.Game, seats: Int, proof: RelayRequest.Proof?)
        case join(code: RoomCode, game: RelayRequest.Game)
        /// Back into a game from before (after the app was closed).
        case rejoin(Seat)
    }

    /// This phone's place in a room: enough to come back to it. The token is a secret.
    public struct Seat: Codable, Sendable, Equatable {
        public var code: String
        public var peer: PeerID
        public var token: String

        public init(code: String, peer: PeerID, token: String) {
            self.code = code
            self.peer = peer
            self.token = token
        }
    }

    public enum Status: Sendable, Equatable {
        case connecting
        /// In the room.
        case open(Seat)
        /// Was in the room; dialling again.
        case reconnecting
        /// The relay said no: wrong code, full, paused, another version. Final.
        case refused(RelayEvent.Refusal)
        /// The relay could not be reached at all. Final.
        case unreachable
        case closed
    }

    /// What came of asking someone played before to join this game.
    public enum InviteAnswer: Sendable, Equatable {
        /// The notification is on its way.
        case sent
        /// `unreachable`: they cannot be notified. Any other reason: the relay would not send it.
        case refused(RelayEvent.Refusal)
        /// No connection, or the relay said nothing in time.
        case noAnswer
    }

    public let events: AsyncStream<TransportEvent>
    /// Players who said "Not now" to an invitation to this game, by player number.
    public let declines: AsyncStream<String>
    /// Every change of `status`, for the lobby.
    public let statuses: AsyncStream<Status>

    private let eventsOut: AsyncStream<TransportEvent>.Continuation
    private let statusOut: AsyncStream<Status>.Continuation
    private let declinesOut: AsyncStream<String>.Continuation
    /// The one question the relay has not answered yet (`ask`).
    private var asking: (id: Int, answer: CheckedContinuation<RelayEvent?, Never>)?
    private var askCount = 0
    /// How long the relay has to answer a question, in seconds.
    public var answerWait: Double = 10
    private let entry: Entry
    private let install: String
    private let dial: Dial
    private let sleep: Sleep
    private let retryDelays: [Double]
    private let lock = NSLock()
    private var socket: (any RelaySocket)?
    private var currentSeat: Seat?
    private var currentStatus = Status.connecting
    private var isOpen = false
    private var isClosed = false
    /// Peers the room has been told are connected.
    private var present: Set<PeerID> = []
    private var runner: Task<Void, Never>?

    /// - Parameters:
    ///   - install: this phone's random ID (the relay keeps only a hash).
    ///   - retryDelays: seconds between tries. Before the first seat they are all there is; once
    ///     seated the last one repeats for as long as the transport is open.
    public init(entry: Entry, install: String, dial: @escaping Dial, retryDelays: [Double] = [1, 2, 4, 8],
                sleep: @escaping Sleep = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.entry = entry
        self.install = install
        self.dial = dial
        self.sleep = sleep
        self.retryDelays = retryDelays.isEmpty ? [1] : retryDelays
        if case let .rejoin(seat) = entry { currentSeat = seat }
        (events, eventsOut) = AsyncStream.makeStream()
        (statuses, statusOut) = AsyncStream.makeStream()
        (declines, declinesOut) = AsyncStream.makeStream()
        runner = Task { [weak self] in await self?.run() }
    }

    /// `p0`… once seated; before that, a placeholder.
    public var me: PeerID { lock.sync { currentSeat?.peer } ?? PeerID("-") }
    public var seat: Seat? { lock.sync { currentSeat } }
    public var status: Status { lock.sync { currentStatus } }

    public func send(_ data: Data, to peer: PeerID?) async throws {
        // A guest only ever talks to the phone in charge, never to the other guests.
        let target = peer ?? (me == Relay.creator ? nil : Relay.creator)
        let text = try Self.encode(try RelayRequest.data(data, to: target))
        guard text.utf8.count <= Relay.maxFrameBytes else { throw Framer.Failure.tooLarge(text.utf8.count) }
        // With no connection the message is dropped: the room has been told its peers are
        // disconnected, and catches up when they are back.
        guard let live = lock.sync({ isOpen && !isClosed ? socket : nil }) else { return }
        do {
            try await live.send(text)
        } catch {
            // The connection is dead but has not said so yet: end it, and dial again.
            live.close()
        }
    }

    /// Asks someone played before to join this game: the relay sends their phone a notification
    /// with the code. Only the phone that made the game can. `me` is registered first (with
    /// `push`, where this phone's own notifications go), so the relay knows who asks.
    public func invite(_ to: String, name: String, from me: RelayPlayer, push: RelayRequest.Push?) async -> InviteAnswer {
        switch await ask(.register(game: me.game, player: me.id, secret: me.secret, push: push)) {
        case .registered: break
        case let .refused(reason): return .refused(reason)
        default: return .noAnswer
        }
        switch await ask(.invite(player: me.id, secret: me.secret, to: to, name: name)) {
        case .invited: return .sent
        case let .refused(reason): return .refused(reason)
        default: return .noAnswer
        }
    }

    /// One question to the relay on this game's connection, and its answer; nil with no
    /// connection or no answer in time. One at a time: a second question ends the first.
    private func ask(_ request: RelayRequest) async -> RelayEvent? {
        guard let text = try? Self.encode(request), let live = lock.sync({ isOpen && !isClosed ? socket : nil }) else { return nil }
        let wait = UInt64(max(answerWait, 0) * 1_000_000_000)
        return await withCheckedContinuation { continuation in
            let (id, earlier): (Int, CheckedContinuation<RelayEvent?, Never>?) = lock.sync {
                askCount += 1
                defer { asking = (askCount, continuation) }
                return (askCount, asking?.answer)
            }
            earlier?.resume(returning: nil)
            Task { [weak self] in
                if (try? await live.send(text)) != nil { try? await Task.sleep(nanoseconds: wait) }
                self?.answered(nil, only: id)
            }
        }
    }

    /// The relay answered (or, with `only`, that question ran out of time).
    private func answered(_ event: RelayEvent?, only id: Int? = nil) {
        let waiting: CheckedContinuation<RelayEvent?, Never>? = lock.sync {
            guard let asking, id == nil || asking.id == id else { return nil }
            self.asking = nil
            return asking.answer
        }
        waiting?.resume(returning: event)
    }

    /// Leaves the room for good and stops.
    public func close() {
        let (live, wasOpen): ((any RelaySocket)?, Bool) = lock.sync {
            guard !isClosed else { return (nil, false) }
            isClosed = true
            defer { socket = nil }
            return (socket, isOpen)
        }
        set(.closed)
        eventsOut.finish()
        statusOut.finish()
        declinesOut.finish()
        answered(nil)
        let runner = runner
        guard let live else {
            runner?.cancel()
            return
        }
        // Say goodbye to the relay before the connection goes, so the others are told at once.
        Task {
            if wasOpen, let leave = try? Self.encode(RelayRequest.leave) { try? await live.send(leave) }
            live.close()
            runner?.cancel()
        }
    }

    /// Stops without leaving the room, as when the app is closed: no goodbye to the relay, so the
    /// seat is kept and the token takes it back later (`Entry.rejoin`).
    public func abandon() {
        let live: (any RelaySocket)? = lock.sync {
            guard !isClosed else { return nil }
            isClosed = true
            defer { socket = nil }
            return socket
        }
        set(.closed)
        eventsOut.finish()
        statusOut.finish()
        declinesOut.finish()
        answered(nil)
        live?.close()
        runner?.cancel()
    }

    /// Breaks the connection without leaving the room, as losing signal does (tests, the demo).
    public func dropConnection() { lock.sync { socket }?.close() }

    // MARK: - The connection

    private func run() async {
        var failures = 0
        while !lock.sync({ isClosed }) {
            let seated = await connectOnce()
            if lock.sync({ isClosed }) { return }
            switch seated {
            case .final: return
            case .wasSeated: failures = 0
            case .never: failures += 1
            }
            let hasSeat = lock.sync { currentSeat != nil }
            if !hasSeat, failures >= retryDelays.count {
                finish(.unreachable)
                return
            }
            if hasSeat { set(.reconnecting) }
            await sleep(retryDelays[min(failures, retryDelays.count - 1)])
        }
    }

    private enum Outcome { case wasSeated, never, final }

    /// One connection, from dialling until it ends.
    private func connectOnce() async -> Outcome {
        guard let live = try? await dial() else { return .never }
        let stillWanted: Bool = lock.sync {
            guard !isClosed else { return false }
            socket = live
            return true
        }
        guard stillWanted else {
            live.close()
            return .final
        }
        defer {
            let gone: Set<PeerID> = lock.sync {
                isOpen = false
                socket = nil
                defer { present = [] }
                return present
            }
            live.close()
            answered(nil)
            // This phone's own link is down: to the room, everyone else has gone quiet.
            for peer in gone.sorted(by: { $0.raw < $1.raw }) { eventsOut.yield(.disconnected(peer)) }
        }
        guard let first = try? Self.encode(firstRequest()), (try? await live.send(first)) != nil else { return .never }
        var seated = false
        for await text in live.incoming {
            guard let event = try? JSONDecoder().decode(RelayEvent.self, from: Data(text.utf8)) else { continue }
            switch event {
            case let .room(code, peer, token, peers):
                let mine = Seat(code: code, peer: peer, token: token)
                lock.sync {
                    currentSeat = mine
                    isOpen = true
                }
                seated = true
                set(.open(mine))
                for other in peers where shows(other) { tell(other, isHere: true) }
            case let .peer(peer, state):
                guard shows(peer) else { break }
                if state == .left {
                    // On purpose: nothing to wait for, so not "reconnecting".
                    lock.sync { _ = present.remove(peer) }
                    eventsOut.yield(.left(peer))
                } else {
                    tell(peer, isHere: state == .joined)
                }
            case let .data(text, from):
                if shows(from) { eventsOut.yield(.received(Data(text.utf8), from: from)) }
            case let .refused(reason):
                if seated {
                    // The relay no longer has this connection in the room, though it is open (it
                    // was wrongly told the phone had gone): take the seat back on a new one.
                    // Any other refusal is about one message (too large, say), not the seat.
                    if reason == .notFound { live.close() } else { answered(event) }
                    break
                }
                finish(.refused(reason))
                return .final
            case .registered, .invited, .blocked:
                answered(event)
            case let .declined(player):
                declinesOut.yield(player)
            case .rolled, .pong, .health, .unknown:
                break
            }
        }
        return seated ? .wasSeated : .never
    }

    private func firstRequest() -> RelayRequest {
        if let seat = lock.sync({ currentSeat }) { return .rejoin(code: seat.code, token: seat.token) }
        switch entry {
        case let .create(game, seats, proof): return .create(game: game, seats: seats, install: install, proof: proof)
        case let .join(code, game): return .join(code: code.text, game: game, install: install)
        case let .rejoin(seat): return .rejoin(code: seat.code, token: seat.token)
        }
    }

    /// The phone in charge sees everyone; everyone else sees only the phone in charge.
    private func shows(_ peer: PeerID) -> Bool {
        let mine = me
        return peer != mine && (mine == Relay.creator || peer == Relay.creator)
    }

    private func tell(_ peer: PeerID, isHere: Bool) {
        lock.sync { _ = isHere ? present.insert(peer).inserted : (present.remove(peer) != nil) }
        eventsOut.yield(isHere ? .connected(peer) : .disconnected(peer))
    }

    private func set(_ status: Status) {
        let changed: Bool = lock.sync {
            guard currentStatus != status else { return false }
            currentStatus = status
            return true
        }
        if changed { statusOut.yield(status) }
    }

    private func finish(_ status: Status) {
        lock.sync { isClosed = true }
        set(status)
        eventsOut.finish()
        statusOut.finish()
        declinesOut.finish()
    }

    private static func encode(_ request: RelayRequest) throws -> String {
        String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
    }
}

/// One message to the relay on a connection of its own, for a phone that is not in a game:
/// registering so it can be invited, blocking someone, saying "Not now".
public enum RelayCall {
    /// Sends `request` and gives back the relay's first answer; nil if the relay could not be
    /// reached or said nothing within `wait` seconds.
    public static func ask(_ request: RelayRequest, dial: OnlineTransport.Dial, wait: Double = 10) async -> RelayEvent? {
        guard let text = try? JSONEncoder().encode(request), let socket = try? await dial() else { return nil }
        defer { socket.close() }
        guard (try? await socket.send(String(decoding: text, as: UTF8.self))) != nil else { return nil }
        let timer = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(wait, 0) * 1_000_000_000))
            if !Task.isCancelled { socket.close() }
        }
        defer { timer.cancel() }
        for await text in socket.incoming {
            if let event = try? JSONDecoder().decode(RelayEvent.self, from: Data(text.utf8)) { return event }
        }
        return nil
    }

    /// Sends `request` where the relay says nothing back (`decline`). False if it did not go.
    @discardableResult
    public static func tell(_ request: RelayRequest, dial: OnlineTransport.Dial) async -> Bool {
        guard let text = try? JSONEncoder().encode(request), let socket = try? await dial() else { return false }
        defer { socket.close() }
        return (try? await socket.send(String(decoding: text, as: UTF8.self))) != nil
    }
}

extension NSLock {
    func sync<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
