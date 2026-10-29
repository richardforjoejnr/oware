import Foundation
import SupportKit

/// Every feature that could be paid one day, and who may use it now. Making one paid is a change
/// to `table` (and `FeatureTableTests`), plus the product in App Store Connect.
enum Feature {
    static let nearbyPlay = "nearbyPlay"
    static let online = "online"

    static let table: [String: Access] = [
        // Hidden while it is built; `.free` when nearby play ships (docs/NEARBY_PLAY.md step 6).
        nearbyPlay: .off,
        // Later: .unlock(productID: OnlineProduct.id, hostPays: true, foundingIncluded: false).
        online: .off,
    ]

    /// Play nearby on Home and Try nearby play in Settings: when its switch is on, or with
    /// `--nearby` in a Debug build (trying it on two phones before it ships).
    @MainActor
    static var showsNearbyPlay: Bool { gate().isShown(nearbyPlay) || LaunchOptions.nearbyPlay }

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
