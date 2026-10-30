import Foundation
import Testing
@testable import OwareEngine

/// A short code for a position, the same on every phone and every platform, so two phones can
/// check they hold the same game (before the first move and after reconnecting).
@Suite("Position fingerprints")
struct FingerprintTests {
    @Test func theSameGameGivesTheSameFingerprint() throws {
        let match = OwareMatch(rules: .namNam, starter: .north, houses: [7, 2, 9])
        #expect(try match.state().fingerprint == match.state().fingerprint)
        #expect(try OwareMatch(rules: .namNam, starter: .north, houses: [7, 2, 9]).state().fingerprint
                == match.state().fingerprint, "another phone replaying the same moves")
    }

    /// Pinned: if this changes, two versions of the app can no longer check each other's games.
    /// Bump the format (the "v1" inside) on purpose rather than by accident.
    @Test func theFingerprintOfTheOpeningIsPinned() {
        #expect(GameState.initial(rules: .abapa).fingerprint == GameState.initial(rules: .abapa).fingerprint)
        #expect(GameState.initial(rules: .abapa).fingerprint.count == 16)
        #expect(GameState.initial(rules: .abapa).fingerprint == "b6d4f2bd0d6c0d3a")
    }

    @Test func anyDifferenceChangesIt() throws {
        let base = GameState.initial(rules: .abapa)
        var changes: [GameState] = []
        var s = base; s.houses[3] += 1; s.houses[4] -= 1; changes.append(s)
        s = base; s.sideToMove = .north; changes.append(s)
        s = base; s.stores[0] = 1; s.houses[0] -= 1; changes.append(s)
        s = base; s.round = 2; changes.append(s)
        s = base; s.territory[5] = .north; changes.append(s)
        s = base; s.outcome = .win(.south, .agreement); changes.append(s)
        s = base; s.moveNumber = 1; changes.append(s)
        changes.append(GameState.initial(rules: .namNam))
        let prints = Set(changes.map(\.fingerprint) + [base.fingerprint])
        #expect(prints.count == changes.count + 1)
    }
}
