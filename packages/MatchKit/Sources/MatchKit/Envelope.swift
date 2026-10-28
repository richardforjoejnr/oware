import Foundation

public enum MatchKit {
    /// The room protocol. Bump when messages change; a phone refuses newer versions and the
    /// players are told to update.
    public static let protocolVersion = 1
}

/// Every message between phones.
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
