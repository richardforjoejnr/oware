import MatchKit
import OwareEngine
import XCTest
@testable import Oware

/// The host's rules for starting a game on two phones (NEARBY_PLAY_REDESIGN.md §2, "Ready"): no
/// move until both phones have said they hold the same opening position.
final class ReadyHandshakeTests: XCTestCase {
    private let rules = OwareRoomRules()

    private func opening(_ ruleSet: RuleSet = .abapa, starter: Player = .south) -> OwareTable {
        OwareTable(match: OwareMatch(rules: ruleSet, starter: starter))
    }

    private func fingerprint(_ table: OwareTable) throws -> String { try table.match.state().fingerprint }

    func testNobodyMovesUntilBothAreReady() throws {
        var table = opening()
        XCTAssertFalse(table.isStarted)
        XCTAssertThrowsError(try rules.applying(.game(.play(house: 2)), from: 0, to: table))

        table = try rules.applying(.ready(stateHash: fingerprint(table)), from: 0, to: table)
        XCTAssertEqual(table.ready, [.south])
        XCTAssertThrowsError(try rules.applying(.game(.play(house: 2)), from: 0, to: table), "the other phone is not ready")

        table = try rules.applying(.ready(stateHash: fingerprint(table)), from: 1, to: table)
        XCTAssertTrue(table.isStarted)
        table = try rules.applying(.game(.play(house: 2)), from: 0, to: table)
        XCTAssertEqual(table.match.houses, [2])
    }

    /// A phone whose engine replays the opening differently (another version of the game) cannot
    /// start: both are told rather than playing two different games.
    func testADifferentOpeningIsCaughtNotPlayed() throws {
        var table = opening(.namNam)
        table = try rules.applying(.ready(stateHash: fingerprint(table)), from: 0, to: table)
        table = try rules.applying(.ready(stateHash: GameState.initial(rules: .abapa).fingerprint), from: 1, to: table)
        XCTAssertTrue(table.isOutOfStep)
        XCTAssertFalse(table.isStarted)
        XCTAssertThrowsError(try rules.applying(.game(.play(house: 2)), from: 0, to: table))
    }

    /// Every snapshot says what the position should be, so a phone can check its own replay.
    func testTheHostStampsEachPositionWithItsFingerprint() throws {
        var table = OwareTable.opening(OwareMatch(rules: .abapa))
        XCTAssertEqual(table.stateHash, try fingerprint(table))
        for seat in 0...1 { table = try rules.applying(.ready(stateHash: fingerprint(table)), from: seat, to: table) }
        table = try rules.applying(.game(.play(house: 3)), from: 0, to: table)
        XCTAssertEqual(table.stateHash, try fingerprint(table))
    }

    /// Both asked for the rematch, so both are there: the new game starts without asking again.
    func testARematchStartsAtOnce() throws {
        var table = opening()
        for seat in 0...1 { table = try rules.applying(.ready(stateHash: fingerprint(table)), from: seat, to: table) }
        table = try rules.applying(.game(.resign), from: 1, to: table)
        table = try rules.applying(.game(.rematch), from: 0, to: table)
        table = try rules.applying(.game(.rematch), from: 1, to: table)
        XCTAssertEqual(table.match.game, 2)
        XCTAssertTrue(table.isStarted)
        XCTAssertEqual(table.stateHash, try fingerprint(table))
    }

    /// Readiness only grows: a late snapshot without it never replaces one with it.
    func testASnapshotWithMoreReadyReplacesOneWithLess() throws {
        let before = opening()
        var after = before
        after.ready = [.south]
        XCTAssertTrue(rules.shouldReplace(before, with: after))
        XCTAssertFalse(rules.shouldReplace(after, with: before))
    }
}
