import XCTest
import OwareEngine
@testable import Oware

/// Seeds must rest inside the carved shapes: every store slot inside its bowl, clear of the count,
/// and every house slot inside its hollow — in both orientations.
final class BoardLayoutTests: XCTestCase {
    private let sizes = [CGSize(width: 402, height: 780), CGSize(width: 1024, height: 700)]

    func testStoreSeedsStayInsideTheBowlAndClearOfTheCount() {
        for size in sizes {
            let layout = BoardLayout(size: size)
            for player in Player.allCases {
                let bowl = layout.storeRect(player).insetBy(dx: layout.seedRadius * 0.5, dy: layout.seedRadius * 0.5)
                let label = layout.storeLabelPoint(player)
                for k in 0..<24 {
                    let p = layout.storeSlot(player, index: k)
                    XCTAssertTrue(bowl.contains(p), "\(size) \(player) seed \(k) at \(p) outside bowl \(bowl)")
                    XCTAssertGreaterThan(hypot(p.x - label.x, p.y - label.y), layout.seedRadius * 2.2,
                                         "\(size) \(player) seed \(k) sits on the count")
                }
            }
        }
    }

    func testHouseSeedsStayInsideTheHollow() {
        for size in sizes {
            let layout = BoardLayout(size: size)
            for house in 0..<12 {
                let c = layout.houseCenter(house)
                for k in 0..<20 {
                    let p = layout.seedSlot(in: house, index: k)
                    XCTAssertLessThan(hypot(p.x - c.x, p.y - c.y), layout.houseRadius * 0.8, "\(size) house \(house) seed \(k)")
                }
            }
        }
    }

    func testHousesDoNotOverlapEachOtherOrTheStores() {
        for size in sizes {
            let layout = BoardLayout(size: size)
            let centres = (0..<12).map { layout.houseCenter($0) }
            for i in 0..<12 {
                for j in (i + 1)..<12 {
                    let d = hypot(centres[i].x - centres[j].x, centres[i].y - centres[j].y)
                    XCTAssertGreaterThan(d, layout.pitSpriteDiameter * 1.04, "\(size) pit sprites \(i) and \(j) touch")
                }
                for player in Player.allCases {
                    let store = layout.storeRect(player).insetBy(dx: -layout.houseRadius, dy: -layout.houseRadius)
                    XCTAssertFalse(store.contains(centres[i]), "\(size) house \(i) overlaps the \(player) store")
                }
            }
        }
    }

    /// Portrait: your store is at the bottom beside "You", the opponent's at the top beside their name.
    func testPortraitStoresSitBesideTheirPlayers() {
        let layout = BoardLayout(size: CGSize(width: 440, height: 956))
        XCTAssertEqual(layout.orientation, .vertical)
        XCTAssertGreaterThan(layout.storeRect(.south).midY, layout.storeRect(.north).midY, "south (you) below north")
        for house in 0..<12 {
            let y = layout.houseCenter(house).y
            XCTAssertTrue(layout.storeRect(.north).maxY < y && y < layout.storeRect(.south).minY, "houses sit between the stores")
        }
    }

    /// Upright phones: each home row has a named strip beside it, on its own side of the board,
    /// clear of every house, count and the carved frame.
    func testPortraitStripsSitBesideTheirOwnRowsClearOfTheHouses() {
        for size in [CGSize(width: 402, height: 677), CGSize(width: 375, height: 470), CGSize(width: 440, height: 760)] {
            let layout = BoardLayout(size: size)
            XCTAssertEqual(layout.orientation, .vertical)
            guard let south = layout.railRect(.south), let north = layout.railRect(.north) else {
                return XCTFail("\(size): no room for the strips")
            }
            XCTAssertGreaterThan(south.minX, layout.houseCenter(0).x, "\(size): your strip is outside your row")
            XCTAssertLessThan(north.maxX, layout.houseCenter(6).x, "\(size): their strip is outside their row")
            XCTAssertGreaterThanOrEqual(south.width, 30, "\(size): wide enough to read")
            for strip in [south, north] {
                XCTAssertTrue(layout.boardRect.insetBy(dx: layout.cell * 0.34, dy: 0).contains(strip), "\(size): strip under the frame")
                for house in 0..<12 {
                    let c = layout.houseCenter(house)
                    let count = layout.countLabelPoint(house)
                    let pit = CGRect(x: c.x - layout.pitSpriteDiameter / 2, y: c.y - layout.pitSpriteDiameter / 2,
                                     width: layout.pitSpriteDiameter, height: layout.pitSpriteDiameter)
                    XCTAssertFalse(strip.intersects(pit), "\(size): strip covers house \(house)")
                    XCTAssertFalse(strip.insetBy(dx: -layout.cell * 0.1, dy: 0).contains(count), "\(size): strip covers count \(house)")
                }
            }
        }
    }

    /// A phone on its side has no room beside the rows: no strip rather than a cramped one.
    func testNoStripWhenTheBoardIsTooTight() {
        let layout = BoardLayout(size: CGSize(width: 852, height: 300))
        XCTAssertNil(layout.railRect(.south))
        XCTAssertNil(layout.railRect(.north))
    }

    func testStripsNameWhoOwnsEachRow() {
        let vsAI = GameMode.versusAI(difficulty: .beginner, personality: .balanced, humanPlays: .south)
        XCTAssertEqual(GameSession.sideName(.south, mode: vsAI), "You")
        XCTAssertEqual(GameSession.sideName(.north, mode: vsAI), "Computer")
        let asNorth = GameMode.versusAI(difficulty: .beginner, personality: .balanced, humanPlays: .north)
        XCTAssertEqual(GameSession.sideName(.north, mode: asNorth), "You")
        XCTAssertEqual(GameSession.sideName(.south, mode: asNorth), "Computer")
        XCTAssertEqual(GameSession.sideName(.south, mode: .passAndPlay), "Player A")
        XCTAssertEqual(GameSession.sideName(.north, mode: .passAndPlay), "Player B")
        XCTAssertEqual(GameSession.sideName(.north, mode: .tutorial(step: 0)), "Nana")
    }
}
