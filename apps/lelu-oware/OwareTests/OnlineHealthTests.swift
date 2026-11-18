import MatchKit
import MatchKitOnline
import XCTest
@testable import Oware

/// The check an app makes as it opens: is the relay there, and is Oware open on it? Play online
/// on Home is greyed out when it is not, rather than failing after Start game.
@MainActor
final class OnlineHealthTests: XCTestCase {
    private func health(_ relay: LocalRelay, at clock: @escaping () -> Date = Date.init) -> OnlineHealth {
        OnlineHealth(dial: relay.dial, wait: 0.2, now: clock)
    }

    func testNothingIsHeldAgainstOnlinePlayBeforeTheFirstAnswer() {
        let health = health(LocalRelay())
        XCTAssertEqual(health.state, .unknown)
        XCTAssertFalse(health.isDown)
        XCTAssertNil(health.note)
    }

    func testARelayThatAnswersIsUp() async {
        let relay = LocalRelay()
        let health = health(relay)
        let state = await health.check()
        XCTAssertEqual(state, .up)
        XCTAssertFalse(health.isDown)
        let asked = await relay.received["health"]
        XCTAssertEqual(asked, 1)
    }

    func testAPausedRelayIsRestingAndSaysSo() async {
        let relay = LocalRelay()
        await relay.setPaused(true)
        let health = health(relay)
        await health.check()
        XCTAssertEqual(health.state, .resting)
        XCTAssertTrue(health.isDown)
        XCTAssertEqual(health.note, "resting just now · tap to check again")
    }

    func testARelayThatCannotBeReachedIsDownAndComesBackOnTheNextCheck() async {
        let relay = LocalRelay()
        await relay.setReachable(false)
        let health = health(relay)
        await health.check()
        XCTAssertEqual(health.state, .unreachable)
        XCTAssertTrue(health.isDown)
        XCTAssertEqual(health.note, "can't be reached · tap to try again")

        await relay.setReachable(true)
        await health.check(force: true)
        XCTAssertEqual(health.state, .up)
        XCTAssertNil(health.note)
    }

    /// Coming to the front again and again does not ask the relay each time.
    func testItAsksAtMostEveryHalfMinuteUnlessThePlayerAsks() async {
        let relay = LocalRelay()
        var time = Date(timeIntervalSince1970: 1_000)
        let health = health(relay, at: { time })
        await health.check()
        await health.check()
        var asked = await relay.received["health"]
        XCTAssertEqual(asked, 1)
        time += 31
        await health.check()
        asked = await relay.received["health"]
        XCTAssertEqual(asked, 2)
        await health.check(force: true)
        asked = await relay.received["health"]
        XCTAssertEqual(asked, 3)
    }

    /// An older relay answers every ping with a plain pong: it is there.
    func testAPlainPongCountsAsUp() {
        XCTAssertEqual(OnlineHealth.reading(.pong), .up)
        XCTAssertEqual(OnlineHealth.reading(.health(open: true)), .up)
        XCTAssertEqual(OnlineHealth.reading(.health(open: false)), .resting)
        XCTAssertEqual(OnlineHealth.reading(.refused(.invalid)), .up, "it answered")
        XCTAssertEqual(OnlineHealth.reading(.refused(.paused)), .resting)
        XCTAssertEqual(OnlineHealth.reading(nil), .unreachable)
    }

    /// Test launches and the demo never ask: they must not depend on the internet.
    func testSwitchedOffItIsAlwaysUpAndAsksNobody() async {
        let relay = LocalRelay()
        await relay.setReachable(false)
        let health = OnlineHealth(dial: relay.dial, wait: 0.2, fixed: .up)
        await health.check()
        XCTAssertEqual(health.state, .up)
        let down = OnlineHealth(dial: relay.dial, wait: 0.2, fixed: .unreachable)
        await down.check(force: true)
        XCTAssertTrue(down.isDown)
    }
}
