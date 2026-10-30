import XCTest
@testable import Oware

/// Nearby play can be tried before it ships: TestFlight and Xcode builds have a switch for it in
/// Settings ▸ Test features. A copy from the App Store has no such switch and ignores it.
@MainActor
final class TestFeaturesTests: XCTestCase {
    func testTheSwitchesAreOnlyInTestFlightAndXcodeBuilds() {
        XCTAssertFalse(TestFeatures.isAvailable(on: .appStore))
        XCTAssertTrue(TestFeatures.isAvailable(on: .development))
        XCTAssertTrue(TestFeatures.isAvailable(on: .testFlight))
    }

    func testAnAppStoreCopyIgnoresASwitchLeftOn() {
        XCTAssertFalse(TestFeatures.nearbyPlay(on: .appStore, switchOn: true))
        XCTAssertTrue(TestFeatures.nearbyPlay(on: .testFlight, switchOn: true))
        XCTAssertFalse(TestFeatures.nearbyPlay(on: .testFlight, switchOn: false))
    }

    func testTheTestSwitchShowsNearbyPlayWhileItsSwitchIsOff() {
        let gate = Feature.gate(defaults: TestSupport.defaults())
        XCTAssertFalse(Feature.showsNearbyPlay(gate: gate, launchOption: false, testSwitch: false))
        XCTAssertTrue(Feature.showsNearbyPlay(gate: gate, launchOption: false, testSwitch: true))
        XCTAssertTrue(Feature.showsNearbyPlay(gate: gate, launchOption: true, testSwitch: false))
    }
}
