import Foundation
import UIKit

/// Web pages the app links to (leluoware.com: built from docs/lelu-oware, hosted on AWS by infra/site).
enum Links {
    /// App Review 5.1.1(i): the privacy policy must be reachable inside the app, not only on the store page.
    static let privacy = URL(string: "https://leluoware.com/lelu-oware/privacy")!
    static let support = URL(string: "https://leluoware.com/lelu-oware/support")!
    /// Newsletter sign-up lives on the website so the app never asks for an email address.
    static let newsletter = URL(string: "https://leluoware.com/lelu-oware/newsletter")!
    /// The address on the support page (docs/lelu-oware/support.md).
    static let supportEmail = "trendnestorg34@gmail.com"

    /// Feedback (Home, while tips are off): the App Store's write-a-review page, or an email when
    /// the app's id is unknown.
    @MainActor static func feedback(appStoreID: String? = Bundle.main.object(forInfoDictionaryKey: "AppStoreID") as? String) -> URL {
        writeReview(appStoreID: appStoreID) ?? feedbackEmail()
    }

    /// Feedback by email, with the version and phone already written in so a reply can help.
    @MainActor static func feedbackEmail(version: String = AppVersion.version, build: String = AppVersion.build,
                         system: String = "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
                         device: String = UIDevice.current.model) -> URL {
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = supportEmail
        parts.queryItems = [
            URLQueryItem(name: "subject", value: "Lelu Oware feedback"),
            URLQueryItem(name: "body", value: "\n\n\n—\nLelu Oware \(version) (\(build)) · \(device) · \(system)"),
        ]
        return parts.url!
    }

    /// The App Store's write-a-review page, from `APP_STORE_ID` (Info.plist key `AppStoreID`).
    /// Nil while the id is empty, which hides the Rate button.
    static var writeReview: URL? { writeReview(appStoreID: Bundle.main.object(forInfoDictionaryKey: "AppStoreID") as? String) }

    static func writeReview(appStoreID: String?) -> URL? {
        guard let id = appStoreID?.trimmingCharacters(in: .whitespaces), !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
    }
}
