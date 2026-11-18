import Foundation
import MatchKit
import MatchKitOnline
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
/// both have asked; the other player may say not now, and a request nobody answers lapses), each
/// player's sowing speed (both phones sow at the slower), and the start handshake: nobody moves
/// until both phones have acknowledged the same opening.
struct OwareTable: Sendable, Equatable {
    var match: OwareMatch
    var rematchAsked: Set<Player> = []
    /// Who said not now to the last request for a rematch. Gone when someone asks again.
    var rematchDeclinedBy: Player?
    /// Whose request for a rematch went unanswered and lapsed. Gone when someone asks again.
    var rematchLapsedFor: Player?
    /// How many requests for a rematch have ended without one (declined or lapsed). A snapshot
    /// with more is newer, though fewer players are asking in it.
    var rematchRound = 0
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

/// What a phone may ask the host: a move, resign or rematch, not now to the other player's
/// rematch, its sowing speed, or to start, with the fingerprint of the opening it replayed.
enum TableIntent: Sendable, Equatable {
    case game(OwareIntent)
    /// Not now, to the other player's request for a rematch.
    case declineRematch
    case pace(Double)
    case ready(stateHash: String)
}

// MARK: - JSON (room protocol version 2, pinned by shared/vectors/room-v2/oware)

/// Players are numbers (0 South, 1 North), sets are lists in order, and `paces` is an object
/// keyed by the player's number: `{"0": 0.35, "1": 0.6}`. `rematchDeclinedBy`, `rematchLapsedFor`
/// and `rematchRound` came after the first builds that spoke version 2: they are left out until
/// they mean something, so a table with no rematch declined or lapsed is written as it always was.
extension OwareTable: Codable {
    private enum Key: String, CodingKey {
        case match, rematchAsked, paces, ready, stateHash, isOutOfStep, rematchDeclinedBy, rematchLapsedFor, rematchRound
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        match = try c.decode(OwareMatch.self, forKey: .match)
        rematchAsked = Set(try c.decode([Player].self, forKey: .rematchAsked))
        ready = Set(try c.decode([Player].self, forKey: .ready))
        for (number, pace) in try c.decode([String: Double].self, forKey: .paces) {
            guard let player = Int(number).flatMap(Player.init(rawValue:)) else {
                throw DecodingError.dataCorruptedError(forKey: .paces, in: c, debugDescription: "no player \(number)")
            }
            paces[player] = pace
        }
        stateHash = try c.decodeIfPresent(String.self, forKey: .stateHash)
        isOutOfStep = try c.decode(Bool.self, forKey: .isOutOfStep)
        rematchDeclinedBy = try c.decodeIfPresent(Player.self, forKey: .rematchDeclinedBy)
        rematchLapsedFor = try c.decodeIfPresent(Player.self, forKey: .rematchLapsedFor)
        rematchRound = try c.decodeIfPresent(Int.self, forKey: .rematchRound) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(match, forKey: .match)
        try c.encode(rematchAsked.sorted { $0.rawValue < $1.rawValue }, forKey: .rematchAsked)
        try c.encode(ready.sorted { $0.rawValue < $1.rawValue }, forKey: .ready)
        try c.encode(Dictionary(uniqueKeysWithValues: paces.map { (String($0.key.rawValue), $0.value) }), forKey: .paces)
        try c.encodeIfPresent(stateHash, forKey: .stateHash)
        try c.encode(isOutOfStep, forKey: .isOutOfStep)
        try c.encodeIfPresent(rematchDeclinedBy, forKey: .rematchDeclinedBy)
        try c.encodeIfPresent(rematchLapsedFor, forKey: .rematchLapsedFor)
        if rematchRound != 0 { try c.encode(rematchRound, forKey: .rematchRound) }
    }
}

/// One object with a `type`: `play` (`house`), `resign`, `rematch`, `declineRematch`, `pace` (`pace`),
/// `ready` (`stateHash`).
extension TableIntent: Codable {
    private enum Key: String, CodingKey { case type, house, pace, stateHash }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "play": self = .game(.play(house: try c.decode(Int.self, forKey: .house)))
        case "resign": self = .game(.resign)
        case "rematch": self = .game(.rematch)
        case "declineRematch": self = .declineRematch
        case "pace": self = .pace(try c.decode(Double.self, forKey: .pace))
        case "ready": self = .ready(stateHash: try c.decode(String.self, forKey: .stateHash))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown intent \(type)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .game(.play(house)):
            try c.encode("play", forKey: .type)
            try c.encode(house, forKey: .house)
        case .game(.resign): try c.encode("resign", forKey: .type)
        case .game(.rematch): try c.encode("rematch", forKey: .type)
        case .declineRematch: try c.encode("declineRematch", forKey: .type)
        case let .pace(pace):
            try c.encode("pace", forKey: .type)
            try c.encode(pace, forKey: .pace)
        case let .ready(stateHash):
            try c.encode("ready", forKey: .type)
            try c.encode(stateHash, forKey: .stateHash)
        }
    }
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
        case .declineRematch:
            // Only an answer to the other player's request; anything else changes nothing.
            guard table.rematchAsked == [player.opponent] else { return table }
            next.rematchAsked = []
            next.rematchDeclinedBy = player
            next.rematchLapsedFor = nil
            next.rematchRound += 1
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
            // A new request: what happened to the last one is no longer news.
            next.rematchDeclinedBy = nil
            next.rematchLapsedFor = nil
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

    /// The phone in charge: a request for a rematch that nobody answered in time is over. Nil
    /// when one player is not waiting on the other.
    static func lapsing(_ table: OwareTable) -> OwareTable? {
        guard table.rematchAsked.count == 1, let asker = table.rematchAsked.first else { return nil }
        var next = table
        next.rematchAsked = []
        next.rematchLapsedFor = asker
        next.rematchDeclinedBy = nil
        next.rematchRound += 1
        return next
    }

    func shouldReplace(_ current: OwareTable, with snapshot: OwareTable) -> Bool {
        if snapshot.match.supersedes(current.match) { return true }
        guard snapshot.match == current.match else { return false }
        // A request for a rematch ended (declined or lapsed) since: newer, though nobody is asking.
        if snapshot.rematchRound != current.rematchRound { return snapshot.rematchRound > current.rematchRound }
        // The same match, with more asked for a rematch, more speeds known or more phones ready.
        return snapshot.rematchAsked.isSuperset(of: current.rematchAsked)
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
    /// Guest: a new connection to the host, after the last one broke (nil: not reachable now).
    /// While the host is "reconnecting" this is tried every couple of seconds, until it is back
    /// or the seat is lost.
    @ObservationIgnored var rejoin: (@MainActor () -> (any MatchTransport)?)?
    @ObservationIgnored private var rejoining: Task<Void, Never>?
    /// New connections made to the host so far (for tests).
    private(set) var rejoins = 0
    /// Between tries to reach the host again.
    static let rejoinInterval: Duration = .seconds(2)
    /// How long a request for a rematch waits for the other player's answer, in seconds.
    static let rematchWait: Double = 60
    /// The phone in charge: the request being waited on, and when it was made.
    @ObservationIgnored private var rematchWaiting: (asked: Set<Player>, round: Int, since: Double)?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    /// Online: this phone's place at the relay, to save with the game (`OnlineSave`).
    @ObservationIgnored var relaySeat: (@MainActor () -> OnlineTransport.Seat?)?

    var isHost: Bool { room.role == .host }
    var mySide: Player? { room.mySeat.map(OwareRoomRules.player(seat:)) }
    /// With the side's colour added when both players have the same name (Oware Player).
    var opponentName: String? {
        let theirSeat = room.mySeat == 0 ? 1 : 0
        guard let theirs = room.seats[theirSeat]?.name else { return nil }
        let mine = room.mySeat.flatMap { room.seats[$0]?.name } ?? myName
        return NearbyLobby.tellApart(theirs, from: mine, side: OwareRoomRules.player(seat: theirSeat))
    }
    /// The other player's player number and name, once their phone has said who it is.
    var opponentPlayer: (id: String, name: String)? {
        guard let mine = room.mySeat else { return nil }
        let theirs = mine == 0 ? 1 : 0
        guard let id = room.players[theirs], let name = room.seats[theirs]?.name else { return nil }
        return (id, name)
    }
    /// Whether this phone has pressed Ready (and the host has it).
    var iAmReady: Bool { mySide.map { table?.ready.contains($0) ?? false } ?? false }
    var table: OwareTable? { room.match }

    /// This phone's sowing speed (`AppSettings.effectiveSpeed`), shared on Ready.
    private let pace: Double
    private let myName: String
    private let clock: any RoomClock

    init(hosting match: OwareMatch, name: String, pace: Double = AppSettings.AnimationSpeed.normal.rawValue,
         transport: any MatchTransport, clock: any RoomClock = SystemClock(), timing: RoomTiming = .nearby) {
        self.pace = pace
        myName = name
        self.clock = clock
        room = Room(hosting: OwareTable.opening(match, paces: [.south: pace]), name: name, rules: OwareRoomRules(),
                    transport: transport, clock: clock, timing: timing)
        room.onEvent = { [weak self] in self?.handle($0) }
    }

    init(joiningAs name: String, pace: Double = AppSettings.AnimationSpeed.normal.rawValue,
         transport: any MatchTransport, clock: any RoomClock = SystemClock(), timing: RoomTiming = .nearby) {
        self.pace = pace
        myName = name
        self.clock = clock
        room = Room(joiningAs: name, rules: OwareRoomRules(), transport: transport, clock: clock, timing: timing)
        room.onEvent = { [weak self] in self?.handle($0) }
    }

    /// Back in a game from before the app was closed: the same seat, and the match as it was saved.
    init(resuming save: OnlineSave, pace: Double = AppSettings.AnimationSpeed.normal.rawValue,
         transport: any MatchTransport, clock: any RoomClock = SystemClock(), timing: RoomTiming = .online) {
        self.pace = pace
        myName = save.room.names[save.room.seat] ?? ""
        self.clock = clock
        saidReady = true
        room = Room(resuming: save.room, match: save.table, rules: OwareRoomRules(), transport: transport, clock: clock, timing: timing)
        room.onEvent = { [weak self] in self?.handle($0) }
    }

    private func handle(_ event: RoomEvent<OwareTable>) {
        switch event {
        case let .joinRequest(peer, name):
            joinRequests.append(JoinRequest(peer: peer, name: name))
        case .seated:
            joinRequests = []
        case .reconnecting(seat: 0) where room.role == .guest:
            startRejoining()
        case .back, .seatLost, .left:
            stopRejoining()
        case let .snapshot(table):
            watchRematch(table)
        default:
            break
        }
        onEvent?(event)
    }

    /// The phone in charge times a request for a rematch from when it was made.
    private func watchRematch(_ table: OwareTable) {
        guard isHost, table.rematchAsked.count == 1 else {
            rematchWaiting = nil
            return
        }
        if let waiting = rematchWaiting, waiting.asked == table.rematchAsked, waiting.round == table.rematchRound { return }
        rematchWaiting = (table.rematchAsked, table.rematchRound, clock.now)
    }

    /// The phone in charge: a request nobody answered for `rematchWait` is over, on both phones.
    private func lapseRematch() async {
        guard let waiting = rematchWaiting, clock.now - waiting.since >= Self.rematchWait else { return }
        rematchWaiting = nil
        guard let table, table.rematchAsked == waiting.asked, table.rematchRound == waiting.round,
              let lapsed = OwareRoomRules.lapsing(table) else { return }
        await room.replaceMatch(with: lapsed)
    }

    /// The host went quiet or the connection broke: connect again, and again, until it is back.
    private func startRejoining() {
        guard rejoining == nil, rejoin != nil else { return }
        rejoining = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.room.seats[0]?.isReconnecting == true else { break }
                if let transport = self.rejoin?() {
                    self.rejoins += 1
                    self.room.reconnect(over: transport)
                }
                try? await Task.sleep(for: Self.rejoinInterval)
            }
            self?.rejoining = nil
        }
    }

    private func stopRejoining() {
        rejoining?.cancel()
        rejoining = nil
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

    /// Host, before the game: Not now to the joining player, already let in.
    func sendAway() async {
        guard isHost, room.seats[1] != nil else { return }
        await room.dismiss(seat: 1)
        await startOver()
    }

    /// Host, before the game: the joining player went or was sent away. Nobody is ready and only
    /// this phone's speed is known, so the next one to join starts clean.
    func startOver() async {
        guard isHost, var table, !table.isStarted else { return }
        table.ready = []
        table.paces = table.paces.filter { $0.key == .south }
        saidReady = false
        await room.replaceMatch(with: table)
    }

    /// Host: applied at once, or refused by the rules. Guest: sent to the host.
    func send(_ intent: OwareIntent) async {
        try? await room.send(.game(intent))
    }

    /// Not now, to the other player's request for a rematch.
    func declineRematch() async {
        try? await room.send(.declineRematch)
    }

    /// A ping, a look at who has gone quiet, and at a rematch nobody has answered.
    func tick() async {
        await room.tick()
        await lapseRematch()
    }

    func startHeartbeat() {
        heartbeat?.cancel()
        let interval = room.timing.heartbeatInterval
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !Task.isCancelled else { return }
                await self.tick()
            }
        }
    }

    func leave() async {
        stopRejoining()
        heartbeat?.cancel()
        await room.leave()
    }

    /// Stops without a goodbye (the room is finished with, or is carried on elsewhere).
    func stop() {
        stopRejoining()
        heartbeat?.cancel()
        room.stop()
    }
}
