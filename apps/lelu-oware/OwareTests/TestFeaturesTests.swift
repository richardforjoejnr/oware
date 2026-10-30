import XCTest
@testable import Oware

/// Nearby play can be tried on TestFlight before it ships: a build made with the TestFlight
/// workflow's "test features" box ticked has a switch for it in Settings. Ordinary builds, and
/// so every build that can be sent to the App Store, have no such switch.
@MainActor
final class TestFeaturesTests: XCTestCase {
    func testAnOrdinaryBuildHasNoTestSwitches() {
        XCTAssertFalse(TestFeatures.isBuiltIn)
        XCTAssertFalse(TestFeatures.nearbyPlay, "the switch reads off when it is not built in")
    }

    func testTheTestSwitchShowsNearbyPlayWhileItsSwitchIsOff() {
        let gate = Feature.gate(defaults: TestSupport.defaults())
        XCTAssertFalse(Feature.showsNearbyPlay(gate: gate, launchOption: false, testSwitch: false))
        XCTAssertTrue(Feature.showsNearbyPlay(gate: gate, launchOption: false, testSwitch: true))
        XCTAssertTrue(Feature.showsNearbyPlay(gate: gate, launchOption: true, testSwitch: false))
    }
}
