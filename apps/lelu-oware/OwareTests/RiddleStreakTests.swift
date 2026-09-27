import XCTest
import OwareAI
@testable import Oware

/// The daily-riddle streak behind the Game Center leaderboard.
@MainActor
final class RiddleStreakTests: XCTestCase {
    private func library() -> PuzzleLibrary {
        let lib = PuzzleLibrary(defaults: UserDefaults(suiteName: UUID().uuidString)!, bundle: Bundle(for: GameSession.self))
        lib.variant = .abapa
        return lib
    }
    private func daily(_ lib: PuzzleLibrary, _ day: Int) throws -> Puzzle { try XCTUnwrap(lib.puzzleSet.daily(dayNumber: day)) }

    func testConsecutiveDaysBuildAStreak() throws {
        let lib = library()
        for day in 100...103 { lib.markSolved(try daily(lib, day), today: day) }
        XCTAssertEqual(lib.currentStreak(today: 103), 4)
    }

    func testSolvingTwiceOnOneDayCountsOnce() throws {
        let lib = library()
        lib.markSolved(try daily(lib, 100), today: 100)
        lib.markSolved(try daily(lib, 100), today: 100)
        XCTAssertEqual(lib.currentStreak(today: 100), 1)
    }

    func testAMissedDayRestartsTheStreak() throws {
        let lib = library()
        lib.markSolved(try daily(lib, 100), today: 100)
        lib.markSolved(try daily(lib, 101), today: 101)
        XCTAssertEqual(lib.currentStreak(today: 102), 2, "still alive until today is over")
        XCTAssertEqual(lib.currentStreak(today: 103), 0, "a whole day missed")
        lib.markSolved(try daily(lib, 103), today: 103)
        XCTAssertEqual(lib.currentStreak(today: 103), 1)
    }

    func testOtherRiddlesDoNotCount() throws {
        let lib = library()
        let today = try daily(lib, 100)
        let other = try XCTUnwrap(lib.puzzles.first { $0.id != today.id })
        XCTAssertFalse(lib.isDaily(other, today: 100))
        lib.markSolved(other, today: 100)
        XCTAssertEqual(lib.currentStreak(today: 100), 0)
    }
}
