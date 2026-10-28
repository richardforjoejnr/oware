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
/// who gets a seat.
public final class NearbyHost: NearbyTransport, @unchecked Sendable {
    private let listener: NWListener
    private let service: NWListener.Service

    /// `serviceType` is like `_leluoware._tcp`; `name` is what browsers list.
    public init(serviceType: String, name: String, info: [String: String] = [:]) throws {
        listener = try NWListener(using: Nearby.parameters())
        service = NWListener.Service(name: name, type: serviceType, domain: nil, txtRecord: NWTXTRecord(info))
        super.init()
        listener.service = service
        listener.newConnectionHandler = { [weak self] connection in self?.adopt(connection) }
        listener.start(queue: queue)
    }

    /// Stops or restarts listing the game, for example once every seat is taken.
    public func setAdvertising(_ on: Bool) {
        queue.async { [self] in listener.service = on ? service : nil }
    }

    public override func close() {
        listener.cancel()
        super.close()
    }
}

/// Lists the games nearby.
public final class NearbyBrowser: @unchecked Sendable {
    /// The games around, every time the list changes.
    public let games: AsyncStream<[NearbyGame]>

    private let browser: NWBrowser
    private let continuation: AsyncStream<[NearbyGame]>.Continuation
    private let queue = DispatchQueue(label: "MatchKitNearby.browser")

    public init(serviceType: String) {
        (games, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: Nearby.parameters())
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
    public func connect(to game: NearbyGame) -> NearbyTransport {
        let transport = NearbyTransport()
        transport.adopt(NWConnection(to: game.endpoint, using: Nearby.parameters()))
        return transport
    }

    public func stop() {
        browser.cancel()
        continuation.finish()
    }
}
#endif
