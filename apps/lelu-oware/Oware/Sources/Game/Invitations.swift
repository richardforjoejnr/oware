import Foundation
import MatchKit
import MatchKitOnline
import Observation
import UIKit
import UserNotifications

/// The phone's own question, "allow notifications?", and its token from Apple.
protocol NotificationAccess: Sendable {
    /// Asks the first time; after that it only reports the answer. True if notifications are allowed.
    func ask() async -> Bool
    /// Asks Apple for this phone's notification token. It arrives at `Invitations.gotToken`.
    func wantToken()
}

struct SystemNotifications: NotificationAccess {
    func ask() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func wantToken() {
        Task { @MainActor in UIApplication.shared.registerForRemoteNotifications() }
    }
}

/// Test launches and the demo player: nothing is asked and no token comes.
struct NoNotifications: NotificationAccess {
    func ask() async -> Bool { true }
    func wantToken() {}
}

/// Invitations to play again (docs/ONLINE_PLAY.md §6): the switch that lets someone played before
/// notify this phone, the invitation when it arrives, and blocking.
///
/// Off until the player turns it on. On, the relay is told this phone's player number and where
/// its notifications go; off again, the relay is told to forget where.
@MainActor
@Observable
final class Invitations {
    /// "Ama wants to play", for the game with this code.
    struct Incoming: Equatable, Identifiable {
        var code: String
        /// Who asks: their player number.
        var from: String
        var name: String

        var id: String { code }
        /// Made here from the code. A link in the notification itself is never opened.
        var link: URL { OnlineConfig.joinLink(code) }
    }

    static let notificationsOff = "Notifications are off for Lelu Oware. Turn them on in the Settings app, then try again."
    /// The relay is told again this often, so it does not forget a phone still in use.
    static let registerEvery: TimeInterval = 7 * 24 * 3600
    static let nameLimit = 40

    /// The app's own.
    static let shared: Invitations = {
        let quiet = LaunchOptions.testMode || LaunchOptions.onlineDemo
        let secrets: any SecretStore = LaunchOptions.onlineDemo ? DemoSecrets() : Keychain()
        #if DEBUG
        let env = RelayRequest.Push.Env.sandbox
        #else
        let env = RelayRequest.Push.Env.production
        #endif
        return Invitations(me: PlayerIdentity.mine(secrets: secrets), recent: RecentPlayers(),
                           dial: OnlineConfig.dial,
                           access: quiet ? NoNotifications() : SystemNotifications(), env: env)
    }()

    /// Which relay this phone talks to now. Each relay keeps its own record of the phone, so after
    /// a change (Settings ▸ Relay) the new one is told.
    @ObservationIgnored var relayName: () -> String = { OnlineConfig.relayURL.absoluteString }

    let me: PlayerIdentity?
    let recent: RecentPlayers
    private(set) var isOn: Bool
    /// An invitation that arrived while the app was open, shown with Join and Not now.
    private(set) var incoming: Incoming?
    /// Why the switch could not be turned on, in words for the player.
    private(set) var problem: String?
    /// A notification was tapped: the game to open. Whoever opens it sets this back to nil.
    var tapped: URL?
    /// Whether a game with another phone is being played now (an invitation does not cover it).
    @ObservationIgnored var isPlaying: (() -> Bool)?

    @ObservationIgnored private let dial: OnlineTransport.Dial
    @ObservationIgnored private let access: any NotificationAccess
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let env: RelayRequest.Push.Env
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let wait: Double
    @ObservationIgnored private var token: String?

    private enum Key {
        static let on = "invitationsOn"
        static let registered = "invitationsRegistered"
        static let registeredAt = "invitationsRegisteredAt"
        static let blocks = "blocksToSend"
    }

    init(me: PlayerIdentity?, recent: RecentPlayers, dial: @escaping OnlineTransport.Dial, access: any NotificationAccess,
         defaults: UserDefaults = .standard, env: RelayRequest.Push.Env, wait: Double = 10, now: @escaping () -> Date = Date.init) {
        self.me = me
        self.recent = recent
        self.dial = dial
        self.access = access
        self.defaults = defaults
        self.env = env
        self.wait = wait
        self.now = now
        recent.me = me?.id
        isOn = me != nil && defaults.bool(forKey: Key.on)
    }

    /// Without a player number (no Keychain) nobody can ask this phone, and it asks nobody.
    var canBeOffered: Bool { me != nil }

    /// Where the relay sends this phone's notifications; nil while the switch is off or Apple
    /// has not given a token.
    var push: RelayRequest.Push? {
        guard isOn, let token else { return nil }
        return RelayRequest.Push(token: token, env: env)
    }

    // MARK: The switch

    /// Each launch. Apple may have changed the token, so it is asked for again; a block that
    /// could not be sent before is sent now. With the switch off nothing is asked or sent.
    func started() async {
        if isOn { access.wantToken() }
        await sendBlocks()
    }

