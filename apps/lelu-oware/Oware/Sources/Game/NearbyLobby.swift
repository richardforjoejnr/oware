import Foundation
import MatchKit
import MatchKitNearby
import Observation
import OwareEngine

/// A game found nearby, as its card shows it: "Kofi's game · Abapa · Kofi starts".
struct NearbyListing: Identifiable, Hashable {
    let name: String
    /// Who made it (an older app lists only "Kofi's game").
    let creatorName: String
    let rules: String?
    /// Whether the player who made the game starts (nil from an older app).
    var creatorStarts: Bool?
    /// The game's `matchID`, for finding it again after a lost connection.
    var gameID: String?
    /// Where to connect; nil for the demo player's game.
    fileprivate var game: NearbyGame?

    var id: String { name }

    /// What a game's Bonjour TXT record carries (`NearbyLobby.host`).
    fileprivate init(name: String, info: [String: String], game: NearbyGame?) {
        self.name = name
        creatorName = info["name"] ?? (name.hasSuffix("'s game") ? String(name.dropLast(7)) : "Nearby Player")
        rules = info["rules"]
        creatorStarts = info["starter"].map { $0 == "creator" }
        gameID = info["game"]
        self.game = game
    }
}

/// What the lobby needs from the phones around: real ones over Bonjour, or the demo player.
@MainActor
protocol NearbyNetwork: AnyObject {
    var isDemo: Bool { get }
    /// Lists a game under `gameName` and returns the transport its guests arrive on. Stops looking
    /// for other games first.
    func host(gameName: String, info: [String: String], status: @escaping @MainActor (NearbyStatus) -> Void) throws -> any MatchTransport
    func browse(games: @escaping @MainActor ([NearbyListing]) -> Void, status: @escaping @MainActor (NearbyStatus) -> Void)
    func connect(to listing: NearbyListing) -> any MatchTransport
    /// The game has started: stop listing it and stop looking for others.
    func stopFinding()
    /// Back out: stop finding, and send the demo player home.
    func shutDown()
}

/// Play nearby (NEARBY_PLAY_REDESIGN.md §2): one screen that lists the games nearby by itself, or
/// starts yours; then Ready to play on both phones, and the room goes to the `GameSession`. Lives
/// as long as the app, so a game's demo player outlives the Nearby screen.
@MainActor
@Observable
final class NearbyLobby {
    enum Phase: Equatable {
        /// Games nearby, and Start nearby game.
        case lobby
        /// Your game is listed: looking for another player.
        case waiting
        /// Ready to play: both players on the screen; the game starts when both press Ready.
        case ready
        /// The game went away, or the creator said not now, or the versions differ.
        case refused(String)
        case playing
    }

    /// The other player on the Ready screen.
    struct Opponent: Equatable {
        var name: String
        /// Seated in the game (the creator sees someone asking as here already).
        var isConnected: Bool
        var isReady: Bool
    }

    /// How a game card says who starts, on the joining phone.
    static func startNote(creatorStarts: Bool, creatorName: String) -> String {
        creatorStarts ? "\(creatorName) starts" : "You start"
    }

    private(set) var phase: Phase = .lobby
    private(set) var games: [NearbyListing] = []
    private(set) var status: NearbyStatus = .working
    private(set) var link: MatchLink?
    private(set) var network: any NearbyNetwork
    /// Ready to play: the other player, and what this game is ("Abapa · You start").
    private(set) var opponent: Opponent?
    private(set) var gameNote = ""
    private(set) var iAmReady = false
    /// Look for games was tapped: games nearby are being looked for.
    private(set) var isLooking = false
    /// Called once both are ready and the game is on the session.
    @ObservationIgnored var onStart: (() -> Void)?
    let session: GameSession
    /// The one asking to play, while the creator decides.
    private var asking: MatchLink.JoinRequest?

    var isDemo: Bool { network.isDemo }
    var isCreator: Bool { link?.isHost ?? false }
    /// Only the creator turns someone away, and only before saying Ready.
    var canSayNotNow: Bool { isCreator && asking != nil && !iAmReady }
    /// The guest has the game once seated; the creator any time someone is there.
    var canPressReady: Bool { phase == .ready && !iAmReady && (isCreator ? asking != nil : link?.table != nil) }

    init(session: GameSession, network: any NearbyNetwork) {
        self.session = session
        self.network = network
    }

    /// Opening the Nearby screen: real phones, or the demo player (Settings ▸ Try nearby play).
    func prepare(demo: Bool) {
        reset()
        if demo != network.isDemo { network = demo ? DemoNetwork() : LiveNearbyNetwork() }
        open()
    }

