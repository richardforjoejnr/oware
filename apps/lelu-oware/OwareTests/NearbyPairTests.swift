import MatchKit
import OwareEngine
import XCTest
@testable import Oware

/// Two phones, each with its own Play nearby lobby, over the in-memory transport: Ready in either
/// order, a started game left off the list, and a dropped connection coming back by itself.
@MainActor
final class NearbyPairTests: XCTestCase {
    /// The air between the two phones: the one game listed, and every connection to it.
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
    }

    /// One phone's view of the air.
    final class AirNetwork: NearbyNetwork {
        let air: Air
        let isDemo = false
        init(_ air: Air) { self.air = air }

        func host(gameName: String, info: [String: String], status: @escaping @MainActor (NearbyStatus) -> Void) throws -> any MatchTransport {
            let transport = LoopbackTransport()
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

        func stopFinding() { if air.hostTransport != nil { air.started = true } }
        func shutDown() {}

        func watchAccess(_ update: @escaping @MainActor (NearbyAccess) -> Void) {
            air.watchers.append(update)
            update(air.access)
        }

        func stopWatchingAccess() { air.watchers = [] }
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
        XCTAssertEqual(guest.state, host.state)
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

    /// Moves made while one phone was away are there when it comes back.
    func testMovesMadeWhileAwayArriveOnReturn() async {
        let p = await playing()
        p.air.canRejoin = false
        p.air.guestTransports[0].drop()
        await until("Kofi sees Ama go") { p.host.session.isReconnecting }
        p.host.session.play(house: 2)
        XCTAssertEqual(p.guest.session.state.moveNumber, 0, "Ama missed it")
        p.air.canRejoin = true
        await until("Ama comes back with the move", timeout: 8) { p.guest.session.state.moveNumber == 1 }
        XCTAssertEqual(p.guest.session.state, p.host.session.state)
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
