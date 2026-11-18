import Foundation
import MatchKit
import MatchKitNearby
import MatchKitOnline
import Observation
import OwareEngine

/// Play online: the lobby for games through the relay (docs/ONLINE_PLAY.md). It is the nearby
/// lobby with another network behind it, so Ready to play, the game and reconnecting are shared.
@MainActor
@Observable
final class OnlinePlay {
    let lobby: NearbyLobby
    /// Where the game is kept so it survives the app closing; nil keeps nothing (tests).
    let saves: OnlineSaves?

    /// Going back to the saved game, from the Rejoin card or its invitation link.
    enum Rejoining: Equatable {
        case no
        case connecting
        /// It could not be rejoined, in words for the player.
        case failed(String)
    }

    private(set) var rejoining = Rejoining.no

    /// Someone played before, asked to join the game just started (Play again).
    struct Asked: Equatable {
        enum State: Equatable {
            case asking
            /// The notification is on its way. It does not say they have seen it.
            case sent
            /// They cannot be notified: invitations off, the app removed, or they blocked this phone.
            case unreachable
            /// They said Not now.
            case declined
            /// The relay would not or could not send it.
            case failed
        }

        /// Their player number.
        var to: String
        var name: String
        /// The game they were asked to.
        var code: String
        var state: State
    }

    private(set) var asked: Asked?
    /// Nil where nobody is asked again (no player number on this phone).
    let invitations: Invitations?
    private let network: OnlineNetwork

    var recent: RecentPlayers? { invitations?.recent }

    init(session: GameSession, network: OnlineNetwork? = nil, saves: OnlineSaves? = nil, invitations: Invitations? = nil) {
        let network = network ?? (LaunchOptions.onlineDemo ? .demo() : .live())
        self.network = network
        lobby = NearbyLobby(session: session, network: network, kind: .online)
        self.saves = saves
        self.invitations = invitations?.canBeOffered == true ? invitations : nil
        session.onlineSaves = saves
        if let invitations = self.invitations, let me = invitations.me {
            network.me = me.forRelay
            network.push = { [weak invitations] in invitations?.push }
            lobby.myPlayer = me.id
            lobby.onMet = { [weak invitations] player, name in invitations?.recent.played(with: player, name: name) }
        }
        network.onDeclined = { [weak self] player in
            guard let self, self.asked?.to == player, self.asked?.code == self.lobby.roomCode else { return }
            self.asked?.state = .declined
        }
    }

    // MARK: Play again with someone played before

    /// Starts a game and asks `player` to it: their phone gets a notification that opens the game.
    /// The game waits like any other, so its link can be sent if they do not come.
    func playAgain(_ player: RecentPlayers.Entry, name: String, rules: RuleSet,
                   pace: Double = AppSettings.AnimationSpeed.normal.rawValue) {
        asked = nil
        lobby.start(name: name, rules: rules, pace: pace) { [weak self] code in
            guard let self else { return }
            self.asked = Asked(to: player.id, name: player.name, code: code, state: .asking)
            Task {
                let answer = await self.network.invite(player.id, name: name)
                guard self.asked?.code == code, self.asked?.to == player.id, self.asked?.state == .asking else { return }
                switch answer {
                case .sent: self.asked?.state = .sent
                case .refused(.unreachable): self.asked?.state = .unreachable
                case .refused, .noAnswer: self.asked?.state = .failed
                }
            }
        }
    }

    /// What the waiting screen says about the player who was asked; nil when nobody was asked to
    /// the game now waiting.
    var askedNote: String? {
        guard let asked, lobby.phase == .waiting, asked.code == lobby.roomCode else { return nil }
        return Self.note(asked)
    }

    /// Honest about what is known: a notification was sent, not that it was seen.
    static func note(_ asked: Asked) -> String {
        switch asked.state {
        case .asking: "Asking \(asked.name)…"
        case .sent: "\(asked.name) has been asked. The game starts when they join."
        case .unreachable: "\(asked.name) could not be reached. Send them the link instead."
        case .declined: "\(asked.name) said not now."
        case .failed: "\(asked.name) could not be asked just now. Send them the link instead."
        }
    }

    // MARK: A game from before the app was closed

