import Foundation
import SupportKit

/// Every feature that could be paid one day, and who may use it now. Making one paid is a change
/// to `table` (and `FeatureTableTests`), plus the product in App Store Connect.
enum Feature {
    static let nearbyPlay = "nearbyPlay"
    static let online = "online"

    static let table: [String: Access] = [
        // On for everyone (the owner's call, 2026-10-31; docs/NEARBY_PLAY.md step 6).
        nearbyPlay: .free,
        // On for everyone (the owner's call, 2026-11-18; docs/ONLINE_PLAY.md stage 6).
        // Later: .unlock(productID: OnlineProduct.id, hostPays: true, foundingIncluded: false).
        online: .free,
    ]

    /// Play nearby on Home: when its switch is on, or with `--nearby` in a Debug build.
    @MainActor
    static var showsNearbyPlay: Bool { gate().isShown(nearbyPlay) || LaunchOptions.nearbyPlay }

    /// Play online on Home: when its switch is on, or with `--online` in a Debug build.
    @MainActor
    static var showsOnlinePlay: Bool { gate().isShown(online) || LaunchOptions.onlinePlay }

    // MARK: Switches for testers

    /// Settings ▸ Play online and Settings ▸ Relay exist only in test builds: TestFlight, and builds
    /// from Xcode. An App Store build has neither: Play online is simply there, on prod. (App Review's build cannot be told from a
    /// TestFlight one, `AppChannel.sandbox`, so App Review sees them too.)
    static func offersTesterSwitches(in channel: AppChannel) -> Bool { channel != .appStore }

    /// The relay stage a build uses. An App Store build is always on prod, whatever was chosen
    /// when the same phone had a TestFlight build. A test build uses the stage chosen in Settings,
    /// and until one is chosen its own: prod for TestFlight, dev from Xcode.
    static func relayStage(in channel: AppChannel, chosen: RelayStage?) -> RelayStage {
        guard offersTesterSwitches(in: channel) else { return .prod }
        return chosen ?? (channel == .development ? .dev : .prod)
    }

    /// Play online on Home. A released app: whenever the feature is on. A test build: its switch
    /// decides (`switchedOn`; nil until the tester has touched it, which follows the feature).
    static func showsOnlinePlay(testerSwitches: Bool, switchedOn: Bool?, featureOn: Bool) -> Bool {
        testerSwitches ? (switchedOn ?? featureOn) : featureOn
    }

    /// The app's gate, with a purchase record for every feature that is sold.
    @MainActor
    static func gate(defaults: UserDefaults = .standard) -> FeatureGate {
        var unlocks: [String: Unlock] = [:]
        for (feature, access) in table {
            if case let .unlock(productID, _, _) = access {
                unlocks[feature] = Unlock(productID: productID, defaults: defaults)
            }
        }
        let founding = FoundingPlayer(policy: FoundingPolicy(lastFreeBuild: OnlineProduct.lastFreeBuild), defaults: defaults)
        return FeatureGate(table, unlocks: unlocks, founding: founding)
    }
}
