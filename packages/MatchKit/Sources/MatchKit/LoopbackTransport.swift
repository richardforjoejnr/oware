import Foundation

/// An in-memory transport for tests, UI tests and the demo player. Connect two with
/// `connect(_:)`; set `isQuiet` to drop everything both ways, like walking out of range.
public final class LoopbackTransport: MatchTransport, @unchecked Sendable {
    public let me: PeerID
    public let events: AsyncStream<TransportEvent>

    private let continuation: AsyncStream<TransportEvent>.Continuation
    private let lock = NSLock()
    private var links: [PeerID: LoopbackTransport] = [:]
    private var quiet = false
    private var closed = false

    public init(me: PeerID = PeerID()) {
        self.me = me
        (events, continuation) = AsyncStream.makeStream()
    }

    public var isQuiet: Bool {
        get { lock.sync { quiet } }
        set { lock.sync { quiet = newValue } }
    }

    /// Links the two, and each sees the other connect.
    public func connect(_ other: LoopbackTransport) {
        lock.sync { links[other.me] = other }
        other.lock.sync { other.links[me] = self }
        continuation.yield(.connected(other.me))
        other.continuation.yield(.connected(me))
    }

    public func send(_ data: Data, to peer: PeerID?) async throws {
        let targets: [LoopbackTransport] = lock.sync {
            guard !quiet, !closed else { return [] }
            if let peer { return links[peer].map { [$0] } ?? [] }
            return Array(links.values)
        }
        for target in targets { target.deliver(data, from: me) }
    }

    private func deliver(_ data: Data, from peer: PeerID) {
        let ok = lock.sync { !quiet && !closed }
        if ok { continuation.yield(.received(data, from: peer)) }
    }

    private func unlink(_ peer: PeerID) {
        let had = lock.sync { links.removeValue(forKey: peer) != nil }
        if had { continuation.yield(.disconnected(peer)) }
    }

    public func close() {
        let others: [LoopbackTransport] = lock.sync {
            closed = true
            defer { links.removeAll() }
            return Array(links.values)
        }
        for other in others { other.unlink(me) }
        continuation.finish()
    }
}
