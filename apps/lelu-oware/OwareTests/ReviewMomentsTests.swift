import XCTest
import OwareEngine
@testable import Oware

/// Apple's rating prompt only at a high point, once per version, two weeks apart (HIG ratings and reviews).
@MainActor
final class ReviewMomentsTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_790_000_000)

    private func moments(_ defaults: UserDefaults, version: String = "1.0.0") -> ReviewMoments {
        ReviewMoments(defaults: defaults, version: version, now: { [unowned self] in self.clock })
    }

    func testTheThirdWinIsAHighPointTheFirstTwoAreNot() {
        let review = moments(TestSupport.defaults())
        review.gameWon(); review.gameWon()
        XCTAssertFalse(review.takePending())
        review.gameWon()
        XCTAssertTrue(review.takePending())
        XCTAssertFalse(review.takePending(), "taken once")
    }

    func testOncePerVersionAndTwoWeeksApart() {
        let d = TestSupport.defaults()
        let review = moments(d)
        review.chapterCompleted()
        XCTAssertTrue(review.takePending())
        review.asked()
        review.chapterCompleted()
        XCTAssertFalse(review.takePending(), "not again in this version")

        clock = clock.addingTimeInterval(3 * 24 * 3600)
        let update = moments(d, version: "1.1.0")
        update.chapterCompleted()
        XCTAssertFalse(update.takePending(), "a new version, but only three days later")
        clock = clock.addingTimeInterval(14 * 24 * 3600)
        update.chapterCompleted()
        XCTAssertTrue(update.takePending())
    }

    func testAPromptThatNeverShowedDoesNotCount() {
        let d = TestSupport.defaults()
        let review = moments(d)
        review.chapterCompleted()
        XCTAssertTrue(review.takePending())
        // The player left the result screen before the prompt appeared: asked() was never called.
        review.chapterCompleted()
        XCTAssertTrue(review.takePending())
    }

    func testWinsAgainstTheComputerCountButPassAndPlayDoesNot() throws {
        let session = TestSupport.session()
        let events = session.events
        var state = GameState.initial(rules: .abapa)
        state.outcome = .win(.south, .reachedWinningSeeds)
        for _ in 0..<3 { events.gameFinished(mode: .passAndPlay, state: state) }
        XCTAssertEqual(events.review.wins, 0)
        for _ in 0..<3 { events.gameFinished(mode: .versusAI(difficulty: .beginner, personality: .balanced, humanPlays: .south), state: state) }
        XCTAssertEqual(events.review.wins, 3)
        XCTAssertTrue(events.review.takePending())
    }
}
