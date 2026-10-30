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
/// both have asked), each player's sowing speed (both phones sow at the slower), and the start
/// handshake: nobody moves until both phones have acknowledged the same opening.
struct OwareTable: Codable, Sendable, Equatable {
    var match: OwareMatch
    var rematchAsked: Set<Player> = []
    var paces: [Player: Double] = [:]
    /// Players whose phone has replayed the opening and got the host's fingerprint.
    var ready: Set<Player> = []
    /// The host's fingerprint of the position now (`GameState.fingerprint`), for phones to check
    /// their own replay against.
    var stateHash: String?
    /// A phone replayed the opening differently (another version of the game): no game.
    var isOutOfStep = false

    /// The speed both phones sow at: the slower of the two, once both are known.
    var sharedPace: Double? { paces.values.min() }
    /// Both phones hold the same opening and are ready: moves may be played.
    var isStarted: Bool { ready.count == Player.allCases.count && !isOutOfStep }

    /// A new table on the host, stamped with the opening's fingerprint.
    static func opening(_ match: OwareMatch, paces: [Player: Double] = [:]) -> OwareTable {
        OwareTable(match: match, paces: paces, stateHash: try? match.state().fingerprint)
    }
}

/// What a phone may ask the host: a move, resign or rematch, its sowing speed, or to start, with
/// the fingerprint of the opening it replayed.
enum TableIntent: Codable, Sendable, Equatable {
    case game(OwareIntent)
    case pace(Double)
    case ready(stateHash: String)
}

/// The host's checks, through the engine. Seat 0 (the host) is South, seat 1 North.
struct OwareRoomRules: RoomRules {
    /// A move before both phones are ready, or after they were found out of step.
    struct NotStarted: Error {}

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
        case let .ready(stateHash):
            guard !table.isStarted else { return table }
            if stateHash == (try table.match.state().fingerprint) {
                next.ready.insert(player)
            } else {
                next.isOutOfStep = true
            }
            return next
        case let .game(intent):
            guard table.isStarted else { throw NotStarted() }
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
                // Both asked, so both are here: the new game starts at once.
                next.ready = Set(Player.allCases)
            }
        }
        next.stateHash = try? next.match.state().fingerprint
        return next
    }

    func shouldReplace(_ current: OwareTable, with snapshot: OwareTable) -> Bool {
        if snapshot.match.supersedes(current.match) { return true }
        // The same match, with more asked for a rematch, more speeds known or more phones ready.
        return snapshot.match == current.match && snapshot.rematchAsked.isSuperset(of: current.rematchAsked)
            && Set(snapshot.paces.keys).isSuperset(of: current.paces.keys)
            && snapshot.ready.isSuperset(of: current.ready) && (snapshot.isOutOfStep || !current.isOutOfStep)
            && snapshot != current
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
    /// With the side's colour added when both players have the same name (Oware Player).
    var opponentName: String? {
        let theirSeat = room.mySeat == 0 ? 1 : 0
        guard let theirs = room.seats[theirSeat]?.name else { return nil }
        let mine = room.mySeat.flatMap { room.seats[$0]?.name } ?? myName
        return NearbyLobby.tellApart(theirs, from: mine, side: OwareRoomRules.player(seat: theirSeat))
    }
    /// Whether this phone has pressed Ready (and the host has it).
    var iAmReady: Bool { mySide.map { table?.ready.contains($0) ?? false } ?? false }
    var table: OwareTable? { room.match }

    /// This phone's sowing speed (`AppSettings.effectiveSpeed`), shared on Ready.
    private let pace: Double
    private let myName: String

    init(hosting match: OwareMatch, name: String, pace: Double = AppSettings.AnimationSpeed.normal.rawValue,
         transport: any MatchTransport, clock: any RoomClock = SystemClock()) {
        self.pace = pace
        myName = name
        room = Room(hosting: OwareTable.opening(match, paces: [.south: pace]), name: name, rules: OwareRoomRules(),
                    transport: transport, clock: clock)
        room.onEvent = { [weak self] in self?.handle($0) }
    }

    init(joiningAs name: String, pace: Double = AppSettings.AnimationSpeed.normal.rawValue,
         transport: any MatchTransport, clock: any RoomClock = SystemClock()) {
        self.pace = pace
        myName = name
        room = Room(joiningAs: name, rules: OwareRoomRules(), transport: transport, clock: clock)
        room.onEvent = { [weak self] in self?.handle($0) }
    }

    private func handle(_ event: RoomEvent<OwareTable>) {
        switch event {
        case let .joinRequest(peer, name):
            joinRequests.append(JoinRequest(peer: peer, name: name))
        case .seated:
            joinRequests = []
        default:
            break
        }
        onEvent?(event)
    }

    private var saidReady = false

    /// The Ready button: the guest's sowing speed (the host's went in with the match), then ready,
    /// with the fingerprint of the opening as this phone's own engine replays it. The game starts
    /// once both have said it.
    func ready() async {
        guard !saidReady, let table = room.match, let fingerprint = try? table.match.state().fingerprint else { return }
        saidReady = true
        if room.role == .guest { try? await room.send(.pace(pace)) }
        try? await room.send(.ready(stateHash: fingerprint))
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