    /// The online game this phone can go back to: one was saved, and it is not the game on the
    /// board now. Home shows it as the Rejoin card.
    var saved: OnlineSave? { lobby.session.link == nil ? saves?.current : nil }

    static func rejoinTitle(_ save: OnlineSave) -> String { "Your game with \(save.opponentName)" }

    static let gameEnded = "That game has ended."

    /// What the relay's no means for a game being rejoined. `ended`: it will not be there later
    /// either, so the save goes. That is `notFound`, and any reason this app does not know (a
    /// newer relay's, which arrives as `other`) or that makes no sense for a seat already held.
    static func rejoinRefused(_ reason: RelayEvent.Refusal) -> (message: String, ended: Bool) {
        switch reason {
        case .paused, .tooMany, .needsUpdate, .needsUnlock: (OnlineNetwork.explain(reason), false)
        default: (gameEnded, true)
        }
    }

    /// Rejoin: connects, takes this phone's seat back with its token, and carries on from the
    /// saved match. The board opens once the relay has let the phone in. False if there is no
    /// saved game, or one is being rejoined already.
    @discardableResult
    func rejoin(pace: Double = AppSettings.AnimationSpeed.normal.rawValue) -> Bool {
        guard let save = saved, rejoining != .connecting else { return false }
        rejoining = .connecting
        let begun = lobby.resume(save, pace: pace, opened: { [weak self] in self?.rejoining = .no }, refused: { [weak self] reason in
            let answer = Self.rejoinRefused(reason)
            if answer.ended { self?.saves?.clear() }
            self?.rejoining = .failed(answer.message)
        })
        if !begun { rejoining = .no }
        return begun
    }

    /// The player has read why the game could not be rejoined.
    func dismissRejoinProblem() {
        if case .failed = rejoining { rejoining = .no }
    }

    /// Leave game, on the Rejoin card: the save goes at once, and the other player is told.
    func leaveSaved() {
        guard let save = saved else { return }
        if rejoining == .connecting { lobby.cancel() }
        rejoining = .no
        saves?.clear()
        lobby.network.goodbye(save)
    }

    /// The link is the invitation to the game saved on this phone: it means Rejoin.
    func rejoins(link: URL) -> Bool {
        guard let code = RoomCode(link: link), let saved else { return false }
        return saved.code == code.text
    }

    /// An invitation link was tapped: join that game. False when it is not an invitation, or a
    /// game with another phone is already being played here (the link does not end it).
    @discardableResult
    func open(link: URL, name: String, pace: Double = AppSettings.AnimationSpeed.normal.rawValue) -> Bool {
        // The game this phone is already in: back to its own seat, not in as someone new.
        if rejoins(link: link) { return rejoin(pace: pace) }
        let session = lobby.session
        let playing = session.link != nil && session.isStarted && !session.state.isOver
        guard let code = RoomCode(link: link), !playing else { return false }
        lobby.prepare(demo: lobby.isDemo)
        return lobby.join(code: code.text, name: name, pace: pace)
    }
}

/// The relay's two stages (the AWS repo's `apps/lelu-play`).
enum RelayStage: String, CaseIterable, Sendable {
    case dev, prod

    var label: String { self == .dev ? "Dev" : "Prod" }
}

/// Where the relay is, and who this phone is to it.
enum OnlineConfig {
    /// The relay (the AWS repo's `apps/lelu-play`): its dev stage for Debug builds and prod for
    /// TestFlight and App Store builds, from `RELAY_URL` in project.yml. A Debug build can point
    /// elsewhere with `--relay=ws://localhost:8787`.
    static let relay = relay(from: Bundle.main.object(forInfoDictionaryKey: "RelayURL") as? String)

    /// The address in the build, if it is a WebSocket address; otherwise the one planned for prod.
    static func relay(from configured: String?) -> URL {
        if let configured, let url = URL(string: configured), ["ws", "wss"].contains(url.scheme), url.host != nil { return url }
        return URL(string: "wss://play.leluoware.com")!
    }

    /// The stage this build uses unless told otherwise.
    static var buildStage: RelayStage {
        #if DEBUG
        .dev
        #else
        .prod
        #endif
    }

