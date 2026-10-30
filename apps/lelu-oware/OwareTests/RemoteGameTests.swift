import MatchKit
import OwareEngine
import XCTest
@testable import Oware

/// Two phones, as two `GameSession`s joined by the in-memory transport: the host plays South, the
/// guest North, and the host's phone decides every move.
@MainActor
final class RemoteGameTests: XCTestCase {
    private let clock = ManualClock()
    private var hostEvents: [AnalyticsEvent] = []

    /// Waits for the sessions to catch up with each other.
    private func until(_ what: @autoclosure () -> String, timeout: TimeInterval = 5, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { return XCTFail("timed out waiting: \(what())") }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    /// Lets messages arrive, for checking that something did not happen.
    private func settle() async { try? await Task.sleep(nanoseconds: 50_000_000) }

    private struct Pair {
        let host: GameSession
        let guest: GameSession
        let hostLink: MatchLink
        let guestLink: MatchLink
        let guestTransport: LoopbackTransport
    }

    /// `ready`: both players press Ready, as on the Ready to play screen.
    private func pair(rules: RuleSet = .abapa, starter: Player = .south, hostPace: Double = 1, guestPace: Double = 1,
                      names: (host: String, guest: String) = ("Kofi", "Ama"), ready: Bool = true) async -> Pair {
        let host = TestSupport.session(track: { [weak self] in self?.hostEvents.append($0) })
        let guest = TestSupport.session()
        let hostTransport = LoopbackTransport(), guestTransport = LoopbackTransport()
        let hostLink = MatchLink(hosting: OwareMatch(rules: rules, starter: starter), name: names.host, pace: hostPace,
                                 transport: hostTransport, clock: clock)
        let guestLink = MatchLink(joiningAs: names.guest, pace: guestPace, transport: guestTransport, clock: clock)
        host.startRemote(hostLink)
        guest.startRemote(guestLink)
        hostTransport.connect(guestTransport)
        await until("the guest asks to join") { hostLink.joinRequests.count == 1 }
        await hostLink.accept(hostLink.joinRequests[0].peer)
        await until("both seated") { host.remoteGame?.opponentName.isEmpty == false && guest.remoteGame?.opponentName.isEmpty == false }
        if ready {
            await hostLink.ready()
            await guestLink.ready()
            await until("both phones ready") { host.isStarted && guest.isStarted }
        }
        return Pair(host: host, guest: guest, hostLink: hostLink, guestLink: guestLink, guestTransport: guestTransport)
    }

    func testBothPhonesStartTheSameGameEachOnTheirOwnSide() async {
        let p = await pair(rules: .namNam)
        XCTAssertEqual(p.host.remoteGame?.mySide, .south)
        XCTAssertEqual(p.guest.remoteGame?.mySide, .north)
        XCTAssertEqual(p.host.state, p.guest.state)
        XCTAssertEqual(p.guest.state.rules, .namNam, "the host's rules")
        XCTAssertTrue(p.host.humanToMove)
        XCTAssertFalse(p.guest.humanToMove)
        XCTAssertEqual(p.guest.sideName(.north), "You")
        XCTAssertEqual(p.guest.sideName(.south), "Kofi")
        XCTAssertEqual(p.guest.turnDescription, "Kofi's turn")
        XCTAssertEqual(p.host.turnDescription, "Your turn")
        XCTAssertEqual(p.host.bottomSide, .south)
        XCTAssertEqual(p.guest.bottomSide, .north, "the guest's board is turned round")
    }

    /// Each phone has its own sowing speed; in a game on two phones both sow at the slower one, so
    /// the boards keep in step, and nobody who chose Slow is hurried.
    func testBothPhonesSowAtTheSlowerSpeed() async {
        let p = await pair(hostPace: AppSettings.AnimationSpeed.fast.rawValue, guestPace: AppSettings.AnimationSpeed.slow.rawValue)
        await until("both know both speeds") { p.host.sharedPace == 0.7 && p.guest.sharedPace == 0.7 }

        // A rematch keeps it.
        let q = await pair(hostPace: 0.7, guestPace: 1.6)
        await until("the host's Slow wins") { q.host.sharedPace == 0.7 && q.guest.sharedPace == 0.7 }
        q.host.resign()
        await until("over") { q.guest.isGameOver }
        q.host.requestRematch()
        q.guest.requestRematch()
        await until("rematch") { !q.host.isGameOver && !q.guest.isGameOver }
        XCTAssertEqual(q.guest.sharedPace, 0.7)

        // Alone, a phone keeps its own speed.
        XCTAssertNil(TestSupport.session().sharedPace)
    }

    /// Connected is not started: until both phones have acknowledged the same opening, nobody moves.
    func testNoMoveBeforeBothPhonesAreReady() async {
        let host = TestSupport.session()
        let link = MatchLink(hosting: OwareMatch(rules: .abapa), name: "Kofi", transport: LoopbackTransport(), clock: clock)
        host.startRemote(link)
        XCTAssertFalse(host.isStarted)
        XCTAssertFalse(host.humanToMove, "nobody to play with yet")
        host.play(house: 2)
        await settle()
        XCTAssertEqual(host.state.moveNumber, 0)
        XCTAssertEqual(host.turnDescription, "Waiting for the other player…")
    }

    /// Being seated is not enough: the game starts only once both players have pressed Ready.
    func testNeitherPhoneStartsUntilBothPressReady() async {
        let p = await pair(ready: false)
        await settle()
        XCTAssertFalse(p.host.isStarted)
        await p.hostLink.ready()
        await settle()
        XCTAssertFalse(p.host.isStarted, "the guest has not pressed Ready")
        XCTAssertFalse(p.guest.isStarted)
        await p.guestLink.ready()
        await until("both start") { p.host.isStarted && p.guest.isStarted }
        XCTAssertTrue(p.host.humanToMove)
    }

    /// iOS only says "iPhone", so two players often keep the default name: add the side's colour.
    func testTwoPlayersWithTheSameNameAreToldApartByColour() async {
        let p = await pair(names: ("Oware Player", "Oware Player"))
        XCTAssertEqual(p.host.opponentName, "Oware Player · red")
        XCTAssertEqual(p.guest.opponentName, "Oware Player · gold")
    }

    /// Leaving on purpose is not a lost connection: no "reconnecting", the computer is offered at once.
    func testLeavingIsToldApartFromALostPhone() async {
        let p = await pair()
        p.host.play(house: 2)
        await until("guest sees the move") { p.guest.state.moveNumber == 1 }
        p.guest.leaveNearbyGame()
        await until("the host hears Ama left") { p.host.opponentLeft }
        XCTAssertFalse(p.host.isReconnecting)
        XCTAssertTrue(p.host.offersComputer)
    }

    func testTheHostMovesAndTheGuestsBoardMatches() async {
        let p = await pair()
        p.host.play(house: 2)
        await until("guest sees the move") { p.guest.state.moveNumber == 1 }
        XCTAssertEqual(p.guest.state, p.host.state)
        XCTAssertTrue(p.guest.humanToMove)
    }

    func testTheGuestMovesAndTheHostsBoardMatches() async {
        let p = await pair()
        p.host.play(house: 2)
        await until("guest's turn") { p.guest.humanToMove }
        p.guest.play(house: 8)
        await until("host sees the move") { p.host.state.moveNumber == 2 }
        await until("guest sees its own move once the host agrees") { p.guest.state.moveNumber == 2 }
        XCTAssertEqual(p.guest.state, p.host.state)
    }

    func testNorthCanStart() async {
        let p = await pair(starter: .north)
        XCTAssertFalse(p.host.humanToMove)
        XCTAssertTrue(p.guest.humanToMove)
        p.guest.play(house: 6)
        await until("host sees the move") { p.host.state.moveNumber == 1 }
        XCTAssertTrue(p.host.humanToMove)
    }

    func testYouCannotMoveOnTheOtherPlayersTurn() async {
        let p = await pair()
        p.guest.play(house: 8)
        await settle()
        XCTAssertEqual(p.host.state.moveNumber, 0)
        p.host.play(house: 2)
        await until("guest sees the move") { p.guest.state.moveNumber == 1 }
        p.host.play(house: 3)   // not the host's turn any more
        await settle()
        XCTAssertEqual(p.host.state.moveNumber, 1)
        XCTAssertEqual(p.guest.state.moveNumber, 1)
    }

    func testThereIsNoUndoAndNoHint() async {
        let p = await pair()
        p.host.play(house: 2)
        await until("guest's turn") { p.guest.humanToMove }
        for session in [p.host, p.guest] {
            XCTAssertFalse(session.canUndo)
            XCTAssertFalse(session.canHint)
            XCTAssertFalse(session.canAgreeToStop)
            XCTAssertTrue(session.canEndGame, "resigning is allowed")
        }
        p.guest.undo()
        p.guest.requestHint()
        await settle()
        XCTAssertEqual(p.host.state.moveNumber, 1)
        XCTAssertNil(p.guest.previewMove)
    }

    func testResigningEndsItOnBothPhones() async {
        let p = await pair()
        p.host.play(house: 2)
        await until("guest sees the move") { p.guest.state.moveNumber == 1 }
        p.guest.resign()
        await until("both over") { p.host.isGameOver && p.guest.isGameOver }
        XCTAssertEqual(p.host.state.outcome, .win(.south, .agreement))
        XCTAssertEqual(p.guest.state.outcome, .win(.south, .agreement))
        XCTAssertTrue(p.host.turnDescription.hasPrefix("You win"))
        XCTAssertTrue(p.guest.turnDescription.hasPrefix("You lose"))
    }

    func testARematchNeedsBothAndTheStarterSwaps() async {
        let p = await pair()
        p.host.resign()
        await until("both over") { p.host.isGameOver && p.guest.isGameOver }

        p.host.requestRematch()
        await until("guest hears the host wants another") { p.guest.rematchAsked == [.south] }
        await settle()
        XCTAssertTrue(p.host.isGameOver && p.guest.isGameOver, "one player asking is not enough")

        p.guest.requestRematch()
        await until("a new game on both") { !p.host.isGameOver && !p.guest.isGameOver }
        XCTAssertEqual(p.host.state, p.guest.state)
        XCTAssertEqual(p.host.state.moveNumber, 0)
        XCTAssertEqual(p.host.sideToMove, .north, "the other player starts the rematch")
        XCTAssertTrue(p.guest.humanToMove)
        XCTAssertEqual(p.guest.rematchAsked, [])
    }

    func testAPlayerGoneForAMinuteCanBeReplacedByTheComputer() async {
        let p = await pair()
        p.host.play(house: 2)
        await until("guest sees the move") { p.guest.state.moveNumber == 1 }
        p.guestTransport.isQuiet = true   // the guest walks out of range

        clock.advance(by: 7)
        await p.hostLink.tick()
        XCTAssertTrue(p.host.isReconnecting)
        XCTAssertFalse(p.host.offersComputer, "not yet: they may come back")

        clock.advance(by: 54)
        await p.hostLink.tick()
        XCTAssertTrue(p.host.offersComputer)

        let position = p.host.state
        p.host.finishAgainstComputer(difficulty: .beginner)
        XCTAssertEqual(p.host.state, position, "the game carries on from where it was")
        XCTAssertEqual(p.host.mode, .versusAI(difficulty: .beginner, personality: .balanced, humanPlays: .south))
        XCTAssertFalse(p.host.offersComputer)
        XCTAssertNil(p.host.remoteGame)

        await until("the computer moves for Ama") { p.host.state.moveNumber == 2 }
        p.host.resign()
        XCTAssertEqual(hostEvents.last, .gameFinished(mode: "computer", level: "beginner", result: "loss", rules: "abapa"),
                       "recorded as an ordinary game against the computer")
    }

    func testTheGuestCanFinishAgainstTheComputerToo() async {
        let p = await pair()
        p.guestTransport.isQuiet = true
        clock.advance(by: 61)
        await p.guestLink.tick()
        XCTAssertTrue(p.guest.offersComputer)
        p.guest.finishAgainstComputer(difficulty: .beginner)
        XCTAssertEqual(p.guest.mode, .versusAI(difficulty: .beginner, personality: .balanced, humanPlays: .north))
        await until("the computer opens as South") { p.guest.state.moveNumber == 1 }
    }

    func testBothPhonesAlwaysShowTheSamePosition() async {
        let p = await pair()
        // Seeded, so a failure can be replayed.
        struct LCG: RandomNumberGenerator {
            var s: UInt64
            mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s }
        }
        var rng = LCG(s: 3)   // this game ends with a player who could not be fed
        var plies = 0
        while !p.host.isGameOver, plies < 400 {
            let mover = p.host.humanToMove ? p.host : p.guest
            await until("someone can move") { mover.humanToMove }
            guard let move = mover.state.legalMoves().randomElement(using: &rng) else { break }
            mover.play(house: move.absoluteIndex)
            plies += 1
            // A move that can feed nobody ends the game without sowing, so it is not counted.
            await until("both show move \(plies): host at \(p.host.state.moveNumber), guest at \(p.guest.state.moveNumber)") {
                (p.host.state.moveNumber == plies && p.guest.state.moveNumber == plies)
                    || (p.host.isGameOver && p.guest.isGameOver)
            }
            XCTAssertEqual(p.host.state, p.guest.state, "after move \(plies)")
        }
        XCTAssertTrue(p.host.isGameOver || plies == 400)
        XCTAssertEqual(p.host.state.outcome, p.guest.state.outcome)
    }
}
