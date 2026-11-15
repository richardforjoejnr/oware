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

/// Drops repeats and messages far older than the newest heard from that sender.
///
/// A message that arrives a little late is still taken. Through the relay two messages sent
/// close together can swap places (each is handled on its own), and dropping the earlier one lost
/// a player's sowing speed sent just before Ready, or a move sent beside a ping. Order does not
/// matter to a room: the host checks every intent against the rules, and a guest takes a snapshot
/// only if it carries the match further.
public struct SequenceFilter: Sendable {
    /// How far behind the newest a late message may be.
    static let window = 64

    private struct Heard: Sendable {
        var newest: Int
        var recent: Set<Int>
    }

    private var heard: [PeerID: Heard] = [:]

    public init() {}

    public mutating func accept(_ sequence: Int, from peer: PeerID) -> Bool {
        guard var mine = heard[peer] else {
            heard[peer] = Heard(newest: sequence, recent: [sequence])
            return true
        }
        guard sequence > mine.newest - Self.window, !mine.recent.contains(sequence) else { return false }
        mine.recent.insert(sequence)
        if sequence > mine.newest {
            mine.newest = sequence
            mine.recent = mine.recent.filter { $0 > sequence - Self.window }
        }
        heard[peer] = mine
        return true
    }

    public mutating func forget(_ peer: PeerID) { heard[peer] = nil }
}
