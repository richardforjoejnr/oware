import XCTest
import OwareEngine
import OwareAI
@testable import Oware

/// Every way into a game follows the rules chosen in Settings, and the Nam-Nam lesson teaches
/// what the engine actually does.
@MainActor
final class RulesFollowSettingsTests: XCTestCase {
    private func tempSession() -> GameSession { TestSupport.session() }

    private func play(_ step: Tutorial.Step) throws -> (GameState, [MoveEvent]) {
        var s = try XCTUnwrap(step.position)
        XCTAssertEqual(s.rules.variant, .namNam, step.title)
        let notation = try XCTUnwrap(step.requiredMove).notation
        let move = try XCTUnwrap(s.legalMoves().first { $0.notation == notation }, "\(step.title): \(notation) must be legal")
        let events = try s.apply(move)
        XCTAssertEqual(s.totalSeeds, 48, step.title)
        return (s, events)
    }

    private func captures(_ e: [MoveEvent]) -> [(house: Int, by: Player)] {
        e.compactMap { if case let .capture(h, _, b) = $0 { return (h, b) } else { return nil } }
    }
    private func relayed(_ e: [MoveEvent]) -> Bool { e.contains { if case .relay = $0 { return true } else { return false } } }

    func testNamNamLessonMovesDoWhatTheLessonSays() throws {
        let steps = Tutorial.steps(for: .namNam)
        func step(_ title: String) throws -> Tutorial.Step { try XCTUnwrap(steps.first { $0.title == title }, title) }

        var (s, e) = try play(step("Sowing"))
        XCTAssertFalse(relayed(e)); XCTAssertTrue(captures(e).isEmpty); XCTAssertEqual(s.sideToMove, .north)

        (s, e) = try play(step("Roaming"))
        XCTAssertTrue(relayed(e)); XCTAssertTrue(captures(e).isEmpty)

        (s, e) = try play(step("Making four"))
        XCTAssertEqual(captures(e).map(\.house), [1]); XCTAssertEqual(captures(e).first?.by, .south)

        (s, e) = try play(step("Four on their side"))
        XCTAssertEqual(captures(e).map(\.house), [6]); XCTAssertEqual(captures(e).first?.by, .south)

        (s, e) = try play(step("Careful"))
        XCTAssertEqual(captures(e).map(\.house), [6]); XCTAssertEqual(captures(e).first?.by, .north)

        let feeding = try step("Feeding")
        XCTAssertEqual(try XCTUnwrap(feeding.position).legalMoves().map(\.notation), ["A6"], "only the feeding move is legal")
        (s, e) = try play(feeding)
        XCTAssertGreaterThan(s.houses[6...].reduce(0, +), 0)

        (s, e) = try play(step("The last four"))
        XCTAssertTrue(e.contains { if case .roundOver = $0 { return true } else { return false } })
        XCTAssertEqual(s.roundHistory.last?.southSeeds, 28)
        XCTAssertEqual(s.roundHistory.last?.southHouses, 7)
    }

    func testLessonFollowsTheChosenRules() {
        let session = tempSession()
        session.startTutorial(step: 0, variant: .namNam)
        XCTAssertEqual(session.state.rules.variant, .namNam)
        XCTAssertEqual(session.tutorialSteps.count, Tutorial.namNamSteps.count)
        session.startTutorial(step: 0, variant: .abapa)
        XCTAssertEqual(session.state.rules.variant, .abapa)
        XCTAssertEqual(session.tutorialSteps.count, Tutorial.steps.count)
    }

    func testPlayAgainAndNextOpponentKeepTheRules() {
        let session = tempSession()
        session.newGame(.journey(chapter: 0, opponent: 0), rules: .namNam)
        XCTAssertEqual(session.state.rules.variant, .namNam)
        session.newGame(session.mode)                                   // Play again
        XCTAssertEqual(session.state.rules.variant, .namNam)
        session.newGame(.journey(chapter: 0, opponent: 1))             // Next opponent
        XCTAssertEqual(session.state.rules.variant, .namNam)
        session.newGame(.passAndPlay, rules: .abapa)
        session.newGame(session.mode)
        XCTAssertEqual(session.state.rules.variant, .abapa)
    }

    func testRiddlesFollowTheChosenRules() {
        let library = PuzzleLibrary(defaults: TestSupport.defaults(), bundle: Bundle(for: GameSession.self))
        library.variant = .namNam
        XCTAssertFalse(library.puzzles.isEmpty)
        XCTAssertTrue(library.puzzles.allSatisfy { $0.state.rules.variant == .namNam && $0.id.hasPrefix("namNam-") })
        library.variant = .abapa
        XCTAssertFalse(library.puzzles.isEmpty)
        XCTAssertTrue(library.puzzles.allSatisfy { $0.state.rules.variant == .abapa })
    }

    func testNamNamJourneyStarsCountRounds() {
        var won = GameState.initial(rules: .namNam)
        won.outcome = .win(.south, .territory)
        won.roundHistory = Array(repeating: RoundResult(round: 1, southSeeds: 30, northSeeds: 18, southHouses: 7, northHouses: 5), count: 2)
        XCTAssertEqual(Journey.stars(for: won), 3)
        won.roundHistory += Array(repeating: won.roundHistory[0], count: 2)
        XCTAssertEqual(Journey.stars(for: won), 2)
        won.roundHistory += Array(repeating: won.roundHistory[0], count: 4)
        XCTAssertEqual(Journey.stars(for: won), 1)
    }
}
