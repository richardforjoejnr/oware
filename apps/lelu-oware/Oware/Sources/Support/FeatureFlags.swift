import Foundation

/// Switches for things that are built but not shown yet, and are never sold. Features that could
/// be paid one day go in `Feature.table` instead.
enum FeatureFlags {
    /// The "News by email" links. Off until the Kit form is on the newsletter page
    /// (docs/lelu-oware/newsletter.md); a "sign-ups open soon" page reads as unfinished in App Review.
    static let newsletter = false
    /// The tip jar (Support me). Off until the Paid Apps Agreement is active in App Store Connect and
    /// the three tips are submitted with a build: App Review rejected 1.0.0 because the tips could not
    /// load. While off, nothing in the app can be bought and Home shows Feedback instead. Set to true
    /// to bring Support me back on Home and in Settings.
    static let tips = false
    /// Game Center: sign-in at launch, leaderboards, achievements and the Settings row. Off until
    /// the 3 leaderboards and 6 achievements exist in App Store Connect (docs/SERVICES.md section 3);
    /// until then nothing is signed in, so scores and achievements are not sent.
    static let gameCenter = false
}

enum OnlineProduct {
    /// Non-consumable in App Store Connect (to be created when online play ships).
    static let id = "com.richardforjoe.oware.online"
    /// Last build before online play was paid; nil while nothing is paid (see FoundingPolicy).
    static let lastFreeBuild: Int? = nil
}
