import Foundation

/// Web pages the app links to (leluoware.com: built from docs/lelu-ludo, hosted on AWS by infra/site).
enum Links {
    /// App Review 5.1.1(i): the privacy policy must be reachable inside the app, not only on the store page.
    static let privacy = URL(string: "https://leluoware.com/lelu-ludo/privacy")!
    static let support = URL(string: "https://leluoware.com/lelu-ludo/support")!
    /// The App Store's write-a-review page (Lelu Ludo's App Store id, from App Store Connect).
    static let writeReview = URL(string: "https://apps.apple.com/app/id6818915279?action=write-review")!
}