    /// Back to Play nearby, not looking for games until asked.
    func open() { reset() }

    /// Look for games: lists the games nearby as they turn up.
    func look() {
        reset()
        isLooking = true
        network.browse(games: { [weak self] in self?.games = $0 }, status: { [weak self] in self?.status = $0 })
    }

    /// Start nearby game: whoever starts it moves first (the owner's call, 2026-10-30). `pace`: this
    /// phone's sowing speed; both phones sow at the slower of the two.
    func start(name: String, rules: RuleSet, pace: Double = AppSettings.AnimationSpeed.normal.rawValue) {
        reset()
        let match = OwareMatch(rules: rules, starter: .south)
        // "starter" stays in the listing so a card can say "Kofi starts".
        let info = ["rules": Self.rulesName(rules), "starter": "creator", "game": match.matchID.uuidString, "name": name]
        do {
            let transport = try network.host(gameName: "\(name)'s game", info: info, status: { [weak self] in self?.status = $0 })
            let link = MatchLink(hosting: match, name: name, pace: pace, transport: transport)
            link.onEvent = { [weak self] in self?.handle($0) }
            self.link = link
            gameNote = "\(Self.rulesName(rules)) · You start"
            phase = .waiting
            session.events.nearbyHosted(demo: isDemo)
        } catch {
            status = .failed
        }
    }

    func join(_ listing: NearbyListing, name: String, pace: Double = AppSettings.AnimationSpeed.normal.rawValue) {
        let link = MatchLink(joiningAs: name, pace: pace, transport: network.connect(to: listing))
        link.onEvent = { [weak self] in self?.handle($0) }
        self.link?.room.stop()
        self.link = link
        opponent = Opponent(name: listing.creatorName, isConnected: false, isReady: false)
        gameNote = [listing.rules, listing.creatorStarts.map { Self.startNote(creatorStarts: $0, creatorName: listing.creatorName) }]
            .compactMap { $0 }.joined(separator: " · ")
        iAmReady = false
        phase = .ready
    }

    /// The Ready button. The creator seats the one asking, then both say ready; the game starts
    /// when the creator's phone has both.
    func ready() async {
        guard let link, canPressReady else { return }
        iAmReady = true
        if let asking {
            self.asking = nil
            await link.accept(asking.peer)
        }
        await link.ready()
        refresh()
    }

    /// The creator: not this player. The game stays listed for someone else.
    func notNow() async {
        guard canSayNotNow, let asking, let link else { return }
        self.asking = nil
        await link.decline(asking.peer)
        opponent = nil
        phase = .waiting
    }

    /// Cancel: take your game down, or leave the one you were joining.
    func cancel() { open() }

    private func reset() {
        network.shutDown()
        if phase != .playing, let link { Task { await link.leave() } }
        link = nil
        asking = nil
        opponent = nil
        iAmReady = false
        isLooking = false
        games = []
        status = .working
        phase = .lobby
    }

    private func handle(_ event: RoomEvent<OwareTable>) {
        guard let link else { return }
        switch event {
        case let .joinRequest(peer, name):
            guard asking == nil, phase == .waiting else { return }
            asking = MatchLink.JoinRequest(peer: peer, name: name)
            opponent = Opponent(name: name, isConnected: true, isReady: false)
            phase = .ready
        case .seated:
            network.stopFinding()
            if link.room.role == .guest { session.events.nearbyJoined(demo: isDemo) }
            link.startHeartbeat()
        case let .refused(refusal):
            link.room.stop()
            self.link = nil
            opponent = nil
            phase = .refused(Self.explain(refusal))
            return
        case .left, .seatLost:
            guard phase == .ready else { break }
            let name = opponent?.name ?? Self.otherPlayer
            Task { await link.leave() }
            self.link = nil
            opponent = nil
            phase = .refused("\(name) has gone.")
            return
        default:
            break
        }
        refresh()
    }

    /// The Ready screen from the table; once both are ready, the game.
    private func refresh() {
        guard phase == .ready, let link else { return }
        if let table = link.table, link.room.mySeat != nil, opponent != nil {
            let theirs: Player = link.isHost ? .north : .south
            opponent?.isConnected = link.isHost ? (asking != nil || link.room.seats[1] != nil) : true
            opponent?.isReady = table.ready.contains(theirs)
            iAmReady = iAmReady || link.iAmReady
            if table.isStarted { begin(link) }
        }
    }

    private func begin(_ link: MatchLink) {
        network.stopFinding()
        phase = .playing
        session.startRemote(link)
        onStart?()
    }