    /// The player turns invitations on: the phone asks about notifications (the first time).
    @discardableResult
    func turnOn() async -> Bool {
        guard me != nil else { return false }
        guard await access.ask() else {
            problem = Self.notificationsOff
            return false
        }
        problem = nil
        isOn = true
        defaults.set(true, forKey: Key.on)
        access.wantToken()
        if token != nil { await register() }
        return true
    }

    /// Off: the relay forgets where this phone's notifications go.
    func turnOff() async {
        guard isOn else { return }
        isOn = false
        problem = nil
        defaults.set(false, forKey: Key.on)
        await register()
    }

    /// Apple's token for this phone, each time the app asks for it.
    func gotToken(_ data: Data) async {
        token = data.map { String(format: "%02x", $0) }.joined()
        if isOn { await register() }
    }

    /// Tells the relay who this phone is and where its notifications go. Skipped when the relay
    /// was told the same within the week.
    @discardableResult
    private func register(force: Bool = false) async -> Bool {
        guard let me else { return false }
        let push = self.push
        let saying = "\(push?.token ?? "-")|\(env.rawValue)|\(relayName())"
        let last = defaults.double(forKey: Key.registeredAt)
        if !force, defaults.string(forKey: Key.registered) == saying, now().timeIntervalSince1970 - last < Self.registerEvery { return true }
        let request = RelayRequest.register(game: OnlineConfig.game.name, player: me.id, secret: me.secret, push: push)
        guard await RelayCall.ask(request, dial: dial, wait: wait) == .registered else { return false }
        defaults.set(saying, forKey: Key.registered)
        defaults.set(now().timeIntervalSince1970, forKey: Key.registeredAt)
        return true
    }

    // MARK: Blocking

    /// Off the list here at once; the relay refuses their invitations as soon as it can be told.
    func block(_ id: String) async {
        recent.block(id)
        guard recent.isBlocked(id) else { return }
        toSend[id] = true
        await sendBlocks()
    }

    func unblock(_ id: String) async {
        recent.unblock(id)
        toSend[id] = false
        await sendBlocks()
    }

    /// Blocks (true) and unblocks (false) the relay has not been told yet.
    private var toSend: [String: Bool] {
        get { defaults.dictionary(forKey: Key.blocks) as? [String: Bool] ?? [:] }
        set { defaults.set(newValue, forKey: Key.blocks) }
    }

    private func sendBlocks() async {
        guard let me, !toSend.isEmpty, await register() else { return }
        for (who, on) in toSend.sorted(by: { $0.key < $1.key }) {
            let request = RelayRequest.block(game: OnlineConfig.game.name, player: me.id, secret: me.secret, who: who, on: on)
            var answer = await RelayCall.ask(request, dial: dial, wait: wait)
            if answer == .refused(.invalid), await register(force: true) {
                // The relay had forgotten this phone: told again, it takes the block.
                answer = await RelayCall.ask(request, dial: dial, wait: wait)
            }
            guard answer == .blocked(who: who, on: on) else { return }
            if toSend[who] == on { toSend[who] = nil }
        }
    }

    // MARK: An invitation arrives

    /// What a notification says, if it is an invitation this phone should show: a code that can
    /// be a code, from a player number, and not from someone blocked.
    func read(_ note: [AnyHashable: Any]) -> Incoming? {
        guard let code = (note["code"] as? String).flatMap({ RoomCode($0) }), let from = note["from"] as? String,
              RecentPlayers.isPlayerNumber(from), from != me?.id, !recent.isBlocked(from) else { return nil }
        let name = ((note["name"] as? String) ?? "").unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let tidy = String(String.UnicodeScalarView(name)).trimmingCharacters(in: .whitespacesAndNewlines)
        return Incoming(code: code.text, from: from, name: tidy.isEmpty ? RecentPlayers.unnamed : String(tidy.prefix(Self.nameLimit)))
    }

    /// The app is open: show the invitation here. False when it is not one to show, or a game
    /// with another phone is being played (it is then left to the phone's own banner).
    @discardableResult
    func show(_ note: [AnyHashable: Any], playing: Bool = false) -> Bool {
        guard !playing, let invitation = read(note) else { return false }
        incoming = invitation
        return true
    }

    /// The notification was tapped: open its game.
    func opened(_ note: [AnyHashable: Any]) {
        guard let invitation = read(note) else { return }
        incoming = nil
        tapped = invitation.link
    }

    /// Join: the link to open, and the invitation is put away.
    func join() -> URL? {
        defer { incoming = nil }
        return incoming?.link
    }

    /// Not now: the player who is waiting is told.
    func notNow() async {
        guard let invitation = incoming else { return }
        incoming = nil
        guard let me else { return }
        await RelayCall.tell(.decline(code: invitation.code, player: me.id), dial: dial)
    }
}
