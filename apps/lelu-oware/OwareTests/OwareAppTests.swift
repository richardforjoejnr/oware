import XCTest
@testable import Oware

final class OwareAppTests: XCTestCase {
    /// The app hosting these tests runs quietly: nothing reaches analytics or Game Center, and
    /// no test depends on what the app did at launch.
    @MainActor
    func testTheTestHostSendsNothing() {
        XCTAssertTrue(LaunchOptions.isUnitTestHost)
        XCTAssertTrue(LaunchOptions.testMode)
        XCTAssertFalse(Analytics.shared.isEnabled, "unit tests never send analytics")
        XCTAssertFalse(GameCenter.shared.isAuthenticated, "unit tests never sign in to Game Center")
    }

    /// Maestro passes a true/false launch argument as a bare `key true`, with no dash, so the
    /// defaults never see it (nearby-demo.yaml found no Play nearby): read that form as well.
    func testASwitchIsReadInEachFormTestToolsPassIt() {
        XCTAssertTrue(LaunchOptions.isOn("--nearby-demo", defaultsKey: "nearbyDemo", in: ["app", "--nearby-demo"]))
        XCTAssertTrue(LaunchOptions.isOn("--nearby-demo", defaultsKey: "nearbyDemo", in: ["app", "nearbyDemo", "true"]))
        XCTAssertTrue(LaunchOptions.isOn("--nearby-demo", defaultsKey: "nearbyDemo", in: ["app", "-rules", "abapa", "nearbyDemo", "YES"]))
        XCTAssertFalse(LaunchOptions.isOn("--nearby-demo", defaultsKey: "nearbyDemo", in: ["app", "nearbyDemo", "false"]))
        XCTAssertFalse(LaunchOptions.isOn("--nearby-demo", defaultsKey: "nearbyDemo", in: ["app", "nearbyDemo"]))
    }

    /// The tip jar lists its products smallest first; each must be a distinct id of this app.
    func testTipProductsAreDistinctAndBelongToTheApp() {
        XCTAssertEqual(Tips.productIDs.count, 3)
        XCTAssertEqual(Set(Tips.productIDs).count, Tips.productIDs.count)
        XCTAssertTrue(Tips.productIDs.allSatisfy { $0.hasPrefix("com.richardforjoe.oware.tip.") })
    }
}
