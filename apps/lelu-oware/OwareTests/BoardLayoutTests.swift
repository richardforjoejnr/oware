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

    /// Upright phones: each home row has its rail at the board's edge on its own side, and a name
    /// plaque halfway along it, both clear of every house, count and seed.
    func testPortraitRailsSitBesideTheirOwnRowsClearOfTheHouses() {
        for size in [CGSize(width: 402, height: 677), CGSize(width: 375, height: 470), CGSize(width: 440, height: 760),
                     CGSize(width: 820, height: 1000)] {
            let layout = BoardLayout(size: size)
            XCTAssertEqual(layout.orientation, .vertical)
            guard let south = layout.railRect(.south), let north = layout.railRect(.north),
                  let southPlaque = layout.plaqueRect(.south), let northPlaque = layout.plaqueRect(.north) else {
                return XCTFail("\(size): no room for the rails")
            }
            XCTAssertGreaterThan(south.minX, layout.houseCenter(0).x, "\(size): your rail is outside your row")
            XCTAssertLessThan(north.maxX, layout.houseCenter(6).x, "\(size): their rail is outside their row")
            XCTAssertGreaterThanOrEqual(south.width, 30, "\(size): rail too thin")
            XCTAssertGreaterThanOrEqual(southPlaque.width, 50, "\(size): plaque too small to read")
            for shape in [south, north, southPlaque, northPlaque] {
                XCTAssertTrue(layout.boardRect.contains(shape), "\(size): \(shape) off the board")
                for house in 0..<12 {
                    let c = layout.houseCenter(house)
                    let pit = CGRect(x: c.x - layout.pitSpriteDiameter / 2, y: c.y - layout.pitSpriteDiameter / 2,
                                     width: layout.pitSpriteDiameter, height: layout.pitSpriteDiameter)
                    XCTAssertFalse(shape.intersects(pit), "\(size): \(shape) covers house \(house)")
                    XCTAssertFalse(shape.insetBy(dx: -layout.cell * 0.1, dy: 0).contains(layout.countLabelPoint(house)),
                                   "\(size): \(shape) covers the count of house \(house)")
                }
            }
            XCTAssertTrue(south.contains(CGPoint(x: south.midX, y: southPlaque.midY)), "\(size): plaque off its rail")
        }
    }

    /// A board lying wide (phone on its side, iPad landscape) has its rows near and far, as on a
    /// real board: no rails.
    func testNoRailsWhenTheBoardLiesWide() {
        for size in [CGSize(width: 852, height: 300), CGSize(width: 1180, height: 700)] {
            let layout = BoardLayout(size: size)
            XCTAssertNil(layout.railRect(.south), "\(size)")
            XCTAssertNil(layout.plaqueRect(.north), "\(size)")
        }
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

    /// A house's name and count sit outside its carved ring, never on it, on every board size
    /// (a lesson's board is shorter, so its houses and rings are smaller). Labels are about 0.25
    /// cells wide and 0.15 cells tall.
    func testHouseLabelsClearTheRing() {
        for size in sizes + [CGSize(width: 402, height: 522), CGSize(width: 375, height: 400)] {
            let layout = BoardLayout(size: size)
            let half = CGSize(width: layout.cell * 0.13, height: layout.cell * 0.08)
            for house in 0..<12 {
                let c = layout.houseCenter(house)
                for withName in [false, true] {
                    for p in [layout.countLabelPoint(house, withName: withName), layout.nameLabelPoint(house)] {
                        // The label's nearest point to the house centre.
                        let dx = max(abs(p.x - c.x) - half.width, 0), dy = max(abs(p.y - c.y) - half.height, 0)
                        XCTAssertGreaterThan(hypot(dx, dy), layout.ringDiameter / 2, "\(size) house \(house) label at \(p) touches its ring")
                    }
                }
            }
        }
    }
}
