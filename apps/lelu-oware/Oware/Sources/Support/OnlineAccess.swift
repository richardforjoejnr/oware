import Foundation
import Observation
import SupportKit

/// Switches for features that are built but not shown yet.
enum FeatureFlags {
    /// Online play (paid, "the host pays"). Off until matchmaking and its screens ship.
    static let onlinePlay = false
}

/// Who may start and join online matches. The plan: a one-time "Play online" purchase; a player
/// who has it can invite anyone, and invited friends play that match free. Founding players
/// (installed before online existed) can be given it too by flipping `foundingPlayersIncluded`.
struct OnlinePolicy: Equatable {
    var hostPays = true
    var foundingPlayersIncluded = false

    func canHost(purchased: Bool, founding: Bool) -> Bool {
        purchased || (foundingPlayersIncluded && founding)
    }

    func canJoin(invitedByPlayerWhoCanHost invited: Bool, purchased: Bool, founding: Bool) -> Bool {
        canHost(purchased: purchased, founding: founding) || (hostPays && invited)
    }
}

enum OnlineProduct {
    /// Non-consumable in App Store Connect (to be created when online play ships).
    static let id = "com.richardforjoe.oware.online"
    /// Last build before online play was paid; nil while nothing is paid (see FoundingPolicy).
    static let lastFreeBuild: Int? = nil
}

/// Ties the purchase and the founding check to the policy. Created only when the feature is on.
@MainActor
@Observable
final class OnlineAccess {
    let unlock: Unlock
    let founding: FoundingPlayer
    var policy: OnlinePolicy

    init(unlock: Unlock = Unlock(productID: OnlineProduct.id),
         founding: FoundingPlayer = FoundingPlayer(policy: FoundingPolicy(lastFreeBuild: OnlineProduct.lastFreeBuild)),
         policy: OnlinePolicy = OnlinePolicy()) {
        self.unlock = unlock
        self.founding = founding
        self.policy = policy
    }

    var isAvailable: Bool { FeatureFlags.onlinePlay }
    var canHost: Bool { policy.canHost(purchased: unlock.isPurchased, founding: founding.isFounding) }
    func canJoin(invitedByPlayerWhoCanHost invited: Bool) -> Bool {
        policy.canJoin(invitedByPlayerWhoCanHost: invited, purchased: unlock.isPurchased, founding: founding.isFounding)
    }

    func load() async {
        await unlock.load()
        await founding.check()
    }
}
