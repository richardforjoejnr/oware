import MatchKit
import OwareEngine
import XCTest
@testable import Oware

/// Starting and joining against the demo player: the same rooms and messages as two phones, with
/// the demo's phone inside the app.
@MainActor
final class NearbyLobbyTests: XCTestCase {
    private var events: [AnalyticsEvent] = []

    private func until(_ what: @autoclosure () -> String, timeout: TimeInterval = 5, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { return XCTFail("timed out waiting: \(what())") }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    /// Kept for the whole test, as the app keeps it: Ama's phone lives in the lobby's network.
    private var kept: NearbyLobby?

    private func lobby(_ script: DemoPlayer.Script = .init(thinkTime: 0.01, joinDelay: 0.01)) -> (NearbyLobby, GameSession) {
        let session = TestSupport.session(track: { [weak self] in self?.events.append($0) })
        let lobby = NearbyLobby(session: session, network: DemoNetwork(script: script))
        kept = lobby
        return (lobby, session)
    }

    /// Opening Play nearby does not look by itself: Look for games does, and lists them.
    func testLookingForGamesIsATap() async {
        let (lobby, _) = lobby()
        lobby.open()
        XCTAssertEqual(lobby.phase, .lobby)
        XCTAssertFalse(lobby.isLooking)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(lobby.games.isEmpty, "nothing until asked")
        lobby.look()
        XCTAssertTrue(lobby.isLooking)
        await until("Ama's game is listed") { lobby.games.map(\.name) == ["Ama's game"] }
        XCTAssertEqual(lobby.games.first?.rules, "Abapa")
        XCTAssertEqual(lobby.games.first?.creatorName, "Ama")
        XCTAssertEqual(lobby.games.first?.creatorStarts, true, "the card can say Ama starts")
        XCTAssertNotNil(lobby.games.first?.gameID)
    }

    /// Stop looking: back to the Look for games button, the list forgotten.
    func testLookingCanBeStopped() async {
        let (lobby, _) = lobby()
        lobby.open()
        lobby.look()
        await until("Ama's game is listed") { !lobby.games.isEmpty }
        lobby.stopLooking()
        XCTAssertFalse(lobby.isLooking)
        XCTAssertTrue(lobby.games.isEmpty)
        XCTAssertEqual(lobby.phase, .lobby)
    }

    /// Start nearby game: listed and waiting; when someone comes, both see Ready to play, and the
    /// game starts only once both have pressed Ready (a connection alone never starts it).
    func testStartingWaitsThenBothPressReady() async {
        let (lobby, session) = lobby()
        var started = false
        lobby.onStart = { started = true }
        lobby.start(name: "Kofi", rules: .namNam)
        XCTAssertEqual(lobby.phase, .waiting)
        await until("Ama comes") { lobby.phase == .ready }
        XCTAssertEqual(lobby.opponent?.name, "Ama")
        XCTAssertTrue(lobby.isCreator)
        XCTAssertTrue(lobby.canSayNotNow)
        XCTAssertFalse(started)
        XCTAssertNil(session.remoteGame)
        await lobby.ready()
        await until("the game starts") { started }
        XCTAssertEqual(lobby.phase, .playing)
        XCTAssertEqual(session.remoteGame?.opponentName, "Ama")
        XCTAssertEqual(session.remoteGame?.mySide, .south)
        XCTAssertEqual(session.state.rules, .namNam, "the creator's rules")
        XCTAssertTrue(session.isStarted)
        XCTAssertTrue(session.humanToMove, "whoever starts the game moves first")
        XCTAssertEqual(events.first, .nearbyHosted(demo: true))
    }

    /// Not now sends Ama away; the game stays listed for someone else.
    func testNotNowKeepsTheGameWaiting() async {
        let (lobby, _) = lobby()
        lobby.start(name: "Kofi", rules: .abapa)
        await until("Ama comes") { lobby.phase == .ready }
        await lobby.notNow()
        XCTAssertEqual(lobby.phase, .waiting, "still waiting for someone else")
        XCTAssertNil(lobby.opponent)
    }

    /// Joining shows Ready to play at once; Ama (the creator) is ready, and nothing starts until
    /// this phone presses Ready too.
    func testJoiningStartsOnlyWhenIPressReady() async {
        let (lobby, session) = lobby()
        var started = false
        lobby.onStart = { started = true }
        lobby.open()
        lobby.look()
        await until("Ama's game is listed") { !lobby.games.isEmpty }
        lobby.join(lobby.games[0], name: "Esi")
        XCTAssertEqual(lobby.phase, .ready)
        XCTAssertFalse(lobby.isCreator)
        XCTAssertFalse(lobby.canSayNotNow)
        XCTAssertEqual(lobby.opponent?.name, "Ama")
        await until("Ama is there and ready") { lobby.opponent?.isReady == true && lobby.canPressReady }
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(started)
        await lobby.ready()
        await until("the game starts") { started }
        XCTAssertEqual(session.remoteGame?.mySide, .north)
        XCTAssertEqual(session.bottomSide, .north)
        await until("Ama moves") { session.state.moveNumber == 1 }
        await until("my turn") { session.humanToMove }
        XCTAssertEqual(events.first, .nearbyJoined(demo: true))
    }

    func testAmaResignsWhenScriptedAndAgreesToARematch() async {
        let (lobby, session) = lobby(.init(resignAfter: 0, thinkTime: 0.01, joinDelay: 0.01))
        lobby.onStart = {}
        lobby.start(name: "Kofi", rules: .abapa)
        await until("Ama comes") { lobby.phase == .ready }
        await lobby.ready()
        await until("the game starts") { lobby.phase == .playing }
        await until("my turn") { session.humanToMove }
        session.play(house: 0)
        await until("Ama resigns") { session.isGameOver }
        XCTAssertEqual(session.state.outcome?.winner, .south)
        await until("Ama asks for a rematch") { session.rematchAsked.contains(.north) }
        session.requestRematch()
        await until("the rematch starts, and Ama only resigns the first game") { !session.isGameOver }
        await until("Ama starts the rematch") { session.state.moveNumber == 1 }
        XCTAssertFalse(session.isGameOver)
        XCTAssertEqual(events.last, .nearbyFinished(result: "win", rules: "abapa"))
    }

    /// Cancel takes the game down and goes back to Play nearby, not looking until asked.
    func testCancellingTakesTheGameDown() {
        let (lobby, session) = lobby()
        lobby.start(name: "Kofi", rules: .abapa)
        lobby.cancel()
        XCTAssertEqual(lobby.phase, .lobby)
        XCTAssertNil(session.remoteGame)
        XCTAssertFalse(lobby.isLooking)
    }

    /// What nearby players see: the saved name, else the Game Center name, else Oware Player;
    /// never "Me" or "You".
    func testMyNameFallsBackToGameCenterThenOwarePlayer() {
        XCTAssertEqual(NearbyLobby.myName(saved: "Kofi", gameCenter: "kofi99"), "Kofi")
        XCTAssertEqual(NearbyLobby.myName(saved: nil, gameCenter: "kofi99"), "kofi99")
        XCTAssertEqual(NearbyLobby.myName(saved: nil, gameCenter: " "), "Oware Player")
        XCTAssertEqual(NearbyLobby.myName(saved: nil, gameCenter: nil), "Oware Player")
    }

    func testTheSameNameIsToldApartByTheSidesColour() {
        XCTAssertEqual(NearbyLobby.tellApart("Oware Player", from: "Oware Player", side: .north), "Oware Player · red")
        XCTAssertEqual(NearbyLobby.tellApart("Oware Player", from: "Oware Player", side: .south), "Oware Player · gold")
        XCTAssertEqual(NearbyLobby.tellApart("Ama", from: "Oware Player", side: .north), "Ama")
    }

    /// The Nearby name is kept, trimmed; a blank one is not a name.
    func testTheNameIsKept() {
        let defaults = TestSupport.defaults()
        XCTAssertNil(NearbyLobby.savedName(defaults))
        NearbyLobby.saveName("  Kofi \n", defaults)
        XCTAssertEqual(NearbyLobby.savedName(defaults), "Kofi")
        NearbyLobby.saveName("   ", defaults)
        XCTAssertEqual(NearbyLobby.savedName(defaults), "Kofi")
    }

    /// Whoever starts the game moves first; the card says so on the other phone.
    func testTheCardSaysWhoStarts() {
        XCTAssertEqual(NearbyLobby.startNote(creatorStarts: true, creatorName: "Richard"), "Richard starts")
        XCTAssertEqual(NearbyLobby.startNote(creatorStarts: false, creatorName: "Richard"), "You start")
    }
}