    static func explain(_ refusal: Refusal) -> String {
        switch refusal {
        case .roomFull: "That game has already started."
        case .declined: "They said not this time."
        case let .needsUpdate(hostVersion):
            hostVersion > MatchKit.protocolVersion
                ? "Update Lelu Oware to join this game."
                : "Their Lelu Oware needs updating to play with yours."
        }
    }

    static func rulesName(_ rules: RuleSet) -> String { rules.variant == .namNam ? "Nam-Nam" : "Abapa" }

    // MARK: Names

    static let defaultName = "Oware Player"
    static let otherPlayer = "Other player"
    private static let nameKey = "nearbyName"

    /// What nearby players see: the Nearby name saved in Settings, else the Game Center name, else
    /// Oware Player (iOS no longer gives apps the phone's name).
    static func myName(saved: String?, gameCenter: String?) -> String {
        [saved, gameCenter].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
            ?? defaultName
    }

    static var myName: String { myName(saved: savedName(), gameCenter: GameCenter.shared.playerName) }

    /// Two players with the same name (both Oware Player): add the side's colour, which is the same
    /// on both phones.
    static func tellApart(_ theirs: String, from mine: String?, side: Player) -> String {
        theirs == mine ? "\(theirs) · \(side == .south ? "gold" : "red")" : theirs
    }

    static func savedName(_ defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: nameKey).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Trimmed; a blank name is not a name.
    static func saveName(_ name: String, _ defaults: UserDefaults = .standard) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        defaults.set(String(trimmed.prefix(24)), forKey: nameKey)
    }
}

/// Real phones: Bonjour over Apple's phone-to-phone Wi-Fi.
@MainActor
final class LiveNearbyNetwork: NearbyNetwork {
    /// Also in Info.plist's `NSBonjourServices`.
    static let serviceType = "_leluoware._tcp"

    let isDemo = false
    private var advertiser: NearbyHost?
    private var browser: NearbyBrowser?
    private var watchers: [Task<Void, Never>] = []

    func host(gameName: String, info: [String: String], status: @escaping @MainActor (NearbyStatus) -> Void) throws -> any MatchTransport {
        let host = try NearbyHost(serviceType: Self.serviceType, name: gameName, info: info)
        advertiser = host
        let updates = host.status
        watchers.append(Task { for await update in updates { status(update) } })
        return host
    }

    func browse(games: @escaping @MainActor ([NearbyListing]) -> Void, status: @escaping @MainActor (NearbyStatus) -> Void) {
        let browser = NearbyBrowser(serviceType: Self.serviceType)
        self.browser = browser
        let found = browser.games, updates = browser.status
        watchers.append(Task {
            for await list in found { games(list.map { NearbyListing(name: $0.name, info: $0.info, game: $0) }) }
        })
        watchers.append(Task { for await update in updates { status(update) } })
    }

    func connect(to listing: NearbyListing) -> any MatchTransport {
        guard let game = listing.game, let browser else { return LoopbackTransport() }
        return browser.connect(to: game)
    }

    func stopFinding() {
        watchers.forEach { $0.cancel() }
        watchers = []
        advertiser?.setAdvertising(false)
        advertiser = nil   // the room owns the connection now
        browser?.stop()
        browser = nil
    }

    func shutDown() { stopFinding() }
}

/// The demo: Ama, a pretend player on a pretend phone inside the app, over the same rooms and
/// messages as two real phones (MULTIPLAYER.md §5). For UI tests, App Review, and anyone who wants
/// to see nearby play before finding a friend.
@MainActor
final class DemoNetwork: NearbyNetwork {
    let isDemo = true
    /// The demo game Ama lists, and hosts when joined.
    private let gameID = UUID()
    let script: DemoPlayer.Script
    private(set) var player: DemoPlayer?
    private var arriving: Task<Void, Never>?

    init(script: DemoPlayer.Script = .fromLaunchOptions) {
        self.script = script
    }

    func host(gameName: String, info: [String: String], status: @escaping @MainActor (NearbyStatus) -> Void) throws -> any MatchTransport {
        let mine = LoopbackTransport(), hers = LoopbackTransport()
        player = DemoPlayer(joining: hers, script: script)
        arrive(mine, hers)
        return mine
    }

    func browse(games: @escaping @MainActor ([NearbyListing]) -> Void, status: @escaping @MainActor (NearbyStatus) -> Void) {
        // Ama makes the game and starts it, as `DemoPlayer(hosting:)` sets up.
        games([NearbyListing(name: "\(DemoPlayer.name)'s game",
                             info: ["rules": NearbyLobby.rulesName(.abapa), "starter": "creator",
                                    "game": gameID.uuidString, "name": DemoPlayer.name],
                             game: nil)])
    }

