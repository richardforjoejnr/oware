import MatchKit
import MatchKitOnline
import OwareEngine
import XCTest
@testable import Oware

/// Asking someone played before for another game (docs/ONLINE_PLAY.md §6): who a phone is to the
/// relay, the Invitations switch, blocking, and Play again on two phones through the relay in
/// memory (`LocalRelay`), which records the notification the real one would send through Apple.
@MainActor
final class InvitationsTests: XCTestCase {
    private func until(_ what: @autoclosure () -> String, timeout: TimeInterval = 5, _ condition: () async -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while await !condition() {
            if Date() > end { return XCTFail("timed out waiting: \(what())") }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// The phone's answer to "allow notifications?".
    final class Access: NotificationAccess, @unchecked Sendable {
        var allows = true
        var asked = 0
        var wantedToken = 0
        func ask() async -> Bool {
            asked += 1
            return allows
        }
        func wantToken() { wantedToken += 1 }
    }

    /// One phone: its player number, its recent players, its Invitations switch and Play online.
    @MainActor
    final class Phone {
        let name: String
        let me: PlayerIdentity
        let access = Access()
        let defaults = TestSupport.defaults()
        let recent: RecentPlayers
        let invitations: Invitations
        let online: OnlinePlay
        var lobby: NearbyLobby { online.lobby }
        /// Which relay the phone is set to (Settings ▸ Relay).
        var relayName = "dev"

        init(_ name: String, relay: LocalRelay, me: PlayerIdentity? = PlayerIdentity.new()) {
            self.name = name
            self.me = me ?? PlayerIdentity(id: "", secret: "")
            recent = RecentPlayers(defaults: defaults)
            invitations = Invitations(me: me, recent: recent, dial: relay.dial, access: access, defaults: defaults, env: .sandbox)

            let network = OnlineNetwork(dial: relay.dial, install: name, retryDelays: [0.01, 0.01, 0.02])
            online = OnlinePlay(session: TestSupport.session(), network: network, invitations: invitations)
            online.lobby.onStart = {}
            invitations.relayName = { [weak self] in self?.relayName ?? "" }
        }

        /// Invitations on, and Apple has given the phone its token.
        func allowsInvitations() async {
            let on = await invitations.turnOn()
            XCTAssertTrue(on)
            await invitations.gotToken(Data([0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45, 0x67, 0x89]))
        }
    }

    /// Ama and Kofi have started a game with each other (so each has the other's player number).
    private func played(_ relay: LocalRelay) async -> (ama: Phone, kofi: Phone) {
        let ama = Phone("Ama", relay: relay), kofi = Phone("Kofi", relay: relay)
        await play(ama, kofi)
        return (ama, kofi)
    }

    private func play(_ ama: Phone, _ kofi: Phone) async {
        ama.lobby.start(name: ama.name, rules: .abapa)
        await until("a code") { ama.lobby.roomCode != nil }
        XCTAssertTrue(kofi.lobby.join(code: ama.lobby.roomCode ?? "", name: kofi.name))
        await until("Kofi is in") { kofi.lobby.opponent?.isConnected == true && ama.lobby.phase == .ready }
        await kofi.lobby.ready()
        await ama.lobby.ready()
        await until("both playing") { ama.lobby.session.isStarted && kofi.lobby.session.isStarted }
    }

    private func leave(_ phones: Phone...) async {
        for phone in phones {
            phone.lobby.session.leaveNearbyGame()
            phone.lobby.prepare(demo: false)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    // MARK: Who this phone is

    func testThePlayerNumberIsMadeOnceAndKeptInTheKeychain() throws {
        let secrets = MemorySecrets()
        let first = try XCTUnwrap(PlayerIdentity.mine(secrets: secrets))
        XCTAssertTrue(RecentPlayers.isPlayerNumber(first.id), first.id)
        XCTAssertGreaterThanOrEqual(first.secret.count, 32)
        XCTAssertNotEqual(first.id, first.secret)
        XCTAssertEqual(PlayerIdentity.mine(secrets: secrets), first, "the same on every launch")
        XCTAssertNotEqual(PlayerIdentity.mine(secrets: MemorySecrets())?.id, first.id, "another phone has another")
        XCTAssertEqual(first.forRelay, RelayPlayer(id: first.id, secret: first.secret, game: "oware"))
    }

    func testWithoutAKeychainThereIsNoPlayerNumber() {
        let secrets = MemorySecrets()
        secrets.refusesWrites = true
        XCTAssertNil(PlayerIdentity.mine(secrets: secrets), "a secret is not kept anywhere less safe")
    }

    // MARK: Recent players

    func testPlayingSomeoneOnlinePutsThemInRecentPlayersOnBothPhones() async {
        let (ama, kofi) = await played(LocalRelay())
        await until("each lists the other") { ama.recent.players.count == 1 && kofi.recent.players.count == 1 }
        XCTAssertEqual(ama.recent.players.first?.id, kofi.me.id)
        XCTAssertEqual(ama.recent.players.first?.name, "Kofi")
        XCTAssertEqual(kofi.recent.players.first?.id, ama.me.id)
        XCTAssertEqual(kofi.recent.players.first?.name, "Ama")
    }

    func testSomeoneWhoOnlyJoinedAndLeftBeforeTheGameIsNotListed() async {
        let relay = LocalRelay()
        let ama = Phone("Ama", relay: relay), kofi = Phone("Kofi", relay: relay)
        ama.lobby.start(name: "Ama", rules: .abapa)
        await until("a code") { ama.lobby.roomCode != nil }
        XCTAssertTrue(kofi.lobby.join(code: ama.lobby.roomCode ?? "", name: "Kofi"))
        await until("Kofi is in") { kofi.lobby.opponent?.isConnected == true && ama.lobby.phase == .ready }
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(ama.recent.players.isEmpty && kofi.recent.players.isEmpty, "no game was played")
    }

    func testAPhoneWithNoPlayerNumberListsNobodyAndIsNotListed() async {
        let relay = LocalRelay()
        let ama = Phone("Ama", relay: relay), old = Phone("Kofi", relay: relay, me: nil)
        await play(ama, old)
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(ama.recent.players.isEmpty)
        XCTAssertTrue(old.recent.players.isEmpty)
        XCTAssertFalse(old.invitations.canBeOffered)
    }

    // MARK: The Invitations switch

    func testInvitationsAreOffUntilThePlayerTurnsThemOn() async {
        let relay = LocalRelay()
        let kofi = Phone("Kofi", relay: relay)
        XCTAssertFalse(kofi.invitations.isOn)
        XCTAssertEqual(kofi.access.asked, 0, "nothing is asked at launch")
        await kofi.invitations.started()
        let registered = await relay.received["register"] ?? 0
        XCTAssertEqual(registered, 0, "and nothing is sent")
    }

    func testTurningInvitationsOnAsksOnceAndTellsTheRelayWhereNotificationsGo() async {
        let relay = LocalRelay()
        let (ama, kofi) = await played(relay)
        await leave(ama, kofi)
        await kofi.allowsInvitations()
        XCTAssertTrue(kofi.invitations.isOn)
        XCTAssertEqual(kofi.access.asked, 1)
        XCTAssertEqual(kofi.access.wantedToken, 1)

        ama.online.playAgain(ama.recent.players[0], name: "Ama", rules: .abapa)
        await until("he is asked") { await relay.invitations.count == 1 }
        let sent = await relay.invitations.first
        XCTAssertEqual(sent, .init(code: ama.lobby.roomCode ?? "", from: ama.me.id, name: "Ama", to: kofi.me.id))
        await until("and she is told") { ama.online.asked?.state == .sent }
        XCTAssertEqual(ama.online.asked?.name, "Kofi")
        XCTAssertEqual(ama.online.askedNote, "Kofi has been asked. The game starts when they join.")
        XCTAssertEqual(ama.lobby.phase, .waiting, "her game waits, and its link can still be sent")
    }

    func testIfThePhoneSaysNoToNotificationsInvitationsStayOff() async {
        let relay = LocalRelay()
        let kofi = Phone("Kofi", relay: relay)
        kofi.access.allows = false
        let on = await kofi.invitations.turnOn()
        XCTAssertFalse(on)
        XCTAssertFalse(kofi.invitations.isOn)
        XCTAssertEqual(kofi.invitations.problem, Invitations.notificationsOff)
    }

    func testSomeoneWithInvitationsOffCannotBeReachedAndTheLinkIsOfferedInstead() async {
        let relay = LocalRelay()
        let (ama, kofi) = await played(relay)
        await leave(ama, kofi)
        ama.online.playAgain(ama.recent.players[0], name: "Ama", rules: .abapa)
        await until("she is told") { ama.online.asked?.state == .unreachable }
        XCTAssertEqual(ama.online.askedNote, "Kofi could not be reached. Send them the link instead.")
        XCTAssertEqual(ama.lobby.phase, .waiting)
        XCTAssertNotNil(ama.lobby.roomCode)

        // On, then off again: unreachable again.
        await kofi.allowsInvitations()
        await kofi.invitations.turnOff()
        XCTAssertFalse(kofi.invitations.isOn)
        ama.online.playAgain(ama.recent.players[0], name: "Ama", rules: .abapa)
        await until("she is told again") { ama.online.asked?.state == .unreachable && ama.lobby.roomCode != nil }
        let sent = await relay.invitations
        XCTAssertTrue(sent.isEmpty)
    }

    func testRegisteringIsNotRepeatedOnEveryLaunch() async {
        let relay = LocalRelay()
        let kofi = Phone("Kofi", relay: relay)
        await kofi.allowsInvitations()
        let once = await relay.received["register"] ?? 0
        XCTAssertEqual(once, 1)
        await kofi.invitations.started()
        await kofi.invitations.gotToken(Data([0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45, 0x67, 0x89]))
        let again = await relay.received["register"] ?? 0
        XCTAssertEqual(again, 1, "the same token, the same week")
        XCTAssertEqual(kofi.access.wantedToken, 2, "but Apple is asked for the token on each launch, as it may change")
        await kofi.invitations.gotToken(Data([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]))
        let changed = await relay.received["register"] ?? 0
        XCTAssertEqual(changed, 2, "a new token is sent")
    }

    func testAfterTheRelayIsChangedInSettingsTheNewOneIsTold() async {
        let relay = LocalRelay()
        let kofi = Phone("Kofi", relay: relay)
        await kofi.allowsInvitations()
        kofi.relayName = "prod"
        await kofi.invitations.started()
        await kofi.invitations.gotToken(Data([0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45, 0x67, 0x89]))
        let told = await relay.received["register"] ?? 0
        XCTAssertEqual(told, 2, "the same token, but a relay that has not heard it")
    }

    // MARK: The invitation arrives

    func testTheNotificationSaysWhoAsksAndWhichGame() async {
        let relay = LocalRelay()
        let (ama, kofi) = await played(relay)
        let note: [AnyHashable: Any] = ["aps": ["alert": ["title": "Lelu Oware"]], "code": "K7M2QD", "from": ama.me.id, "name": "Ama",
                                        "link": "https://example.com/elsewhere"]
        let invitation = kofi.invitations.read(note)
        XCTAssertEqual(invitation, .init(code: "K7M2QD", from: ama.me.id, name: "Ama"))
        XCTAssertEqual(invitation?.link.absoluteString, "https://leluoware.com/lelu-oware/join?c=K7M2QD",
                       "the link is made here from the code, not taken from the notification")
        XCTAssertNil(kofi.invitations.read(["code": "not a code", "from": ama.me.id, "name": "Ama"]))
        XCTAssertNil(kofi.invitations.read(["code": "K7M2QD", "from": "someone", "name": "Ama"]))
        XCTAssertNil(kofi.invitations.read(["aps": [:]]))
        // A name is shown as text of a sensible length, whatever was sent.
        let long = kofi.invitations.read(["code": "K7M2QD", "from": ama.me.id, "name": String(repeating: "A", count: 200)])
        XCTAssertEqual(long?.name.count, 40)
    }

    func testAnInvitationWhileTheAppIsOpenIsShownAndJoinTakesThePlayerIn() async {
        let relay = LocalRelay()
        let (ama, kofi) = await played(relay)
        await leave(ama, kofi)
        await kofi.allowsInvitations()
        ama.online.playAgain(ama.recent.players[0], name: "Ama", rules: .abapa)
        await until("he is asked") { await relay.invitations.count == 1 }
        let sent = await relay.invitations[0]
        let note: [AnyHashable: Any] = ["code": sent.code, "from": sent.from, "name": sent.name]

        XCTAssertTrue(kofi.invitations.show(note), "shown in the app, not as a banner over it")
        XCTAssertEqual(kofi.invitations.incoming?.name, "Ama")
        let link = kofi.invitations.join()
        XCTAssertNil(kofi.invitations.incoming)
        XCTAssertTrue(kofi.online.open(link: try! XCTUnwrap(link), name: "Kofi"))
        await until("Ama sees him") { ama.lobby.phase == .ready && ama.lobby.opponent?.name == "Kofi" }
    }

    func testNotNowTellsThePlayerWhoIsWaiting() async {
        let relay = LocalRelay()
        let (ama, kofi) = await played(relay)
        await leave(ama, kofi)
        await kofi.allowsInvitations()
        ama.online.playAgain(ama.recent.players[0], name: "Ama", rules: .abapa)
        await until("he is asked") { await relay.invitations.count == 1 }
        let sent = await relay.invitations[0]
        XCTAssertTrue(kofi.invitations.show(["code": sent.code, "from": sent.from, "name": sent.name]))
        await kofi.invitations.notNow()
        XCTAssertNil(kofi.invitations.incoming)
        await until("she is told") { ama.online.asked?.state == .declined }
        XCTAssertEqual(ama.online.askedNote, "Kofi said not now.")
        XCTAssertEqual(ama.lobby.phase, .waiting, "her game is still there for the link")
    }

    func testAnInvitationDoesNotInterruptAGameBeingPlayed() async {
        let relay = LocalRelay()
        let (ama, kofi) = await played(relay)
        XCTAssertFalse(kofi.invitations.show(["code": "K7M2QD", "from": ama.me.id, "name": "Ama"], playing: true))
        XCTAssertNil(kofi.invitations.incoming)
    }

    // MARK: Blocking

    func testBlockingTakesThemOffTheListAndTheirInvitationsNoLongerArrive() async {
        let relay = LocalRelay()
        let (ama, kofi) = await played(relay)
        await leave(ama, kofi)
        await kofi.allowsInvitations()
        await kofi.invitations.block(ama.me.id)
        XCTAssertTrue(kofi.recent.players.isEmpty)
        XCTAssertEqual(kofi.recent.blocked.map(\.name), ["Ama"])

        ama.online.playAgain(ama.recent.players[0], name: "Ama", rules: .abapa)
        await until("she is told only that he cannot be reached") { ama.online.asked?.state == .unreachable }
        let sent = await relay.invitations
        XCTAssertTrue(sent.isEmpty)
        // One that was already on its way is not shown either.
        XCTAssertFalse(kofi.invitations.show(["code": "K7M2QD", "from": ama.me.id, "name": "Ama"]))
        XCTAssertNil(kofi.invitations.read(["code": "K7M2QD", "from": ama.me.id, "name": "Ama"]))

        await kofi.invitations.unblock(ama.me.id)
        XCTAssertTrue(kofi.recent.blocked.isEmpty)
        ama.online.playAgain(ama.recent.players[0], name: "Ama", rules: .abapa)
        await until("he can be asked again") { ama.online.asked?.state == .sent }
    }

    func testABlockMadeWithNoInternetIsSentWhenThereIsSome() async {
        let relay = LocalRelay()
        let (ama, kofi) = await played(relay)
        await leave(ama, kofi)
        await kofi.allowsInvitations()
        await relay.setReachable(false)
        await kofi.invitations.block(ama.me.id)
        XCTAssertEqual(kofi.recent.blocked.count, 1, "blocked on this phone at once")
        await relay.setReachable(true)
        await kofi.invitations.started()
        ama.online.playAgain(ama.recent.players[0], name: "Ama", rules: .abapa)
        await until("the relay refuses her") { ama.online.asked?.state == .unreachable }
    }

    func testABlockedPlayerIsNotListedAgainAfterAnotherGame() async {
        let relay = LocalRelay()
        let (ama, kofi) = await played(relay)
        await leave(ama, kofi)
        await kofi.invitations.block(ama.me.id)
        await play(ama, kofi)
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(kofi.recent.players.isEmpty)
    }

    // MARK: Words

    func testARefusalToAnInvitationHasPlainWords() {
        XCTAssertEqual(OnlineNetwork.explain(.ended), "That game has ended. Ask your friend to start a new one.")
        XCTAssertEqual(OnlinePlay.note(.init(to: "x", name: "Kofi", code: "K7M2QD", state: .asking)), "Asking Kofi…")
        XCTAssertEqual(OnlinePlay.note(.init(to: "x", name: "Kofi", code: "K7M2QD", state: .failed)),
                       "Kofi could not be asked just now. Send them the link instead.")
    }

    // MARK: The demo player

    func testInTheDemoAmaIsARecentPlayerWhoCanBeAskedAgain() async {
        let recent = RecentPlayers(defaults: TestSupport.defaults())
        let invitations = Invitations(me: .new(), recent: recent, dial: { throw CancellationError() }, access: Access(),
                                      defaults: TestSupport.defaults(), env: .sandbox)
        let network = OnlineNetwork.demo(script: .init(thinkTime: 0.05, joinDelay: 0.05))
        let online = OnlinePlay(session: TestSupport.session(), network: network, invitations: invitations)
        online.lobby.onStart = {}
        online.lobby.start(name: "Kofi", rules: .abapa)
        await until("Ama joins") { online.lobby.phase == .ready }
        await online.lobby.ready()
        await until("the game starts") { online.lobby.session.isStarted }
        await until("she is listed") { recent.players.first?.name == "Ama" }
        XCTAssertEqual(recent.players.first?.id, DemoPlayer.playerNumber)

        online.lobby.session.leaveNearbyGame()
        online.lobby.prepare(demo: true)
        online.playAgain(recent.players[0], name: "Kofi", rules: .abapa)
        await until("she is asked") { online.asked?.state == .sent }
        await until("and joins") { online.lobby.phase == .ready && online.lobby.opponent?.name == "Ama" }
    }
}
