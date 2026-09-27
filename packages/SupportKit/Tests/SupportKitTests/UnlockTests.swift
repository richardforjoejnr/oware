import Foundation
import Testing
@testable import SupportKit

@MainActor
struct UnlockTests {
    private func defaults() -> UserDefaults {
        let name = "SupportKitTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func startsLockedAndRemembersAPurchase() {
        let d = defaults()
        let unlock = Unlock(productID: "online", defaults: d)
        #expect(!unlock.isPurchased)
        unlock.set(purchased: true)
        #expect(Unlock(productID: "online", defaults: d).isPurchased, "known at the next launch")
        unlock.set(purchased: false)   // refunded
        #expect(!Unlock(productID: "online", defaults: d).isPurchased)
    }

    @Test func purchasesAreKeptPerProduct() {
        let d = defaults()
        Unlock(productID: "online", defaults: d).set(purchased: true)
        #expect(!Unlock(productID: "chapters", defaults: d).isPurchased)
    }

    @Test func foundingPolicy() {
        #expect(FoundingPolicy().isFounding(originalBuild: "40"), "nothing paid yet: everyone is founding")
        let paywall = FoundingPolicy(lastFreeBuild: 12)
        #expect(paywall.isFounding(originalBuild: "1"))
        #expect(paywall.isFounding(originalBuild: "12"))
        #expect(!paywall.isFounding(originalBuild: "13"))
        #expect(paywall.isFounding(originalBuild: "1.0"), "sandbox and TestFlight report 1.0: be generous")
        #expect(paywall.isFounding(originalBuild: nil), "not known yet: be generous")
    }

    @Test func foundingPlayerCachesTheOriginalBuild() {
        let d = defaults()
        let player = FoundingPlayer(policy: FoundingPolicy(lastFreeBuild: 5), defaults: d)
        player.record(originalBuild: "9")
        #expect(!player.isFounding)
        #expect(FoundingPlayer(policy: FoundingPolicy(lastFreeBuild: 5), defaults: d).originalBuild == "9")
    }
}
