import MatchKit
import MatchKitNearby
import OwareEngine
import XCTest
@testable import Oware

/// Two phones, each with its own Play nearby lobby, over the in-memory transport: Ready in either
/// order, a started game left off the list, and a dropped connection coming back by itself.
@MainActor
final class NearbyPairTests: XCTestCase {
    /// The air between the two phones: the one game listed, and every connection to it.
    @MainActor
    final class Air {
        var hostTransport: LoopbackTransport?
        var name = ""
        var info: [String: String] = [:]
        var started = false
        var guestTransports: [LoopbackTransport] = []
        /// False: the host's phone cannot be reached again (gone for good).
        var canRejoin = true
        /// Local Network permission and Wi-Fi, as the phone reports them.
        var access = NearbyAccess() { didSet { watchers.forEach { $0(access) } } }
        var watchers: [@MainActor (NearbyAccess) -> Void] = []
        /// Times the phone was asked to look at Local Network and Wi-Fi again.
        var rechecks = 0
    }

    /// One phone's view of the air.
    final class AirNetwork: NearbyNetwork {
        let air: Air
        let isDemo = false
        /// This phone made the game (only the creator's phone marks it started).
        private var hosted = false
        init(_ air: Air) { self.air = air }

        func host(gameName: String, info: [String: String], status: @escaping @MainActor (NearbyStatus) -> Void) throws -> any MatchTransport {
            let transport = LoopbackTransport()
            hosted = true
            air.hostTransport = transport
            air.name = gameName
            air.info = info
            return transport
        }

        func browse(games: @escaping @MainActor ([NearbyListing]) -> Void, status: @escaping @MainActor (NearbyStatus) -> Void) {
            guard air.hostTransport != nil else { return games([]) }
            let info = air.started ? air.info.merging(["started": "1"]) { $1 } : air.info
            games([NearbyListing(name: air.name, info: info)])
        }

        func connect(to listing: NearbyListing) -> any MatchTransport {
            let transport = LoopbackTransport()
            air.guestTransports.append(transport)
            air.hostTransport?.connect(transport)
            return transport
        }

        func rejoin(_ listing: NearbyListing) -> (any MatchTransport)? {
            air.canRejoin ? connect(to: listing) : nil
        }

        func stopFinding() { if hosted { air.started = true } }
        func shutDown() {}

        func watchAccess(_ update: @escaping @MainActor (NearbyAccess) -> Void) {
            air.watchers.append(update)
            update(air.access)
        }

        func stopWatchingAccess() { air.watchers = [] }

        func recheckAccess() {
            air.rechecks += 1
            air.watchers.forEach { $0(air.access) }
        }
    }

