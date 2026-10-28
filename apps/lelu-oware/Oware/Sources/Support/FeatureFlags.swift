import Foundation

/// Switches for things that are built but not shown yet, and are never sold. Features that could
/// be paid one day go in `Feature.table` instead.
enum FeatureFlags {
    /// The "News by email" links. Off until the Kit form is on the newsletter page
    /// (docs/lelu-oware/newsletter.md); a "sign-ups open soon" page reads as unfinished in App Review.
    static let newsletter = false
}

enum OnlineProduct {
    /// Non-consumable in App Store Connect (to be created when online play ships).
    static let id = "com.richardforjoe.oware.online"
    /// Last build before online play was paid; nil while nothing is paid (see FoundingPolicy).
    static let lastFreeBuild: Int? = nil
}
