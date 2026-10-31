#if canImport(Network)
import Foundation
import MatchKit
import Network

/// Phones nearby, with no router or internet: Bonjour over Apple's phone-to-phone Wi-Fi
/// (`includePeerToPeer`), TCP, and `Framer` for whole messages (docs/MULTIPLAYER.md §1).
/// The app's Info.plist needs `NSLocalNetworkUsageDescription` and the service type in
/// `NSBonjourServices`.
enum Nearby {
    static func parameters() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true   // moves are tiny; send them at once
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
}

/// How finding phones is going. `localNetworkDenied`: the player said no to Local Network (or turned
/// it off in Settings), and nothing nearby can be found until they turn it on.
public enum NearbyStatus: Sendable, Equatable {
    case working
    case localNetworkDenied
    case failed

    /// `kDNSServiceErr_PolicyDenied`: what Bonjour reports without the Local Network permission.
    static let policyDenied: Int32 = -65570

    init(_ state: NWBrowser.State) {
        switch state {
        case let .waiting(error), let .failed(error): self.init(error)
        default: self = .working
        }
    }

    init(_ state: NWListener.State) {
        switch state {
        case let .waiting(error), let .failed(error): self.init(error)
        default: self = .working
        }
    }

    init(_ error: NWError) {
        if case let .dns(code) = error, code == Self.policyDenied { self = .localNetworkDenied } else { self = .failed }
    }
}

/// A game found nearby.
public struct NearbyGame: Sendable, Hashable, Identifiable {
    /// The host's game name, such as "Kofi's game".
    public let name: String
    /// What the host advertises beside the name, such as the rules.
    public let info: [String: String]
    let endpoint: NWEndpoint

    public var id: String { name }
}

/// Connections to other phones, as a `MatchTransport`. A guest has one (to the host); a host,
/// `NearbyHost`, one per guest. All state lives on one serial queue.
public class NearbyTransport: MatchTransport, @unchecked Sendable {
    public let me = PeerID()
    public let events: AsyncStream<TransportEvent>

    let queue = DispatchQueue(label: "MatchKitNearby")
    private let continuation: AsyncStream<TransportEvent>.Continuation
    private var links: [PeerID: Link] = [:]
    private var closed = false

    /// Touched only on `queue`.
    final class Link: @unchecked Sendable {
        let peer = PeerID()
        let connection: NWConnection
        var reader = Framer.Reader()
        var isReady = false
        init(_ connection: NWConnection) { self.connection = connection }
    }

    init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    /// A new connection to a game's host, found earlier (also to come back to a game in play).
    /// Its first `connected` event is the host.
    public static func connect(to game: NearbyGame) -> NearbyTransport {
        let transport = NearbyTransport()
        transport.adopt(NWConnection(to: game.endpoint, using: Nearby.parameters()))
        return transport
    }

    /// Takes a connection on: starts it, reads whole messages from it and reports it.
    func adopt(_ connection: NWConnection) {
        let link = Link(connection)
        queue.async { [self] in
            guard !closed else { return connection.cancel() }
            links[link.peer] = link
            connection.stateUpdateHandler = { [weak self] state in self?.changed(link, state) }
            connection.start(queue: queue)
            read(link)
        }
    }

    private func changed(_ link: Link, _ state: NWConnection.State) {
        switch state {
        case .ready:
            if !link.isReady {
                link.isReady = true
                continuation.yield(.connected(link.peer))
            }
        case .failed, .cancelled:
            drop(link)
        default:
            break
        }
    }

    private func read(_ link: Link) {
        link.connection.receive(minimumIncompleteLength: 1, maximumLength: Framer.maxMessageBytes) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                do {
                    for message in try link.reader.push(data) {
                        self.continuation.yield(.received(message, from: link.peer))
                    }
                } catch {
                    link.connection.cancel()   // garbage: the stream cannot be trusted any more
                    return
                }
            }
            if isComplete || error != nil {
                link.connection.cancel()
            } else {
                self.read(link)
            }
        }
    }

    private func drop(_ link: Link) {
        guard links.removeValue(forKey: link.peer) != nil else { return }
        if link.isReady { continuation.yield(.disconnected(link.peer)) }
    }

    public func send(_ data: Data, to peer: PeerID?) async throws {
        let framed = try Framer.frame(data)
        let targets: [NWConnection] = queue.sync {
            if let peer { return links[peer].map { [$0.connection] } ?? [] }
            return links.values.filter(\.isReady).map(\.connection)
        }
        for connection in targets {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                connection.send(content: framed, completion: .contentProcessed { error in
                    if let error { done.resume(throwing: error) } else { done.resume() }
                })
            }
        }
    }

    public func close() {
        queue.sync {
            closed = true
            for link in links.values { link.connection.cancel() }
            links.removeAll()
        }
        continuation.finish()
    }
}

