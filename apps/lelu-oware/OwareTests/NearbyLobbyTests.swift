import MatchKit
import OwareEngine
import XCTest
@testable import Oware

/// Hosting and joining against the demo player: the same rooms and messages as two phones, with
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

    private func lobby(_ script: DemoPlayer.Script = .init(thinkTime: 0.01, joinDelay: 0.01)) -> (NearbyLobby, GameSession) {
        let session = TestSupport.session(track: { [weak self] in self?.events.append($0) })
        let lobby = NearbyLobby(session: session, network: DemoNetwork(script: script))
        return (lobby, session)
    }

    func testHostingTheDemoAmaAsksAndTheGameStartsOnAccept() async {
        let (lobby, session) = lobby()
        var started = false
        lobby.onStart = { started = true }
        lobby.host(name: "Kofi", rules: .namNam, starter: .creatorStarts)
        XCTAssertEqual(lobby.phase, .hosting)
        await until("Ama asks") { lobby.joinRequests.map(\.name) == ["Ama"] }
        XCTAssertFalse(started)
        await lobby.accept(lobby.joinRequests[0])
        await until("the game starts") { started }
        XCTAssertEqual(lobby.phase, .playing)
        XCTAssertEqual(session.remoteGame?.opponentName, "Ama")
        XCTAssertEqual(session.remoteGame?.mySide, .south)
        XCTAssertEqual(session.state.rules, .namNam, "the host's rules")
        XCTAssertTrue(session.humanToMove)
        XCTAssertEqual(events.first, .nearbyHosted(demo: true))
    }

    func testTheHostCanLetThemStart() async {
        let (lobby, session) = lobby()
        lobby.onStart = {}
        lobby.host(name: "Kofi", rules: .abapa, starter: .joiningPlayerStarts)
        await until("Ama asks") { !lobby.joinRequests.isEmpty }
        await lobby.accept(lobby.joinRequests[0])
        await until("Ama moves first") { session.state.moveNumber == 1 }
        XCTAssertTrue(session.humanToMove)
    }

    func testDecliningSendsAmaAway() async {
        let (lobby, _) = lobby()
        lobby.host(name: "Kofi", rules: .abapa, starter: .creatorStarts)
        await until("Ama asks") { !lobby.joinRequests.isEmpty }
        await lobby.decline(lobby.joinRequests[0])
        XCTAssertTrue(lobby.joinRequests.isEmpty)
        XCTAssertEqual(lobby.phase, .hosting, "still waiting for someone else")
    }

    func testJoiningTheDemoPlaysNorthAndAmaMovesFirst() async {
        let (lobby, session) = lobby()
        var started = false
        lobby.onStart = { started = true }
        lobby.browse()
        await until("Ama's game is listed") { lobby.games.map(\.name) == ["Ama's game"] }
        XCTAssertEqual(lobby.games.first?.rules, "Abapa")
        XCTAssertEqual(lobby.games.first?.creatorStarts, true, "the card can say Ama starts")
        XCTAssertNotNil(lobby.games.first?.gameID)
        lobby.join(lobby.games[0], name: "Esi")
        await until("seated") { started }
        XCTAssertEqual(session.remoteGame?.mySide, .north)
        XCTAssertEqual(session.bottomSide, .north)
        await until("Ama moves") { session.state.moveNumber == 1 }
        await until("my turn") { session.humanToMove }
        XCTAssertEqual(events.first, .nearbyJoined(demo: true))
    }

    func testAmaResignsWhenScriptedAndAgreesToARematch() async {
        let (lobby, session) = lobby(.init(resignAfter: 0, thinkTime: 0.01, joinDelay: 0.01))
        lobby.onStart = {}
        lobby.host(name: "Kofi", rules: .abapa, starter: .creatorStarts)
        await until("Ama asks") { !lobby.joinRequests.isEmpty }
        await lobby.accept(lobby.joinRequests[0])
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

    func testCancellingStopsHostingAndLeavesNoGame() async {
        let (lobby, session) = lobby()
        lobby.host(name: "Kofi", rules: .abapa, starter: .creatorStarts)
        lobby.cancel()
        XCTAssertEqual(lobby.phase, .choosing)
        XCTAssertNil(session.remoteGame)
    }

    /// The name is asked once and kept, trimmed; a blank one is not a name.
    func testTheNameIsKept() {
        let defaults = TestSupport.defaults()
        XCTAssertNil(NearbyLobby.savedName(defaults))
        NearbyLobby.saveName("  Kofi \n", defaults)
        XCTAssertEqual(NearbyLobby.savedName(defaults), "Kofi")
        NearbyLobby.saveName("   ", defaults)
        XCTAssertEqual(NearbyLobby.savedName(defaults), "Kofi")
    }

    /// The choice is stored by what it means, not by "you" or "them", which swap between phones;
    /// random is settled before the game is listed, so both phones agree.
    func testWhoStartsIsStoredByMeaningAndShownPerPhone() {
        XCTAssertEqual(NearbyLobby.Starter.allCases.map(\.title), ["Me", "Other player", "Random"])
        XCTAssertEqual(NearbyLobby.Starter.creatorStarts.firstPlayer, .south)
        XCTAssertEqual(NearbyLobby.Starter.joiningPlayerStarts.firstPlayer, .north)
        XCTAssertTrue([.south, .north].contains(NearbyLobby.Starter.random.firstPlayer))
        XCTAssertEqual(NearbyLobby.startNote(creatorStarts: true, creatorName: "Richard"), "Richard starts")
        XCTAssertEqual(NearbyLobby.startNote(creatorStarts: false, creatorName: "Richard"), "You start")
    }
}