    private func until(_ what: @autoclosure () -> String, timeout: TimeInterval = 5, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { return XCTFail("timed out waiting: \(what())") }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func settle() async { try? await Task.sleep(nanoseconds: 50_000_000) }

    private struct Phones {
        let air: Air
        let host: NearbyLobby
        let guest: NearbyLobby
    }

    /// Kofi starts a game; Ama finds it and joins. Nobody has pressed Ready.
    private func phones() async -> Phones {
        let air = Air()
        let host = NearbyLobby(session: TestSupport.session(), network: AirNetwork(air))
        let guest = NearbyLobby(session: TestSupport.session(), network: AirNetwork(air))
        host.onStart = {}
        guest.onStart = {}
        host.start(name: "Kofi", rules: .abapa)
        guest.look()
        await until("Kofi's game is listed") { guest.games.count == 1 }
        guest.join(guest.games[0], name: "Ama")
        await until("Kofi sees Ama") { host.phase == .ready && host.opponent?.name == "Ama" }
        return Phones(air: air, host: host, guest: guest)
    }

    /// Both ready, in that order, and the game under way on both phones.
    private func playing() async -> Phones {
        let p = await phones()
        await p.host.ready()
        await p.guest.ready()
        await until("both playing") { p.host.phase == .playing && p.guest.phase == .playing }
        await until("both started") { p.host.session.isStarted && p.guest.session.isStarted }
        return p
    }

    // MARK: Ready

    /// The joining player need not wait for the creator: either may press Ready first.
    func testTheGuestCanPressReadyFirst() async {
        let p = await phones()
        XCTAssertTrue(p.guest.canPressReady, "Ready works before the creator has said anything")
        await p.guest.ready()
        XCTAssertTrue(p.guest.iAmReady)
        XCTAssertFalse(p.guest.canPressReady, "pressed once")
        await until("Kofi sees Ama is ready") { p.host.opponent?.isReady == true }
        await settle()
        XCTAssertEqual(p.guest.phase, .ready, "nothing starts until both are ready")
        XCTAssertEqual(p.host.phase, .ready)
        XCTAssertTrue(p.host.canPressReady)

        await p.host.ready()
        await until("the game starts on both phones") { p.host.phase == .playing && p.guest.phase == .playing }
        await until("both started") { p.host.session.isStarted && p.guest.session.isStarted }
        XCTAssertTrue(p.host.session.humanToMove, "the creator moves first")
        XCTAssertEqual(p.guest.session.remoteGame?.mySide, .north)
    }

    func testTheCreatorCanPressReadyFirst() async {
        let p = await phones()
        await p.host.ready()
        await until("Ama sees Kofi is ready") { p.guest.opponent?.isReady == true }
        await settle()
        XCTAssertEqual(p.host.phase, .ready, "nothing starts until both are ready")
        await p.guest.ready()
        await until("the game starts on both phones") { p.host.phase == .playing && p.guest.phase == .playing }
    }

    /// Both phones show who has pressed Ready, whoever pressed it first.
    func testBothPhonesSeeEitherReady() async {
        let p = await phones()
        XCTAssertEqual(p.host.opponent?.isReady, false)
        XCTAssertEqual(p.guest.opponent?.isReady, false)
        await p.guest.ready()
        await until("Kofi sees Ama ready") { p.host.opponent?.isReady == true }
        XCTAssertEqual(p.guest.opponent?.isReady, false, "Kofi has not pressed it")
        await p.host.ready()
        await until("the game starts") { p.host.phase == .playing && p.guest.phase == .playing }
    }

    /// Not now after Ama said Ready: she is told no, and the next player to join starts clean,
    /// not already ready.
    func testNotNowAfterTheGuestIsReadyStartsTheNextOneClean() async {
        let p = await phones()
        await p.guest.ready()
        await until("Kofi sees Ama ready") { p.host.opponent?.isReady == true }
        XCTAssertTrue(p.host.canSayNotNow)
        await p.host.notNow()
        XCTAssertEqual(p.host.phase, .waiting)
        await until("Ama is told no") { if case .refused = p.guest.phase { true } else { false } }
        XCTAssertFalse(p.air.started, "Kofi's game is still offered")

        let yaw = NearbyLobby(session: TestSupport.session(), network: AirNetwork(p.air))
        yaw.onStart = {}
        yaw.look()
        await until("Yaw sees the game") { yaw.games.count == 1 }
        yaw.join(yaw.games[0], name: "Yaw")
        await until("Kofi sees Yaw") { p.host.phase == .ready && p.host.opponent?.name == "Yaw" }
        await settle()
        XCTAssertEqual(p.host.opponent?.isReady, false, "Yaw has not pressed Ready")
        await p.host.ready()
        await settle()
        XCTAssertEqual(p.host.phase, .ready, "nothing starts until Yaw is ready too")
        await yaw.ready()
        await until("the game starts") { p.host.phase == .playing && yaw.phase == .playing }
    }

    /// The joining player cancels on the Ready screen: the creator is back to waiting, game listed.
    func testTheJoiningPlayerCancellingLeavesTheGameOpen() async {
        let p = await phones()
        p.guest.cancel()
        await until("Kofi waits again") { p.host.phase == .waiting }
        XCTAssertNil(p.host.opponent)
        XCTAssertFalse(p.air.started)
    }

    func testNeitherPressingReadyStartsNothing() async {
        let p = await phones()
        await settle()
        XCTAssertEqual(p.host.phase, .ready)
        XCTAssertEqual(p.guest.phase, .ready)
        XCTAssertNil(p.host.session.remoteGame)
    }

    // MARK: The list

    /// A game that has started stays findable (for its guest to come back) but is not offered
    /// to anyone else.
    func testAStartedGameIsNotListed() async {
        let p = await playing()
        XCTAssertTrue(p.air.started)
        let third = NearbyLobby(session: TestSupport.session(), network: AirNetwork(p.air))
        third.look()
        await settle()
        XCTAssertTrue(third.games.isEmpty)
    }

    // MARK: Reconnecting

    /// The joining phone's connection breaks (its app went to the background): it connects again
    /// by itself, both banners go, and play carries on from the same position.
    func testTheGuestsConnectionDroppingComesBackByItself() async {
        let p = await playing()
        let host = p.host.session, guest = p.guest.session
        host.play(house: 2)
        await until("Ama sees the move") { guest.state.moveNumber == 1 }

        p.air.guestTransports[0].drop()
        await until("Ama is back on Kofi's phone") { !host.isReconnecting && p.air.guestTransports.count == 2 }
        await until("Kofi is back on Ama's phone") { !guest.isReconnecting }
        await until("the same position on both") { guest.state == host.state }
        XCTAssertFalse(host.offersComputer)
        XCTAssertFalse(guest.offersComputer)

        await until("Ama's turn") { guest.humanToMove }
        guest.play(house: guest.state.legalMoves().first!.absoluteIndex)
        await until("Kofi sees Ama's move") { host.state.moveNumber == 2 }
        XCTAssertEqual(guest.state, host.state)
    }

    /// The creator's phone drops the connection: the joining phone finds the game again.
    func testTheHostsConnectionDroppingComesBackToo() async {
        let p = await playing()
        let host = p.host.session, guest = p.guest.session
        p.air.hostTransport?.drop()
        await until("Ama connects again") { p.air.guestTransports.count == 2 }
        await until("both back") { !host.isReconnecting && !guest.isReconnecting }
        host.play(house: 2)
        await until("Ama sees Kofi's move") { guest.state.moveNumber == 1 }
    }

    /// A move made before the creator's phone noticed Ama had gone (her phone went quiet first)
    /// is on her board when she comes back.
    func testAMoveMissedWhileAwayArrivesOnReturn() async {
        let p = await playing()
        let guestLink = p.air.guestTransports[0]
        guestLink.isQuiet = true                 // out of range: nothing gets through yet
        p.host.session.play(house: 2)            // not reconnecting yet, so this is allowed
        await settle()
        XCTAssertEqual(p.guest.session.state.moveNumber, 0, "Ama missed it")
        guestLink.drop()                         // then the connection breaks
        await until("Ama comes back with the move", timeout: 8) { p.guest.session.state.moveNumber == 1 }
        await until("the same position on both") { p.guest.session.state == p.host.session.state }
    }

    /// Leaving the game ends it for the other phone at once: no reconnecting.
    func testLeavingIsNotReconnected() async {
        let p = await playing()
        p.guest.session.leaveNearbyGame()
        await until("Kofi hears Ama left") { p.host.session.opponentLeft }
        await settle()
        XCTAssertFalse(p.host.session.isReconnecting)
        XCTAssertEqual(p.air.guestTransports.count, 1, "no attempt to come back")
    }

    // MARK: Before looking: Local Network and Wi-Fi

    /// Local Network off for the app: nothing nearby can be found, so Start and Look for games are
    /// greyed out under a message saying how to turn it on, until it is on.
    func testLocalNetworkOffGreysOutStartingAndLooking() async {
        let air = Air()
        air.access.localNetworkAllowed = false
        let lobby = NearbyLobby(session: TestSupport.session(), network: AirNetwork(air))
        lobby.prepare(demo: false)
        XCTAssertEqual(lobby.blocker, .localNetwork)
        XCTAssertFalse(lobby.canSearch)
        lobby.start(name: "Kofi", rules: .abapa)
        XCTAssertEqual(lobby.phase, .lobby, "no game is started")
        XCTAssertNil(air.hostTransport)
        lobby.look()
        XCTAssertFalse(lobby.isLooking)

        air.access.localNetworkAllowed = true   // turned on in Settings, then back to the app
        XCTAssertNil(lobby.blocker)
        lobby.look()
        XCTAssertTrue(lobby.isLooking)
    }

    /// Wi-Fi seems off. iOS cannot tell an unconnected radio from one switched off, and two phones
    /// can still find each other with Wi-Fi off in Control Center, so Try anyway lifts it.
    func testWiFiOffGreysOutUntilTriedAnyway() async {
        let air = Air()
        air.access.wifiOn = false
        let lobby = NearbyLobby(session: TestSupport.session(), network: AirNetwork(air))
        lobby.prepare(demo: false)
        XCTAssertEqual(lobby.blocker, .wifi)
        XCTAssertFalse(lobby.canSearch)
        lobby.tryAnyway()
        XCTAssertNil(lobby.blocker)
        lobby.start(name: "Kofi", rules: .abapa)
        XCTAssertEqual(lobby.phase, .waiting)
    }

    /// Check again under "Wi-Fi seems off" looks again, and says so when it is still off.
    func testCheckAgainLooksAgain() async {
        let air = Air()
        air.access.wifiOn = false
        let lobby = NearbyLobby(session: TestSupport.session(), network: AirNetwork(air))
        lobby.prepare(demo: false)
        XCTAssertFalse(lobby.stillOff, "nothing checked again yet")

        lobby.checkAgain()
        XCTAssertEqual(air.rechecks, 1)
        XCTAssertEqual(lobby.blocker, .wifi)
        XCTAssertTrue(lobby.stillOff, "the card says it is still off: the tap did something")

        // Wi-Fi switched on without the phone saying so (as when the app was in the background).
        let watchers = air.watchers
        air.watchers = []
        air.access.wifiOn = true
        air.watchers = watchers
        XCTAssertEqual(lobby.blocker, .wifi, "not seen yet")
        lobby.checkAgain()
        XCTAssertNil(lobby.blocker)
        XCTAssertTrue(lobby.canSearch)
        XCTAssertFalse(lobby.stillOff)
    }

    /// Coming back to the app (from Settings or Control Center) looks again by itself, quietly.
    func testComingBackToTheAppLooksAgain() async {
        let air = Air()
        air.access.wifiOn = false
        let lobby = NearbyLobby(session: TestSupport.session(), network: AirNetwork(air))
        lobby.prepare(demo: false)
        lobby.recheck()
        XCTAssertEqual(air.rechecks, 1)
        XCTAssertFalse(lobby.stillOff, "no \"still off\" for a check the player did not ask for")
    }

    /// Wi-Fi counts as on when either a Wi-Fi network is there or the peer-to-peer Wi-Fi nearby
    /// play uses is up (Wi-Fi on, but not joined to a network).
    func testWiFiIsOnWithANetworkOrPeerToPeer() {
        XCTAssertTrue(LiveNearbyNetwork.wifiOn(network: true, peerToPeer: false))
        XCTAssertTrue(LiveNearbyNetwork.wifiOn(network: false, peerToPeer: true))
        XCTAssertFalse(LiveNearbyNetwork.wifiOn(network: false, peerToPeer: false))
    }

    func testWiFiComingOnLiftsTheBlock() async {
        let air = Air()
        air.access.wifiOn = false
        let lobby = NearbyLobby(session: TestSupport.session(), network: AirNetwork(air))
        lobby.prepare(demo: false)
        XCTAssertEqual(lobby.blocker, .wifi)
        air.access.wifiOn = true
        XCTAssertNil(lobby.blocker)
    }

    /// Local Network matters more: it is the one to fix first when both are off.
    func testLocalNetworkIsShownBeforeWiFi() async {
        let air = Air()
        air.access = NearbyAccess(localNetworkAllowed: false, wifiOn: false)
        let lobby = NearbyLobby(session: TestSupport.session(), network: AirNetwork(air))
        lobby.prepare(demo: false)
        XCTAssertEqual(lobby.blocker, .localNetwork)
    }

    /// The pretend player needs neither.
    func testTheDemoIsNeverGreyedOut() async {
        let lobby = NearbyLobby(session: TestSupport.session(), network: DemoNetwork())
        lobby.prepare(demo: true)
        XCTAssertNil(lobby.blocker)
        XCTAssertTrue(lobby.canSearch)
    }
}