    func connect(to listing: NearbyListing) -> any MatchTransport {
        let mine = LoopbackTransport(), hers = LoopbackTransport()
        player = DemoPlayer(hosting: hers, match: OwareMatch(rules: .abapa, matchID: gameID), script: script)
        arrive(mine, hers)
        return mine
    }

    /// Ama's phone turns up a moment later, as a real one would.
    private func arrive(_ mine: LoopbackTransport, _ hers: LoopbackTransport) {
        let delay = script.joinDelay
        arriving = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            mine.connect(hers)
        }
    }

    func stopFinding() {}

    func shutDown() {
        arriving?.cancel()
        player?.stop()
        player = nil
    }
}

/// Ama: plays the first move she can after a pause, always agrees to a rematch, and does what the
/// script says (resign her first game after so many moves, or go quiet for a while).
@MainActor
final class DemoPlayer {
    struct Script: Equatable {
        /// Resign the first game on her turn once she has made this many moves.
        var resignAfter: Int?
        /// Go quiet after this many moves, for `quietFor` seconds, like walking out of range.
        var quietAfter: Int?
        var quietFor: Double = 12
        /// Long enough to read "Ama's turn".
        var thinkTime: Double = 2
        var joinDelay: Double = 1.5

        static var fromLaunchOptions: Script {
            Script(resignAfter: LaunchOptions.demoResignAfter, quietAfter: LaunchOptions.demoQuietAfter)
        }
    }

    static let name = "Ama"

    let room: Room<OwareRoomRules>
    private let transport: LoopbackTransport
    private let script: Script
    private var firstGame: UUID?
    private var movesIn: [UUID: Int] = [:]
    private var totalMoves = 0
    private var turn: Task<Void, Never>?

    init(joining transport: LoopbackTransport, script: Script) {
        self.transport = transport
        self.script = script
        room = Room(joiningAs: Self.name, rules: OwareRoomRules(), transport: transport)
        start()
    }

    init(hosting transport: LoopbackTransport, match: OwareMatch, script: Script) {
        self.transport = transport
        self.script = script
        room = Room(hosting: OwareTable.opening(match), name: Self.name, rules: OwareRoomRules(), transport: transport)
        start()
    }

    private func start() {
        room.onEvent = { [weak self] in self?.handle($0) }
        room.startHeartbeat()
    }

    func stop() {
        turn?.cancel()
        room.stop()
    }

    private func handle(_ event: RoomEvent<OwareTable>) {
        switch event {
        case let .joinRequest(peer, _):
            Task { await room.accept(peer) }
        case .seated, .snapshot:
            consider()
        default:
            break
        }
    }

    /// Her turn, or a finished game: decide what to do.
    private func consider() {
        guard turn == nil, let table = room.match, let seat = room.mySeat,
              let state = try? table.match.state() else { return }
        let me = OwareRoomRules.player(seat: seat)
        let id = table.match.matchID
        if firstGame == nil { firstGame = id }
        // Like any phone: acknowledge the opening as her own engine replays it, then wait for both.
        if !table.ready.contains(me), !table.isOutOfStep {
            act(.ready(stateHash: state.fingerprint), pause: 0)
            return
        }
        guard table.isStarted else { return }
        if state.isOver {
            if !table.rematchAsked.contains(me) { act(.game(.rematch)) }
            return
        }
        guard state.sideToMove == me else { return }
        if let limit = script.resignAfter, id == firstGame, movesIn[id, default: 0] >= limit {
            act(.game(.resign))
        } else if let move = state.legalMoves().first {
            movesIn[id, default: 0] += 1
            act(.game(.play(house: move.absoluteIndex)))
        }
    }

    private func act(_ intent: TableIntent, pause: Double? = nil) {
        let pause = pause ?? script.thinkTime
        turn = Task { [weak self] in
            try? await Task.sleep(for: .seconds(pause))
            guard let self, !Task.isCancelled else { return }
            try? await self.room.send(intent)
            self.turn = nil
            if case .game(.play) = intent { self.played() }
            // Hosting, her own move comes back while she is still busy: look again.
            self.consider()
        }
    }

    private func played() {
        totalMoves += 1
        guard totalMoves == script.quietAfter else { return }
        transport.isQuiet = true
        let quietFor = script.quietFor
        Task { [transport] in
            try? await Task.sleep(for: .seconds(quietFor))
            transport.isQuiet = false
        }
    }
}
