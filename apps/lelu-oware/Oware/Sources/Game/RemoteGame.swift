import Foundation
import MatchKit
import Observation
import OwareEngine

/// The other player in a game on two phones (docs/NEARBY_PLAY.md).
struct RemoteGame: Codable, Hashable, Sendable {
    enum Via: String, Codable, Sendable { case nearby, online }

    /// The host plays South, the guest North.
    var mySide: Player
    var opponentName: String
    var via: Via = .nearby
}

/// What the phones share: the match, who has asked for another game (a rematch starts only once
/// both have asked), and each player's sowing speed (both phones sow at the slower).
struct OwareTable: Codable, Sendable, Equatable {
    var match: OwareMatch
    var rematchAsked: Set<Player> = []
    var paces: [Player: Double] = [:]

    /// The speed both phones sow at: the slower of the two, once both are known.
    var sharedPace: Double? { paces.values.min() }
}

/// What a phone may ask the host: a move, resign or rematch, or its sowing speed.
enum TableIntent: Codable, Sendable, Equatable {
    case game(OwareIntent)
    case pace(Double)
}

/// The host's checks, through the engine. Seat 0 (the host) is South, seat 1 North.
struct OwareRoomRules: RoomRules {
    let seatCount = 2

    static func player(seat: Int) -> Player { seat == 0 ? .south : .north }

    func applying(_ intent: TableIntent, from seat: Int, to table: OwareTable) throws -> OwareTable {
        let player = Self.player(seat: seat)
        var next = table
        let game: OwareIntent
        switch intent {
        case let .pace(pace):
            next.paces[player] = min(max(pace, 0.1), AppSettings.AnimationSpeed.instant.rawValue)
            return next
        case let .game(intent):
            game = intent
        }
        switch game {
        case .play, .resign:
            next.match = try table.match.applying(game, from: player)
        case .rematch:
            guard try table.match.state().isOver else { throw OwareMatch.Failure.gameNotOver }
            next.rematchAsked.insert(player)
            if next.rematchAsked.count == seatCount {
                next.match = try table.match.applying(.rematch, from: player)
                next.rematchAsked = []
            }
        }
        return next
    }

    func shouldReplace(_ current: OwareTable, with snapshot: OwareTable) -> Bool {
        if snapshot.match.supersedes(current.match) { return true }
        // The same match, with more asked for a rematch or more speeds known.
        return snapshot.match == current.match && snapshot.rematchAsked.isSuperset(of: current.rematchAsked)
            && Set(snapshot.paces.keys).isSuperset(of: current.paces.keys) && snapshot != current
    }
}

/// Room ⇄ session: what a `GameSession` needs from a game on two phones.
@MainActor
@Observable
final class MatchLink {
    struct JoinRequest: Equatable { let peer: PeerID; let name: String }

    let room: Room<OwareRoomRules>
    /// Host: people asking to play.
    private(set) var joinRequests: [JoinRequest] = []
    /// Set by the session, which turns room events into moves on the board.
    @ObservationIgnored var onEvent: (@MainActor (RoomEvent<OwareTable>) -> Void)?

    var isHost: Bool { room.role == .host }
    var mySide: Player? { room.mySeat.map(OwareRoomRules.player(seat:)) }
    var opponentName: String? { room.seats[room.mySeat == 0 ? 1 : 0]?.name }
    var table: OwareTable? { room.match }

    /// This phone's sowing speed (`AppSettings.effectiveSpeed`), shared once seated.
    private let pace: Double

    init(hosting match: OwareMatch, name: String, pace: Double = AppSettings.AnimationSpeed.normal.rawValue,
         transport: any MatchTransport, clock: any RoomClock = SystemClock()) {
        self.pace = pace
        room = Room(hosting: OwareTable(match: match, paces: [.south: pace]), name: name, rules: OwareRoomRules(),
                    transport: transport, clock: clock)
        room.onEvent = { [weak self] in self?.handle($0) }
    }

    init(joiningAs name: String, pace: Double = AppSettings.AnimationSpeed.normal.rawValue,
         transport: any MatchTransport, clock: any RoomClock = SystemClock()) {
        self.pace = pace
        room = Room(joiningAs: name, rules: OwareRoomRules(), transport: transport, clock: clock)
        room.onEvent = { [weak self] in self?.handle($0) }
    }

    private func handle(_ event: RoomEvent<OwareTable>) {
        switch event {
        case let .joinRequest(peer, name):
            joinRequests.append(JoinRequest(peer: peer, name: name))
        case .seated:
            joinRequests = []
            // The guest tells the host its speed; the host's went in with the match.
            if room.role == .guest {
                let pace = pace
                Task { try? await room.send(.pace(pace)) }
            }
        default:
            break
        }
        onEvent?(event)
    }

    func accept(_ peer: PeerID) async {
        joinRequests.removeAll { $0.peer == peer }
        await room.accept(peer)
    }

    func decline(_ peer: PeerID) async {
        joinRequests.removeAll { $0.peer == peer }
        await room.decline(peer)
    }

    /// Host: applied at once, or refused by the rules. Guest: sent to the host.
    func send(_ intent: OwareIntent) async {
        try? await room.send(.game(intent))
    }

    func tick() async { await room.tick() }

    func startHeartbeat() { room.startHeartbeat() }

    func leave() async { await room.leave() }
}
