import XCTest
@testable import Oware

/// The Rate button opens the App Store's review page, and is hidden until the app's id is known.
final class LinksTests: XCTestCase {
    func testAnAppStoreIDMakesTheWriteAReviewLink() {
        XCTAssertEqual(Links.writeReview(appStoreID: "1234567890")?.absoluteString,
                       "https://apps.apple.com/app/id1234567890?action=write-review")
    }

    func testNoIDMeansNoLink() {
        XCTAssertNil(Links.writeReview(appStoreID: nil))
        XCTAssertNil(Links.writeReview(appStoreID: ""))
        XCTAssertNil(Links.writeReview(appStoreID: "  "))
    }

    func testAnUnsetBuildSettingIsNotAnID() {
        XCTAssertNil(Links.writeReview(appStoreID: "$(APP_STORE_ID)"))
    }
}
