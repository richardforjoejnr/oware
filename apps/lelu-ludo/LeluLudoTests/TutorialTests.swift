import LudoEngine
import XCTest
@testable import LeluLudo

/// Learn the game: every lesson can be done with its dice, a wrong move asks to try again, and the
/// player's own game survives the tutorial.
@MainActor
final class TutorialTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func session() -> LudoSession {
        let s = LudoSession(store: GameStore(directory: directory), dice: ScriptedDice([2]))
        s.pacing = .instant
        return s
    }

    /// Each lesson's first roll, then the move that does what it asks (if any), reaches its goal.
    func testEveryLessonCanBeDone() async {
        for (index, lesson) in Lesson.all.enumerated() {
            let s = session()
            s.startTutorial(at: index)
            await s.roll()
            if s.tutorial?.outcome != .done {
                let goalMove = s.state.legalMoves().first { move in
                    var copy = s.state
                    return ((try? copy.apply(move)) ?? []).contains(where: lesson.goal)
                }
                XCTAssertNotNil(goalMove, "lesson \(index + 1), \(lesson.title): no move reaches the goal")
                if let goalMove { await s.play(goalMove) }
            }
            XCTAssertEqual(s.tutorial?.outcome, .done, "lesson \(index + 1), \(lesson.title)")
            XCTAssertFalse(s.canRoll, "a finished lesson waits for Next")
        }
    }

    func testAWrongMoveAsksToTryAgainAndRetryStartsOver() async {
        let s = session()
        s.startTutorial(at: Lesson.Chapter.ghanaRules.start)   // the back kick
        await s.roll()
        let forward = s.state.legalMoves().first { $0.kind == .forward }
        XCTAssertNotNil(forward)
        if let forward { await s.play(forward) }
        XCTAssertEqual(s.tutorial?.outcome, .tryAgain)
        s.retryLesson()
        XCTAssertEqual(s.tutorial?.outcome, .playing)
        XCTAssertTrue(s.canRoll)
        XCTAssertEqual(s.state.tokens(of: .red).first, Lesson.all[s.tutorial!.index].red.first)
    }

    func testNextWalksThroughEveryLessonThenStops() {
        let s = session()
        s.startTutorial()
        var seen = 1
        while s.nextLesson() { seen += 1 }
        XCTAssertEqual(seen, Lesson.all.count)
        XCTAssertTrue(s.tutorial?.isLast == true)
    }

    func testTheTutorialLeavesTheSavedGameAlone() async {
        let s = session()
        s.newGame(.versusComputer(opponents: 1, level: .novice, rules: .ghanaClassic))
        await s.roll()
        let saved = GameStore(directory: directory).load()
        XCTAssertNotNil(saved)
        s.startTutorial()
        await s.roll()
        XCTAssertEqual(GameStore(directory: directory).load(), saved, "nothing saved during a lesson")
        s.endTutorial()
        XCTAssertNil(s.tutorial)
        XCTAssertEqual(s.state, saved?.state)
        XCTAssertTrue(s.hasGame)
    }
}
