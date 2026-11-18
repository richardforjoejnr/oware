import Foundation

/// The relay: a small service that makes rooms with a code and passes messages between the phones
/// in a room (docs/ONLINE_PLAY.md §5). It never reads a room message; those ride inside `data`.
///
/// This file is the relay's wire format, version 1. Every message is one JSON object with a
/// `type`. The examples in `shared/vectors/relay-v1` are the contract: this code and the relay's
/// are both tested against them.
public enum Relay {
    /// Sent with `create`, `join` and `rejoin`. The relay serves the last two versions.
    public static let version = 1
    /// API Gateway closes a connection on a larger frame, and bills in steps of this size.
    public static let maxFrameBytes = 32 * 1024
    /// The phone that made the room. It is in charge of the game, as the host is in nearby play.
    public static let creator = PeerID("p0")
}

/// Phone → relay.
public enum RelayRequest: Sendable, Equatable {
    /// Which game, and which versions of the room protocol and the match format this phone
    /// speaks. A phone that joins a room made with other numbers is refused with `needsUpdate`.
    public struct Game: Sendable, Equatable {
        public var name: String
        public var protocolVersion: Int
        public var formatVersion: Int

        public init(name: String, protocolVersion: Int, formatVersion: Int) {
            self.name = name
            self.protocolVersion = protocolVersion
            self.formatVersion = formatVersion
        }
    }

    /// The creator's signed purchase, for when starting a game is paid (off at first).
    public struct Proof: Codable, Sendable, Equatable {
        /// `apple` or `google`: who signed it.
        public var store: String
        public var transaction: String

        public init(store: String, transaction: String) {
            self.store = store
            self.transaction = transaction
        }
    }

    /// The room message was not UTF-8 text, so it cannot ride inside `data`.
    public struct NotText: Error, Equatable {}

    /// Where a notification for this phone goes: its token from Apple, and which of Apple's two
    /// services gave it (`sandbox` for a build run from Xcode, `production` for every other).
    public struct Push: Codable, Sendable, Equatable {
        public enum Env: String, Codable, Sendable { case sandbox, production }
        public var token: String
        public var env: Env

        public init(token: String, env: Env) {
            self.token = token
            self.env = env
        }
    }

    case create(game: Game, seats: Int, install: String, proof: Proof?)
    case join(code: String, game: Game, install: String)
    /// Takes the same seat back with the token from `room`.
    case rejoin(code: String, token: String)
    /// A room message, to one peer or to everyone else in the room.
    case data(String, to: PeerID?)
    /// Ludo: asks the relay for the next roll.
    case roll
    case leave
    case ping
    /// This phone may be invited again: `player` is its player number, which other phones are
    /// given; `secret` proves later messages come from the same phone and is told only to the
    /// relay. Without `push` the phone cannot be notified.
    case register(game: String, player: String, secret: String, push: Push?)
    /// From the phone that made the room: notify `to` that `name` wants to play, with this room's code.
    case invite(player: String, secret: String, to: String, name: String)
    /// `on`: invitations from `who` are refused from now on. Off undoes it.
    case block(game: String, player: String, secret: String, who: String, on: Bool)
    /// "Not now" to an invitation: the phone waiting in that room is told.
    case decline(code: String, player: String)

    /// A room message as it comes from `Room`: JSON bytes.
    public static func data(_ message: Data, to peer: PeerID?) throws -> RelayRequest {
        guard let text = String(data: message, encoding: .utf8) else { throw NotText() }
        return .data(text, to: peer)
    }
}

/// Relay → phone.
public enum RelayEvent: Sendable, Equatable {
    public enum PeerState: String, Codable, Sendable {
        case joined
        /// Left on purpose.
        case left
        /// Its connection broke; it may come back with `rejoin`.
        case dropped
    }

    public enum Refusal: String, Sendable, CaseIterable {
        /// No room has that code (or it has closed), or the token is not that room's.
        case notFound
        case full
        /// Online play is switched off for now.
        case paused
        /// The room was made by another version of the app.
        case needsUpdate
        /// Starting a game needs the purchase.
        case needsUnlock
        /// Too many rooms or wrong codes from this phone or network.
        case tooMany
        /// The room was there but has closed or run out of time.
        case ended
        /// The player invited cannot be notified (the relay does not say why).
        case unreachable
        /// The relay could not read the message.
        case invalid
        /// A reason from a newer relay.
        case other
    }

    /// You are in. `peer` is you, `token` takes the seat back later, `peers` are already here.
    case room(code: String, peer: PeerID, token: String, peers: [PeerID])
    case peer(PeerID, PeerState)
    case data(String, from: PeerID)
    /// Ludo: roll number `n` of this room, the same for every phone.
    case rolled(n: Int, value: Int)
    case refused(Refusal)
    case pong
    case registered
    /// The notification is on its way to that player.
    case invited(to: String)
    case blocked(who: String, on: Bool)
    /// That player said "Not now" to the invitation.
    case declined(player: String)
    /// Something a newer relay says. Passed over.
    case unknown(String)
}

