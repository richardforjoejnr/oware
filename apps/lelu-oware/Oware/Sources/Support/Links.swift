import Foundation

/// Web pages the app links to (served by GitHub Pages from docs/lelu-oware).
enum Links {
    /// Newsletter sign-up lives on the website so the app never asks for an email address.
    static let newsletter = URL(string: "https://richardforjoejnr.github.io/oware/lelu-oware/newsletter")!

    /// The App Store's write-a-review page, from `APP_STORE_ID` (Info.plist key `AppStoreID`).
    /// Nil while the id is empty, which hides the Rate button.
    static var writeReview: URL? { writeReview(appStoreID: Bundle.main.object(forInfoDictionaryKey: "AppStoreID") as? String) }

    static func writeReview(appStoreID: String?) -> URL? {
        guard let id = appStoreID?.trimmingCharacters(in: .whitespaces), !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
    }
}