    /// A stage's address, if the build carries it.
    static func address(_ stage: RelayStage) -> URL? {
        let text = Bundle.main.object(forInfoDictionaryKey: stage == .dev ? "RelayURLDev" : "RelayURLProd") as? String
        guard let text, let url = URL(string: text), ["ws", "wss"].contains(url.scheme), url.host != nil else { return nil }
        return url
    }

    private static let choice = NSLock()
    nonisolated(unsafe) private static var chosenStage: RelayStage?
    /// Settings ▸ Relay, in builds that offer it (`AppSettings.chosenRelayStage`); nil: the build's own.
    static var chosen: RelayStage? {
        get { choice.withLock { chosenStage } }
        set { choice.withLock { chosenStage = newValue } }
    }

    /// A launch argument first, then the stage chosen in Settings, then the build's own relay.
    static func relayURL(launch: URL?, chosen: RelayStage?) -> URL {
        launch ?? chosen.flatMap(address) ?? relay
    }

    static var relayURL: URL { relayURL(launch: LaunchOptions.relayURL, chosen: chosen) }

    /// Connections to whichever relay is chosen when each is made, so a change in Settings counts
    /// from the next game.
    static let dial: OnlineTransport.Dial = { try await OnlineTransport.dial(relayURL)() }

    /// What every phone in a game must agree on to play together.
    static let game = RelayRequest.Game(name: "oware", protocolVersion: MatchKit.protocolVersion,
                                        formatVersion: OwareMatch.formatVersion)

    /// What a friend taps to join. With the app it opens straight into the game; without, a page
    /// with the code and the App Store (docs/lelu-oware/join.html).
    static func joinLink(_ code: String) -> URL { URL(string: "https://leluoware.com/lelu-oware/join?c=\(code)")! }

    /// The words that go with the link in a message. The code is there too, for a friend whose
    /// phone opens the link somewhere it cannot open the app.
    static func invitation(code: String) -> String {
        "Play Oware with me in Lelu Oware. Tap the link to join, or enter the code \(code) under Play online."
    }

    static let installKey = "onlineInstall"

    /// A random ID made on this phone, sent with `create` and `join` so the relay can limit how
    /// many rooms one phone makes. It is not an account and names nobody. Kept in the Keychain
    /// (docs/ONLINE_PLAY.md §6); one an earlier build kept in the settings moves there unchanged.
    /// If the Keychain cannot be written the settings keep it, so the phone is still one phone.
    static func installID(secrets: any SecretStore = Keychain(), defaults: UserDefaults = .standard) -> String {
        if let kept = secrets.read(installKey).map({ String(decoding: $0, as: UTF8.self) }), !kept.isEmpty { return kept }
        let earlier = defaults.string(forKey: installKey).flatMap { $0.isEmpty ? nil : $0 }
        let id = earlier ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        if secrets.write(Data(id.utf8), for: installKey) {
            defaults.removeObject(forKey: installKey)
        } else {
            defaults.set(id, forKey: installKey)
        }
        return id
    }
}

/// The relay as the lobby sees it: start a game (a room with a code) or join one by its code.
@MainActor
final class OnlineNetwork: NearbyNetwork {
    let isDemo: Bool
    private let dial: OnlineTransport.Dial
    private let install: String
    private let retryDelays: [Double]
    /// Demo: the relay inside the app, and Ama's script.
    private let demoRelay: LocalRelay?
    private let script: DemoPlayer.Script
    private(set) var player: DemoPlayer?
    private var arriving: Task<Void, Never>?
    private(set) var transport: OnlineTransport?
    private var watcher: Task<Void, Never>?
    private var onCode: (@MainActor (String) -> Void)?
    private var onProblem: (@MainActor (String) -> Void)?
    private var onSeatRefused: (@MainActor (RelayEvent.Refusal) -> Void)?
    /// The transport has had its seat at the relay.
    private var wasSeated = false
    private var farewell: Task<Void, Never>?
    /// Who this phone is when it asks someone to a game, and where its own notifications go.
    var me: RelayPlayer?
    var push: (@MainActor () -> RelayRequest.Push?)?
    /// Someone asked to this phone's game said Not now (their player number).
    var onDeclined: (@MainActor (String) -> Void)?
    private var declineWatcher: Task<Void, Never>?
    /// How long Leave game on the Rejoin card waits for the other phone, to tell it, in seconds.
    var goodbyeWait: Double = 5
    /// Demo: Ama's seat token in a room made again after the app was closed.
    private static let amaToken = "ama"

