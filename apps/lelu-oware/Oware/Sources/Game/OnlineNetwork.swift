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

    init(session: GameSession, network: OnlineNetwork? = nil) {
        lobby = NearbyLobby(session: session, network: network ?? (LaunchOptions.onlineDemo ? .demo() : .live()), kind: .online)
    }
}

/// Where the relay is, and who this phone is to it.
enum OnlineConfig {
    /// The relay (the AWS repo's `apps/lelu-play`). A Debug build can point elsewhere with
    /// `--relay=ws://localhost:8787`.
    static let relay = URL(string: "wss://play.leluoware.com")!

    static var relayURL: URL { LaunchOptions.relayURL ?? relay }

    /// What every phone in a game must agree on to play together.
    static let game = RelayRequest.Game(name: "oware", protocolVersion: MatchKit.protocolVersion,
                                        formatVersion: OwareMatch.formatVersion)

    /// What a friend taps to join.
    static func joinLink(_ code: String) -> URL { URL(string: "https://leluoware.com/lelu-oware/join/\(code)")! }

    private static let installKey = "onlineInstall"

    /// A random ID made on this phone, sent with `create` and `join` so the relay can limit how
    /// many rooms one phone makes. It is not an account and names nobody.
    static func installID(_ defaults: UserDefaults = .standard) -> String {
        if let saved = defaults.string(forKey: installKey), !saved.isEmpty { return saved }
        let made = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        defaults.set(made, forKey: installKey)
        return made
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

    /// Through the relay at `url`.
    static func live(_ url: URL = OnlineConfig.relayURL) -> OnlineNetwork {
        OnlineNetwork(dial: OnlineTransport.dial(url), install: OnlineConfig.installID())
    }

    /// Through a relay inside the app, where the demo player, Ama, joins the game you start.
    static func demo(script: DemoPlayer.Script = .fromLaunchOptions) -> OnlineNetwork {
        let relay = LocalRelay()
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

    private func open(_ entry: OnlineTransport.Entry) -> OnlineTransport {
        watcher?.cancel()
        let transport = OnlineTransport(entry: entry, install: install, dial: dial, retryDelays: retryDelays)
        self.transport = transport
        let statuses = transport.statuses
        watcher = Task { [weak self] in
            for await status in statuses {
                guard !Task.isCancelled else { return }
                self?.took(status, entry: entry)
            }
        }
        return transport
    }

    private func took(_ status: OnlineTransport.Status, entry: OnlineTransport.Entry) {
        switch status {
        case let .open(seat):
            onCode?(seat.code)
            if case .create = entry, isDemo, player == nil { amaJoins(seat.code) }
        case let .refused(reason):
            onProblem?(Self.explain(reason))
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
        arriving?.cancel()
        player?.stop()
        player = nil
        transport = nil
    }
}
