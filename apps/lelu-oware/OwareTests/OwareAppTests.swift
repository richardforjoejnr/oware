import XCTest
@testable import Oware

final class OwareAppTests: XCTestCase {
    /// The tip jar lists its products smallest first; each must be a distinct id of this app.
    func testTipProductsAreDistinctAndBelongToTheApp() {
        XCTAssertEqual(Tips.productIDs.count, 3)
        XCTAssertEqual(Set(Tips.productIDs).count, Tips.productIDs.count)
        XCTAssertTrue(Tips.productIDs.allSatisfy { $0.hasPrefix("com.richardforjoe.oware.tip.") })
    }
}