    /// Through the relay (`OnlineConfig.relayURL`).
    static func live() -> OnlineNetwork {
        OnlineNetwork(dial: OnlineConfig.dial, install: OnlineConfig.installID())
    }

    /// Through a relay inside the app, where the demo player, Ama, joins the game you start.
    static func demo(script: DemoPlayer.Script = .fromLaunchOptions) -> OnlineNetwork {
        let relay = LocalRelay()
        // Ama can be asked again: the relay in the app knows her, as if her phone had registered.
        let hers = RelayRequest.Push(token: "a0a0a0a0a0a0a0a0", env: .sandbox)
        Task { await relay.know(player: DemoPlayer.playerNumber, secret: amaToken, push: hers) }
        return OnlineNetwork(dial: relay.dial, install: "demo", demoRelay: relay, script: script)
    }

    /// - Parameter retryDelays: seconds between tries to reach the relay (tests pass short ones).
    init(dial: @escaping OnlineTransport.Dial, install: String, retryDelays: [Double] = [1, 2, 4, 8],
         demoRelay: LocalRelay? = nil, script: DemoPlayer.Script = DemoPlayer.Script()) {
        self.dial = dial
        self.install = install
        self.retryDelays = retryDelays
        self.demoRelay = demoRelay
        self.script = script
        isDemo = demoRelay != nil
    }

    func watchRoom(code: @escaping @MainActor (String) -> Void, problem: @escaping @MainActor (String) -> Void) {
        onCode = code
        onProblem = problem
    }

    func host(gameName: String, info: [String: String], status: @escaping @MainActor (NearbyStatus) -> Void) throws -> any MatchTransport {
        open(.create(game: OnlineConfig.game, seats: 2, proof: nil))
    }

    /// `listing.name` is the code (`NearbyLobby.join(code:)` has checked it).
    func connect(to listing: NearbyListing) -> any MatchTransport {
        open(.join(code: RoomCode(listing.name) ?? RoomCode("222222")!, game: OnlineConfig.game))
    }

    var roomSeat: OnlineTransport.Seat? { transport?.seat }

    /// From the phone that made the game now waiting: asks `to` (a player number) to it.
    func invite(_ to: String, name: String) async -> OnlineTransport.InviteAnswer {
        guard let me, let transport else { return .noAnswer }
        return await transport.invite(to, name: name, from: me, push: push?())
    }

    func watchSeat(refused: @escaping @MainActor (RelayEvent.Refusal) -> Void) { onSeatRefused = refused }

    /// Back into a saved game: this phone's seat again, with its token.
    func resume(_ save: OnlineSave) -> (any MatchTransport)? {
        let transport = open(.rejoin(save.relay), dial: dial(for: save))
        if isDemo, save.seat == 0 { amaReturns(to: save) }
        return transport
    }

    /// Closing without a goodbye: the seat is kept for later.
    func abandon() { transport?.abandon() }

