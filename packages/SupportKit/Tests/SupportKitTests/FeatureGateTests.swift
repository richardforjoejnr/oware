import Foundation
import Testing
@testable import SupportKit

@MainActor
struct FeatureGateTests {
    private func defaults() -> UserDefaults {
        let name = "SupportKitTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private let online = Access.unlock(productID: "online", hostPays: true, foundingIncluded: false)

    /// A gate with one feature, a fresh purchase record and a founding check that says `founding`.
    private func gate(_ access: Access, founding: Bool = false) -> (FeatureGate, Unlock?) {
        let d = defaults()
        let player = FoundingPlayer(policy: FoundingPolicy(lastFreeBuild: 10), defaults: d)
        player.record(originalBuild: founding ? "5" : "20")
        var unlocks: [String: Unlock] = [:]
        if case let .unlock(productID, _, _) = access { unlocks["f"] = Unlock(productID: productID, defaults: d) }
        return (FeatureGate(["f": access], unlocks: unlocks, founding: player), unlocks["f"])
    }

    @Test func offIsNotShownOrUsable() {
        let (gate, _) = gate(.off)
        #expect(!gate.isShown("f"))
        #expect(!gate.canUse("f"))
        #expect(!gate.canJoin("f", invitedByHostWhoCanUse: true))
    }

    @Test func aFeatureMissingFromTheTableIsOff() {
        let (gate, _) = gate(.free)
        #expect(!gate.isShown("missing"))
        #expect(!gate.canUse("missing"))
    }

    @Test func freeIsUsableByEveryone() {
        let (gate, _) = gate(.free)
        #expect(gate.isShown("f"))
        #expect(gate.canUse("f"))
        #expect(gate.canJoin("f", invitedByHostWhoCanUse: false))
    }

    @Test func unlockIsShownAndUsableOncePurchased() {
        let (gate, unlock) = gate(online)
        #expect(gate.isShown("f"), "shown so it can be bought")
        #expect(!gate.canUse("f"))
        unlock?.set(purchased: true)
        #expect(gate.canUse("f"))
        unlock?.set(purchased: false)   // refunded
        #expect(!gate.canUse("f"))
    }

    @Test func foundingPlayersOnlyWhenIncluded() {
        #expect(!gate(online, founding: true).0.canUse("f"), "founding players are not included unless switched on")
        let generous = Access.unlock(productID: "online", hostPays: true, foundingIncluded: true)
        #expect(gate(generous, founding: true).0.canUse("f"))
        #expect(!gate(generous, founding: false).0.canUse("f"))
    }

    @Test func hostPaysSoInvitedFriendsJoinFree() {
        let (gate, _) = gate(online)
        #expect(gate.canJoin("f", invitedByHostWhoCanUse: true), "invited friends play free")
        #expect(!gate.canJoin("f", invitedByHostWhoCanUse: false))
        let everyonePays = Access.unlock(productID: "online", hostPays: false, foundingIncluded: false)
        #expect(!self.gate(everyonePays).0.canJoin("f", invitedByHostWhoCanUse: true))
    }

    @Test func aPlayerWhoPaidCanJoinAnyone() {
        let (gate, unlock) = gate(online)
        unlock?.set(purchased: true)
        #expect(gate.canJoin("f", invitedByHostWhoCanUse: false))
    }

    // The rules `OnlinePolicy` had in Lelu Oware, now on `Access`.
    @Test func accessRules() {
        #expect(online.canUse(purchased: true, founding: false))
        #expect(!online.canUse(purchased: false, founding: true))
        #expect(online.canJoin(invitedByHostWhoCanUse: true, purchased: false, founding: false))
        #expect(!online.canJoin(invitedByHostWhoCanUse: false, purchased: false, founding: false))
        let generous = Access.unlock(productID: "online", hostPays: true, foundingIncluded: true)
        #expect(generous.canUse(purchased: false, founding: true))
        #expect(Access.free.canUse(purchased: false, founding: false))
        #expect(!Access.off.canUse(purchased: true, founding: true))
        #expect(!Access.off.isShown && Access.free.isShown && online.isShown)
    }
}