// MARK: - JSON

private enum Key: String, CodingKey {
    case type, v, game, `protocol`, format, seats, install, proof, code, token, to, from, data
    case peer, peers, state, n, value, reason
    case player, secret, push, name, who, on
}

extension RelayRequest: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        func game() throws -> Game {
            Game(name: try c.decode(String.self, forKey: .game),
                 protocolVersion: try c.decode(Int.self, forKey: .protocol),
                 formatVersion: try c.decode(Int.self, forKey: .format))
        }
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "create":
            self = .create(game: try game(), seats: try c.decode(Int.self, forKey: .seats),
                           install: try c.decode(String.self, forKey: .install),
                           proof: try c.decodeIfPresent(Proof.self, forKey: .proof))
        case "join":
            self = .join(code: try c.decode(String.self, forKey: .code), game: try game(),
                         install: try c.decode(String.self, forKey: .install))
        case "rejoin":
            self = .rejoin(code: try c.decode(String.self, forKey: .code), token: try c.decode(String.self, forKey: .token))
        case "data":
            self = .data(try c.decode(String.self, forKey: .data), to: try c.decodeIfPresent(String.self, forKey: .to).map(PeerID.init))
        case "roll": self = .roll
        case "leave": self = .leave
        case "ping": self = .ping
        case "register":
            self = .register(game: try c.decode(String.self, forKey: .game), player: try c.decode(String.self, forKey: .player),
                             secret: try c.decode(String.self, forKey: .secret), push: try c.decodeIfPresent(Push.self, forKey: .push))
        case "invite":
            self = .invite(player: try c.decode(String.self, forKey: .player), secret: try c.decode(String.self, forKey: .secret),
                           to: try c.decode(String.self, forKey: .to), name: try c.decode(String.self, forKey: .name))
        case "block":
            self = .block(game: try c.decode(String.self, forKey: .game), player: try c.decode(String.self, forKey: .player),
                          secret: try c.decode(String.self, forKey: .secret), who: try c.decode(String.self, forKey: .who),
                          on: try c.decode(Bool.self, forKey: .on))
        case "decline":
            self = .decline(code: try c.decode(String.self, forKey: .code), player: try c.decode(String.self, forKey: .player))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown request \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        func write(_ game: Game) throws {
            try c.encode(Relay.version, forKey: .v)
            try c.encode(game.name, forKey: .game)
            try c.encode(game.protocolVersion, forKey: .protocol)
            try c.encode(game.formatVersion, forKey: .format)
        }
        switch self {
        case let .create(game, seats, install, proof):
            try c.encode("create", forKey: .type)
            try write(game)
            try c.encode(seats, forKey: .seats)
            try c.encode(install, forKey: .install)
            try c.encodeIfPresent(proof, forKey: .proof)
        case let .join(code, game, install):
            try c.encode("join", forKey: .type)
            try write(game)
            try c.encode(code, forKey: .code)
            try c.encode(install, forKey: .install)
        case let .rejoin(code, token):
            try c.encode("rejoin", forKey: .type)
            try c.encode(Relay.version, forKey: .v)
            try c.encode(code, forKey: .code)
            try c.encode(token, forKey: .token)
        case let .data(text, peer):
            try c.encode("data", forKey: .type)
            try c.encodeIfPresent(peer?.raw, forKey: .to)
            try c.encode(text, forKey: .data)
        case .roll: try c.encode("roll", forKey: .type)
        case .leave: try c.encode("leave", forKey: .type)
        case .ping: try c.encode("ping", forKey: .type)
        case let .register(game, player, secret, push):
            try c.encode("register", forKey: .type)
            try c.encode(Relay.version, forKey: .v)
            try c.encode(game, forKey: .game)
            try c.encode(player, forKey: .player)
            try c.encode(secret, forKey: .secret)
            try c.encodeIfPresent(push, forKey: .push)
        case let .invite(player, secret, to, name):
            try c.encode("invite", forKey: .type)
            try c.encode(Relay.version, forKey: .v)
            try c.encode(player, forKey: .player)
            try c.encode(secret, forKey: .secret)
            try c.encode(to, forKey: .to)
            try c.encode(name, forKey: .name)
        case let .block(game, player, secret, who, on):
            try c.encode("block", forKey: .type)
            try c.encode(Relay.version, forKey: .v)
            try c.encode(game, forKey: .game)
            try c.encode(player, forKey: .player)
            try c.encode(secret, forKey: .secret)
            try c.encode(who, forKey: .who)
            try c.encode(on, forKey: .on)
        case let .decline(code, player):
            try c.encode("decline", forKey: .type)
            try c.encode(Relay.version, forKey: .v)
            try c.encode(code, forKey: .code)
            try c.encode(player, forKey: .player)
        }
    }
}

