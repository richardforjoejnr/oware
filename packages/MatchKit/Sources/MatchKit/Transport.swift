import Foundation

/// A phone in a match, as its transport knows it. Not shown to players.
public struct PeerID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let raw: String
    public init(_ raw: String = UUID().uuidString) { self.raw = raw }
    public var description: String { raw }
}

public enum TransportEvent: Sendable {
    case connected(PeerID)
    case disconnected(PeerID)
    case received(Data, from: PeerID)
}

/// Moves whole messages between phones. Nearby play uses `NearbyTransport` (MatchKitNearby);
/// tests and demos use `LoopbackTransport`; online play will add a Game Center one.
public protocol MatchTransport: AnyObject, Sendable {
    var me: PeerID { get }
    var events: AsyncStream<TransportEvent> { get }
    /// To one peer, or everyone when `to` is nil.
    func send(_ data: Data, to peer: PeerID?) async throws
    func close()
}
