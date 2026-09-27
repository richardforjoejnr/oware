import XCTest
import OwareEngine
@testable import Oware

/// The banner after a Nam-Nam round says what happened to your houses, measured against the round before.
@MainActor
final class RoundMessageTests: XCTestCase {
    private let vsAI = GameMode.versusAI(difficulty: .beginner, personality: .balanced, humanPlays: .south)
    private func r(_ n: Int, _ s: Int, _ sh: Int) -> RoundResult {
        RoundResult(round: n, southSeeds: s, northSeeds: 48 - s, southHouses: sh, northHouses: 12 - sh)
    }

    func testGainingOneHouse() {
        XCTAssertEqual(GameSession.describe(r(1, 28, 7), previous: nil, in: vsAI), "Round 1: you 28, them 20 — you gain 1 house, now 7")
    }
    func testGainingTwoHouses() {
        XCTAssertEqual(GameSession.describe(r(1, 32, 8), previous: nil, in: vsAI), "Round 1: you 32, them 16 — you gain 2 houses, now 8")
    }
    func testWinningTheRoundButLosingAHouse() {
        XCTAssertEqual(GameSession.describe(r(2, 26, 7), previous: r(1, 32, 8), in: vsAI), "Round 2: you 26, them 22 — you lose 1 house, now 7")
    }
    func testKeepingHouses() {
        XCTAssertEqual(GameSession.describe(r(2, 28, 7), previous: r(1, 28, 7), in: vsAI), "Round 2: you 28, them 20 — you keep 7 houses")
    }
    func testPassAndPlay() {
        XCTAssertEqual(GameSession.describe(r(2, 20, 5), previous: r(1, 28, 7), in: .passAndPlay), "Round 2: A 20, B 28 — B takes 2 houses. A 5, B 7")
    }
}
