import Testing
import Foundation
@testable import SupportKit

@MainActor
struct TipJarTests {
    private func defaults() -> UserDefaults {
        let name = "SupportKitTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func startsEmptyAndUnthanked() {
        let jar = TipJar(productIDs: ["a", "b"], defaults: defaults())
        #expect(jar.tips.isEmpty)
        #expect(!jar.hasTipped)
        #expect(jar.tipCount == 0)
    }

    @Test func recordingATipPersistsTheCount() {
        let d = defaults()
        let jar = TipJar(productIDs: ["a"], defaults: d)
        var reported: [String] = []
        jar.onTip = { reported.append($0) }
        jar.record(productID: "a")
        #expect(jar.tipCount == 1)
        #expect(jar.justTipped)
        #expect(jar.lastTippedProductID == "a")
        #expect(reported == ["a"])
        let again = TipJar(productIDs: ["a"], defaults: d)
        #expect(again.hasTipped)
        #expect(again.tipCount == 1)
    }

    @Test func productOrderFollowsTheIDsGiven() {
        let jar = TipJar(productIDs: ["small", "medium", "large"], defaults: defaults())
        #expect(jar.productIDs == ["small", "medium", "large"])
    }
}
