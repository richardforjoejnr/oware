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

/// Feedback replaces Support me on the home screen while tips are off (the Paid Apps Agreement is
/// not active yet): the App Store's write-a-review page, or an email when the app's id is unknown.
@MainActor
final class FeedbackLinkTests: XCTestCase {
    func testTheFeedbackEmailGoesToTheSupportAddress() throws {
        let url = Links.feedbackEmail(version: "1.0.1", build: "202610301200", system: "iOS 27.1", device: "iPhone")
        XCTAssertEqual(url.scheme, "mailto")
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.path, "trendnestorg34@gmail.com")
        let query = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["subject"], "Lelu Oware feedback")
        XCTAssertTrue(query["body"]?.contains("1.0.1 (202610301200)") == true, "the version, to tell builds apart")
        XCTAssertTrue(query["body"]?.contains("iOS 27.1") == true)
        XCTAssertTrue(query["body"]?.contains("iPhone") == true)
    }

    func testFeedbackGoesToTheAppStoreReviewPage() {
        XCTAssertEqual(Links.feedback(appStoreID: "6816694006").absoluteString,
                       "https://apps.apple.com/app/id6816694006?action=write-review")
    }

    func testWithoutAnAppStoreIDFeedbackIsAnEmail() {
        XCTAssertEqual(Links.feedback(appStoreID: nil).scheme, "mailto")
        XCTAssertEqual(Links.feedback(appStoreID: "$(APP_STORE_ID)").scheme, "mailto")
    }

    func testGameCenterIsOffUntilItsLeaderboardsAreSetUp() {
        XCTAssertFalse(FeatureFlags.gameCenter, "no sign-in sheet or empty dashboard until App Store Connect has them")
    }

    func testTipsAreOffInTheShippedApp() {
        XCTAssertFalse(FeatureFlags.tips, "no In-App Purchase until the Paid Apps Agreement is active")
    }
}
