import SupportKit
import XCTest
@testable import Oware

/// Every feature behind a switch, and who may use it. Changing a price, or showing a feature,
/// means changing this test on purpose.
final class FeatureTableTests: XCTestCase {
    func testEveryFeatureAndItsAccess() {
        XCTAssertEqual(Feature.table, [
            // Off for now (the owner's call, 2026-11-11).
            Feature.nearbyPlay: .off,
            // Later: .unlock(productID: OnlineProduct.id, hostPays: true, foundingIncluded: false).
            Feature.online: .off,
        ])
    }

    func testOnlinePlayIsSoldAsPlanned() {
        XCTAssertEqual(OnlineProduct.id, "com.richardforjoe.oware.online")
        XCTAssertNil(OnlineProduct.lastFreeBuild, "nothing is paid yet")
    }

    @MainActor
    func testTheAppGateFollowsTheTable() {
        let gate = Feature.gate(defaults: TestSupport.defaults())
        XCTAssertFalse(gate.isShown(Feature.nearbyPlay))
        XCTAssertFalse(gate.isShown(Feature.online))
    }
}
