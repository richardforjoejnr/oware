import XCTest
@testable import Oware

/// Recent players: the last five people played online, kept on this phone only, so one of them
/// can be asked for another game without a new link (docs/ONLINE_PLAY.md §6 and §12).
@MainActor
final class RecentPlayersTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private func id(_ n: Int) -> String { String(repeating: String(n, radix: 16), count: 32) }

    private func list(_ defaults: UserDefaults = TestSupport.defaults()) -> RecentPlayers {
        RecentPlayers(defaults: defaults, now: { [unowned self] in self.clock })
    }

    func testTheLastPlayedIsFirst() {
        let recent = list()
        recent.played(with: id(1), name: "Kwame")
        clock += 60
        recent.played(with: id(2), name: "Ama")
        XCTAssertEqual(recent.players.map(\.name), ["Ama", "Kwame"])
    }

    func testPlayingSomeoneAgainMovesThemUpAndKeepsOneRowWithTheirNewName() {
        let recent = list()
        recent.played(with: id(1), name: "Kwame")
        recent.played(with: id(2), name: "Ama")
        clock += 60
        recent.played(with: id(1), name: "Kwame A.")
        XCTAssertEqual(recent.players.map(\.name), ["Kwame A.", "Ama"])
        XCTAssertEqual(recent.players.first?.lastPlayed, clock)
    }

    func testOnlyTheLatestFiveAreKept() {
        let recent = list()
        for n in 1...7 {
            clock += 1
            recent.played(with: id(n), name: "Player \(n)")
        }
        XCTAssertEqual(recent.players.map(\.name), ["Player 7", "Player 6", "Player 5", "Player 4", "Player 3"])
    }

    func testTheListIsThereTheNextTimeTheAppOpens() {
        let defaults = TestSupport.defaults()
        list(defaults).played(with: id(1), name: "Kofi")
        XCTAssertEqual(list(defaults).players.map(\.name), ["Kofi"])
    }

    func testAPlayerCanBeRemoved() {
        let defaults = TestSupport.defaults()
        let recent = list(defaults)
        recent.played(with: id(1), name: "Kofi")
        recent.played(with: id(2), name: "Yaa")
        recent.remove(id(1))
        XCTAssertEqual(recent.players.map(\.name), ["Yaa"])
        XCTAssertEqual(list(defaults).players.map(\.name), ["Yaa"])
        XCTAssertFalse(recent.isBlocked(id(1)), "removing is not blocking")
    }

    func testABlockedPlayerLeavesTheListAndDoesNotComeBack() {
        let defaults = TestSupport.defaults()
        let recent = list(defaults)
        recent.played(with: id(1), name: "Kofi")
        recent.block(id(1))
        XCTAssertTrue(recent.players.isEmpty)
        XCTAssertTrue(recent.isBlocked(id(1)))
        recent.played(with: id(1), name: "Kofi")
        XCTAssertTrue(recent.players.isEmpty, "a later game with them does not list them again")
        XCTAssertEqual(list(defaults).blocked, [RecentPlayers.Blocked(id: id(1), name: "Kofi")], "and the block is kept")
        recent.unblock(id(1))
        XCTAssertFalse(recent.isBlocked(id(1)))
    }

    func testSomethingThatIsNotAPlayerNumberIsNotListed() {
        let recent = list()
        recent.played(with: "", name: "Nobody")
        recent.played(with: "not-an-id", name: "Nobody")
        recent.played(with: id(1).uppercased() + "0", name: "Nobody")
        XCTAssertTrue(recent.players.isEmpty)
    }

    func testANameIsTrimmedAndABlankOneIsShownAsAFriend() {
        let recent = list()
        recent.played(with: id(1), name: "  Kofi \n")
        recent.played(with: id(2), name: "   ")
        XCTAssertEqual(recent.players.map(\.name), ["A friend", "Kofi"])
    }

    func testMyOwnNumberIsNeverListed() {
        let recent = list()
        recent.me = id(9)
        recent.played(with: id(9), name: "Me")
        XCTAssertTrue(recent.players.isEmpty)
    }
}
