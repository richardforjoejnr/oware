import SupportKit
import XCTest
@testable import Oware

/// Every feature behind a switch, and who may use it. Changing a price, or showing a feature,
/// means changing this test on purpose.
final class FeatureTableTests: XCTestCase {
    func testEveryFeatureAndItsAccess() {
        XCTAssertEqual(Feature.table, [
            // On for everyone (the owner's call, 2026-10-31, NEARBY_PLAY.md step 6).
            Feature.nearbyPlay: .free,
            // On for everyone (the owner's call, 2026-11-18, ONLINE_PLAY.md stage 6).
            // Later: .unlock(productID: OnlineProduct.id, hostPays: true, foundingIncluded: false).
            Feature.online: .free,
        ])
    }

    func testOnlinePlayIsSoldAsPlanned() {
        XCTAssertEqual(OnlineProduct.id, "com.richardforjoe.oware.online")
        XCTAssertNil(OnlineProduct.lastFreeBuild, "nothing is paid yet")
    }

    @MainActor
    func testTheAppGateFollowsTheTable() {
        let gate = Feature.gate(defaults: TestSupport.defaults())
        XCTAssertTrue(gate.isShown(Feature.nearbyPlay))
        XCTAssertTrue(gate.isShown(Feature.online))
        XCTAssertTrue(gate.canUse(Feature.online), "free: nothing to buy")
    }
}
