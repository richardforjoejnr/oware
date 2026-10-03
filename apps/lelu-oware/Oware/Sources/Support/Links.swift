import Foundation

/// Web pages the app links to (built from docs/lelu-oware, hosted on AWS by infra/site).
enum Links {
    /// App Review 5.1.1(i): the privacy policy must be reachable inside the app, not only on the store page.
    static let privacy = URL(string: "https://diqw2b8iw2b16.cloudfront.net/lelu-oware/privacy")!
    static let support = URL(string: "https://diqw2b8iw2b16.cloudfront.net/lelu-oware/support")!
    /// Newsletter sign-up lives on the website so the app never asks for an email address.
    static let newsletter = URL(string: "https://diqw2b8iw2b16.cloudfront.net/lelu-oware/newsletter")!

    /// The App Store's write-a-review page, from `APP_STORE_ID` (Info.plist key `AppStoreID`).
    /// Nil while the id is empty, which hides the Rate button.
    static var writeReview: URL? { writeReview(appStoreID: Bundle.main.object(forInfoDictionaryKey: "AppStoreID") as? String) }

    static func writeReview(appStoreID: String?) -> URL? {
        guard let id = appStoreID?.trimmingCharacters(in: .whitespaces), !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
    }
}
