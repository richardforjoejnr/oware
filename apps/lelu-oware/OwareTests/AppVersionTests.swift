import XCTest
@testable import Oware

final class AppVersionTests: XCTestCase {
    func testAppStoreBuildsShowOnlyTheVersion() {
        XCTAssertEqual(AppVersion.label(version: "1.2.0", build: "202609271730", channel: .appStore), "Version 1.2.0 (202609271730)")
    }

    func testTestFlightBuildsSayBeta() {
        XCTAssertEqual(AppVersion.label(version: "1.3.0", build: "202610011200", channel: .testFlight), "Version 1.3.0 (202610011200) · Beta")
    }

    func testDevelopmentBuildsSaySo() async {
        let channel = await AppChannel.current()
        XCTAssertEqual(channel, .development, "tests run a Debug build")
    }
}