    /// Leave game on the Rejoin card: back in for a moment, to tell the other phone (if it is
    /// there) and the relay that this player has left. The demo's game is gone with the app.
    func goodbye(_ save: OnlineSave) {
        guard !isDemo else { return }
        let transport = OnlineTransport(entry: .rejoin(save.relay), install: install, dial: dial, retryDelays: retryDelays)
        let link = MatchLink(resuming: save, transport: transport)
        let theirs = save.seat == 0 ? 1 : 0
        let wait = goodbyeWait
        farewell = Task {
            let end = ContinuousClock.now + .seconds(wait)
            while ContinuousClock.now < end, link.room.seats[theirs]?.isReconnecting != false {
                if case .refused = transport.status { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            await link.leave()
        }
    }

    /// The demo's relay starts empty with the app: the saved game's room is made again first.
    private func dial(for save: OnlineSave) -> OnlineTransport.Dial {
        guard let demoRelay else { return dial }
        let tokens = [save.relay.token, Self.amaToken]
        return {
            await demoRelay.restore(code: save.code, game: OnlineConfig.game, tokens: tokens)
            return try await demoRelay.dial()
        }
    }

    /// Demo: Ama was in the game all along, as a friend would be. She comes back to her seat a
    /// moment later with the match as it was saved.
    private func amaReturns(to save: OnlineSave) {
        guard player == nil else { return }
        let delay = script.joinDelay, script = script, dial = dial(for: save)
        let hers = RoomSave(seat: 1, names: save.room.names, tokens: save.room.tokens.filter { $0.key == 1 }, sequence: 0)
        arriving = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            let seat = OnlineTransport.Seat(code: save.code, peer: PeerID("p1"), token: Self.amaToken)
            let transport = OnlineTransport(entry: .rejoin(seat), install: "ama", dial: dial)
            self.player = DemoPlayer(resuming: hers, table: save.table, transport: transport, script: script)
        }
    }

    private func open(_ entry: OnlineTransport.Entry, dial: OnlineTransport.Dial? = nil) -> OnlineTransport {
        watcher?.cancel()
        wasSeated = false
        let transport = OnlineTransport(entry: entry, install: install, dial: dial ?? self.dial, retryDelays: retryDelays)
        self.transport = transport
        let statuses = transport.statuses
        watcher = Task { [weak self] in
            for await status in statuses {
                guard !Task.isCancelled else { return }
                self?.took(status, entry: entry)
            }
        }
        declineWatcher?.cancel()
        let declines = transport.declines
        declineWatcher = Task { [weak self] in
            for await player in declines {
                guard !Task.isCancelled else { return }
                self?.onDeclined?(player)
            }
        }
        return transport
    }

    private func took(_ status: OnlineTransport.Status, entry: OnlineTransport.Entry) {
        switch status {
        case let .open(seat):
            wasSeated = true
            onCode?(seat.code)
            if case .create = entry, isDemo, player == nil { amaJoins(seat.code) }
        case let .refused(reason):
            // No to a phone that had a seat is about the game it was in, not about getting into one.
            var hadSeat = wasSeated
            if case .rejoin = entry { hadSeat = true }
            if hadSeat { onSeatRefused?(reason) } else { onProblem?(Self.explain(reason)) }
        case .unreachable:
            onProblem?(Self.unreachable)
        case .connecting, .reconnecting, .closed:
            break
        }
    }

    /// Demo: Ama gets the code a moment later and joins, as a friend would.
    private func amaJoins(_ code: String) {
        guard let demoRelay, let code = RoomCode(code) else { return }
        let delay = script.joinDelay, script = script
        arriving = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            let hers = OnlineTransport(entry: .join(code: code, game: OnlineConfig.game), install: "ama", dial: demoRelay.dial)
            self.player = DemoPlayer(joining: hers, script: script)
        }
    }

    static let unreachable = "Could not reach online play. Check your internet connection and try again."

    static func explain(_ refusal: RelayEvent.Refusal) -> String {
        switch refusal {
        case .notFound: "No game has that code. Check it with your friend, or ask them to start a new game."
        case .ended: "That game has ended. Ask your friend to start a new one."
        case .unreachable: "They could not be reached. Send them the link instead."
        case .full: "That game already has two players."
        case .paused: "Online play is resting. Try again later."
        case .needsUpdate: "You and your friend need the same version of Lelu Oware. Update it on both phones."
        case .needsUnlock: "Starting an online game is not unlocked on this phone."
        case .tooMany: "Too many tries. Wait a few minutes, then try again."
        case .invalid, .other: "Online play could not start. Try again."
        }
    }

    /// The transport mends its own connection; there is nothing for the lobby to dial again.
    func rejoin(_ listing: NearbyListing) -> (any MatchTransport)? { nil }

    func browse(games: @escaping @MainActor ([NearbyListing]) -> Void, status: @escaping @MainActor (NearbyStatus) -> Void) {}
    func stopFinding() {}
    func watchAccess(_ update: @escaping @MainActor (NearbyAccess) -> Void) { update(NearbyAccess()) }
    func stopWatchingAccess() {}
    func recheckAccess() {}

    func shutDown() {
        watcher?.cancel()
        watcher = nil
        declineWatcher?.cancel()
        declineWatcher = nil
        arriving?.cancel()
        player?.stop()
        player = nil
        transport = nil
    }
}