/// Hosts a game: advertises it nearby and takes every phone that connects. The room decides
/// who gets a seat. It stays findable for the whole game, so a guest whose connection broke can
/// come back; `markStarted()` lets lists leave a game in play out.
public final class NearbyHost: NearbyTransport, @unchecked Sendable {
    /// Whether the game can be found, each time that changes.
    public let status: AsyncStream<NearbyStatus>
    private let statusContinuation: AsyncStream<NearbyStatus>.Continuation
    private let serviceType: String
    private let name: String
    /// Touched only on `queue`.
    private var info: [String: String]
    private var listener: NWListener?
    private var advertising = true
    private var stopped = false

    /// `serviceType` is like `_leluoware._tcp`; `name` is what browsers list.
    public init(serviceType: String, name: String, info: [String: String] = [:]) throws {
        self.serviceType = serviceType
        self.name = name
        self.info = info
        (status, statusContinuation) = AsyncStream.makeStream(of: NearbyStatus.self, bufferingPolicy: .bufferingNewest(1))
        super.init()
        let first = try NWListener(using: Nearby.parameters())
        queue.sync { listen(on: first) }
    }

    /// TXT key set once the game is under way.
    public static let startedKey = "started"

    private var service: NWListener.Service {
        NWListener.Service(name: name, type: serviceType, domain: nil, txtRecord: NWTXTRecord(info))
    }

    /// On `queue`.
    private func listen(on listener: NWListener) {
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .cancelled:
                return
            case .failed:
                // iOS can stop a listener while the app is in the background: start a new one,
                // so the guest can find the game again when this phone comes back.
                statusContinuation.yield(NearbyStatus(state))
                restart()
            default:
                statusContinuation.yield(NearbyStatus(state))
            }
        }
        listener.service = advertising ? service : nil
        listener.newConnectionHandler = { [weak self] connection in self?.adopt(connection) }
        listener.start(queue: queue)
    }

    /// On `queue`.
    private func restart() {
        listener?.cancel()
        listener = nil
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, !self.stopped, self.listener == nil,
                  let fresh = try? NWListener(using: Nearby.parameters()) else { return }
            self.listen(on: fresh)
        }
    }

    /// Stops or restarts listing the game.
    public func setAdvertising(_ on: Bool) {
        queue.async { [self] in
            advertising = on
            listener?.service = on ? service : nil
        }
    }

    /// The game is under way: still listed, for its guest to come back, but marked so that lists
    /// leave it out.
    public func markStarted() {
        queue.async { [self] in
            info[Self.startedKey] = "1"
            if advertising { listener?.service = service }
        }
    }

    public override func close() {
        queue.sync {
            stopped = true
            listener?.cancel()
            listener = nil
        }
        statusContinuation.finish()
        super.close()
    }
}

/// Lists the games nearby.
public final class NearbyBrowser: @unchecked Sendable {
    /// The games around, every time the list changes.
    public let games: AsyncStream<[NearbyGame]>
    /// Whether games can be found, each time that changes.
    public let status: AsyncStream<NearbyStatus>

    private let browser: NWBrowser
    private let continuation: AsyncStream<[NearbyGame]>.Continuation
    private let queue = DispatchQueue(label: "MatchKitNearby.browser")

    public init(serviceType: String) {
        (games, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: Nearby.parameters())
        let (status, statusContinuation) = AsyncStream.makeStream(of: NearbyStatus.self, bufferingPolicy: .bufferingNewest(1))
        self.status = status
        browser.stateUpdateHandler = { state in
            if case .cancelled = state { return statusContinuation.finish() }
            statusContinuation.yield(NearbyStatus(state))
        }
        browser.browseResultsChangedHandler = { [continuation] results, _ in
            let found = results.compactMap { result -> NearbyGame? in
                guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                var info: [String: String] = [:]
                if case let .bonjour(txt) = result.metadata { info = txt.dictionary }
                return NearbyGame(name: name, info: info, endpoint: result.endpoint)
            }
            continuation.yield(found.sorted { $0.name < $1.name })
        }
        browser.start(queue: queue)
    }

    /// A transport to the game's host. Its first `connected` event is the host.
    public func connect(to game: NearbyGame) -> NearbyTransport { NearbyTransport.connect(to: game) }

    public func stop() {
        browser.cancel()
        continuation.finish()
    }
}
#endif
