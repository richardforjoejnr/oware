import Foundation

/// A phone in a match, as its transport knows it. Not shown to players.
public struct PeerID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let raw: String
    public init(_ raw: String = UUID().uuidString) { self.raw = raw }
    public var description: String { raw }
}

public enum TransportEvent: Sendable {
    /// A peer is reachable. Sent again for the same peer when the link to it is new (after a
    /// reconnect): messages in between may have been lost, so the room catches up.
    case connected(PeerID)
    case disconnected(PeerID)
    /// A peer left for good, as the carrier itself knows (the relay's `left`). The room's own
    /// goodbye says the same; either is enough, and it may be lost.
    case left(PeerID)
    case received(Data, from: PeerID)
}

/// Moves whole messages between phones. Nearby play uses `NearbyTransport` (MatchKitNearby);
/// tests and demos use `LoopbackTransport`; online play adds one that talks to the relay (`RelayMessage`).
public protocol MatchTransport: AnyObject, Sendable {
    var me: PeerID { get }
    var events: AsyncStream<TransportEvent> { get }
    /// To one peer, or everyone when `to` is nil.
    func send(_ data: Data, to peer: PeerID?) async throws
    func close()
}