extension RelayEvent: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "room":
            self = .room(code: try c.decode(String.self, forKey: .code), peer: PeerID(try c.decode(String.self, forKey: .peer)),
                         token: try c.decode(String.self, forKey: .token),
                         peers: try c.decode([String].self, forKey: .peers).map(PeerID.init))
        case "peer":
            guard let state = PeerState(rawValue: try c.decode(String.self, forKey: .state)) else {
                self = .unknown(type)
                return
            }
            self = .peer(PeerID(try c.decode(String.self, forKey: .peer)), state)
        case "data":
            self = .data(try c.decode(String.self, forKey: .data), from: PeerID(try c.decode(String.self, forKey: .from)))
        case "rolled":
            self = .rolled(n: try c.decode(Int.self, forKey: .n), value: try c.decode(Int.self, forKey: .value))
        case "refused":
            self = .refused(Refusal(rawValue: try c.decode(String.self, forKey: .reason)) ?? .other)
        case "pong": self = .pong
        case "registered": self = .registered
        case "invited": self = .invited(to: try c.decode(String.self, forKey: .to))
        case "blocked": self = .blocked(who: try c.decode(String.self, forKey: .who), on: try c.decode(Bool.self, forKey: .on))
        case "declined": self = .declined(player: try c.decode(String.self, forKey: .player))
        default: self = .unknown(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .room(code, peer, token, peers):
            try c.encode("room", forKey: .type)
            try c.encode(code, forKey: .code)
            try c.encode(peer.raw, forKey: .peer)
            try c.encode(token, forKey: .token)
            try c.encode(peers.map(\.raw), forKey: .peers)
        case let .peer(peer, state):
            try c.encode("peer", forKey: .type)
            try c.encode(peer.raw, forKey: .peer)
            try c.encode(state, forKey: .state)
        case let .data(text, peer):
            try c.encode("data", forKey: .type)
            try c.encode(peer.raw, forKey: .from)
            try c.encode(text, forKey: .data)
        case let .rolled(n, value):
            try c.encode("rolled", forKey: .type)
            try c.encode(n, forKey: .n)
            try c.encode(value, forKey: .value)
        case let .refused(reason):
            try c.encode("refused", forKey: .type)
            try c.encode(reason.rawValue, forKey: .reason)
        case .pong: try c.encode("pong", forKey: .type)
        case .registered: try c.encode("registered", forKey: .type)
        case let .invited(to):
            try c.encode("invited", forKey: .type)
            try c.encode(to, forKey: .to)
        case let .blocked(who, on):
            try c.encode("blocked", forKey: .type)
            try c.encode(who, forKey: .who)
            try c.encode(on, forKey: .on)
        case let .declined(player):
            try c.encode("declined", forKey: .type)
            try c.encode(player, forKey: .player)
        case let .unknown(type): try c.encode(type, forKey: .type)
        }
    }
}

// MARK: - Room codes

/// What a friend types or taps to join: six characters from 31 that are hard to confuse
/// (no `0 O 1 I L`), about 890 million codes.
public struct RoomCode: Hashable, Sendable, CustomStringConvertible {
    public static let alphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
    public static let length = 6

    public let text: String

    /// As typed: any case, with spaces or hyphens.
    public init?(_ typed: String) {
        let tidy = typed.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard tidy.count == Self.length, tidy.allSatisfy(Self.alphabet.contains) else { return nil }
        text = tidy
    }

    /// From an invitation link: `https://leluoware.com/<app>/join?c=<code>` (what the apps share),
    /// the app's own `<scheme>://join?c=<code>`, or the code as the last part of the path
    /// (`…/join/<code>`).
    public init?(link: URL) {
        let parts = link.pathComponents.filter { $0 != "/" }
        let isJoin = parts.last == "join" || link.host == "join" && parts.isEmpty
        if isJoin, let typed = URLComponents(url: link, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "c" })?.value, let code = RoomCode(typed) {
            self = code
            return
        }
        guard parts.count >= 2, parts[parts.count - 2] == "join", let code = RoomCode(parts[parts.count - 1]) else { return nil }
        self = code
    }

    /// What a player typed or pasted: a code, or a whole invitation link (or a message with one in it).
    public init?(pasted text: String) {
        if let code = RoomCode(text) {
            self = code
            return
        }
        for word in text.split(whereSeparator: \.isWhitespace) {
            if let url = URL(string: String(word)), url.scheme != nil, let code = RoomCode(link: url) {
                self = code
                return
            }
        }
        return nil
    }

    public var description: String { text }

    /// For VoiceOver, which would otherwise try to read the code as a word.
    public var spelledOut: String { text.map(String.init).joined(separator: " ") }
}
