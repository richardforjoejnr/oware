import XCTest
@testable import Oware

final class AppVersionTests: XCTestCase {
    func testAppStoreBuildsShowOnlyTheVersion() {
        XCTAssertEqual(AppVersion.label(version: "1.2.0", build: "202609271730", channel: .appStore), "Version 1.2.0 (202609271730)")
    }

    /// App Review installs run in StoreKit's sandbox, just like TestFlight, so the app cannot tell
    /// them apart. A "Beta" label there made 1.0.0 look like a pre-release (guideline 2.2), so a
    /// sandbox build shows only the version.
    func testSandboxBuildsNeverSayBeta() {
        let label = AppVersion.label(version: "1.3.0", build: "202610011200", channel: .sandbox)
        XCTAssertEqual(label, "Version 1.3.0 (202610011200)")
        XCTAssertFalse(label.contains("Beta"))
    }

    func testDevelopmentBuildsSaySo() async {
        let channel = await AppChannel.current()
        XCTAssertEqual(channel, .development, "tests run a Debug build")
    }
}
