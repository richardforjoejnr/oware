import Foundation

public enum MatchKit {
    /// The room protocol. Bump when messages change; a phone refuses every other version and the
    /// players are told who should update. Version 2 (November 2026) gave the messages a plain
    /// JSON form that other languages can write (`shared/vectors/room-v2`).
    public static let protocolVersion = 2
}

/// Every message between phones. `protocolVersion` keeps its name and place in every version:
/// it is how a phone with any version of the app knows it cannot read the rest.
public struct Envelope<Body: Codable & Sendable>: Codable, Sendable {
    public var protocolVersion: Int
    /// Per sender, so repeats and stale messages are dropped.
    public var sequence: Int
    public var body: Body

    public init(protocolVersion: Int, sequence: Int, body: Body) {
        self.protocolVersion = protocolVersion
        self.sequence = sequence
        self.body = body
    }
}

extension Envelope: Equatable where Body: Equatable {}

/// Read first, so a message from a newer app is recognised before its body is misread.
public struct EnvelopeHeader: Decodable, Sendable {
    public var protocolVersion: Int
}

/// Keeps only messages newer than the last one heard from each sender.
public struct SequenceFilter: Sendable {
    private var last: [PeerID: Int] = [:]

    public init() {}

    public mutating func accept(_ sequence: Int, from peer: PeerID) -> Bool {
        if let seen = last[peer], sequence <= seen { return false }
        last[peer] = sequence
        return true
    }

    public mutating func forget(_ peer: PeerID) { last[peer] = nil }
}
