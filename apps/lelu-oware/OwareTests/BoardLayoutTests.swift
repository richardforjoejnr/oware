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
}
