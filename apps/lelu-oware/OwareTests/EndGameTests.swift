import XCTest
import OwareAI
import OwareEngine
@testable import Oware

/// Resigning and agreeing to stop, from the in-game flag button.
@MainActor
final class EndGameTests: XCTestCase {
    private func session() -> GameSession {
        GameSession(store: GameStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)))
    }
    private let vsAI = GameMode.versusAI(difficulty: .beginner, personality: .balanced, humanPlays: .south)

    func testResigningAgainstTheComputerGivesItTheGame() {
        let s = session()
        s.newGame(vsAI, rules: .namNam)
        XCTAssertTrue(s.canEndGame)
        s.resign()
        XCTAssertEqual(s.state.outcome, .win(.north, .agreement))
        XCTAssertFalse(s.canEndGame)
    }

    func testEitherPlayerCanResignInPassAndPlay() {
        let s = session()
        s.newGame(.passAndPlay, rules: .abapa)
        s.resign(.north)
        XCTAssertEqual(s.state.outcome, .win(.south, .agreement))
    }

    func testStoppingInAbapaEndsTheGameOnTheScores() {
        let s = session()
        s.newGame(.passAndPlay, rules: .abapa)
        s.agreeToStop()
        XCTAssertEqual(s.state.outcome?.reason, .agreement)
        XCTAssertEqual(s.state.totalSeeds, 48)
        XCTAssertTrue(s.state.houses.allSatisfy { $0 == 0 }, "each side kept its own seeds")
    }

    func testStoppingInNamNamEndsOnlyTheRound() {
        let s = session()
        s.newGame(.passAndPlay, rules: .namNam)
        s.agreeToStop()
        XCTAssertNil(s.state.outcome, "the game goes on")
        XCTAssertEqual(s.state.round, 2)
        XCTAssertNotNil(s.roundMessage)
    }

    func testLessonsAndRiddlesCannotBeEnded() {
        let s = session()
        s.startTutorial(step: 1, variant: .abapa)
        XCTAssertFalse(s.canEndGame)
    }
}
