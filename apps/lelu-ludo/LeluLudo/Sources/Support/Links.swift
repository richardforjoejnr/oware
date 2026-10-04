import Foundation

/// Web pages the app links to (leluoware.com: built from docs/lelu-ludo, hosted on AWS by infra/site).
enum Links {
    /// App Review 5.1.1(i): the privacy policy must be reachable inside the app, not only on the store page.
    static let privacy = URL(string: "https://leluoware.com/lelu-ludo/privacy")!
    static let support = URL(string: "https://leluoware.com/lelu-ludo/support")!
}
