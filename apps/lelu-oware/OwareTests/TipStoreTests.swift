import StoreKit
import StoreKitTest
import SupportKit
import XCTest
@testable import Oware

/// The in-app purchases the app really uses. App Review (30 Oct 2026) rejected 1.0.0 because the
/// tips did not load and because products had not been submitted: the app must ask only for the
/// products that are submitted with it (the three tips), and they must load and complete.
@MainActor
final class TipStoreTests: XCTestCase {
    private static let storeFile = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Oware/Resources/Tips.storekit")

    func testTheAppAsksOnlyForTheThreeTips() {
        XCTAssertEqual(Tips.productIDs, ["com.richardforjoe.oware.tip.small",
                                         "com.richardforjoe.oware.tip.medium",
                                         "com.richardforjoe.oware.tip.large"])
        XCTAssertFalse(Tips.productIDs.contains(OnlineProduct.id), "online play is not in this version")
    }

    /// The local store holds exactly what the app asks for, so nothing unshipped (such as "Play
    /// online") can be tried in a build or mistaken for something to submit.
    func testTheLocalStoreHoldsOnlyTheTips() throws {
        let data = try Data(contentsOf: Self.storeFile)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try XCTUnwrap(json["products"] as? [[String: Any]])
        let ids = products.compactMap { $0["productID"] as? String }
        XCTAssertEqual(Set(ids), Set(Tips.productIDs))
        XCTAssertEqual(ids.count, Tips.productIDs.count)
        XCTAssertTrue(products.allSatisfy { $0["type"] as? String == "Consumable" }, "tips unlock nothing")
    }

    func testOnlinePlayIsSwitchedOff() {
        XCTAssertFalse(FeatureFlags.onlinePlay)
    }

    private func storeSession() throws -> SKTestSession {
        let session = try SKTestSession(contentsOf: Self.storeFile)
        session.disableDialogs = true
        session.failTransactionsEnabled = false
        session.clearTransactions()
        return session
    }

    func testTheTipsLoadInOrder() async throws {
        let session = try storeSession()
        defer { _ = session }
        let jar = TipJar(productIDs: Tips.productIDs, defaults: TestSupport.defaults(), storageKey: "test.\(UUID())")
        await jar.load()
        XCTAssertEqual(jar.loadState, .loaded)
        XCTAssertEqual(jar.tips.map(\.id), Tips.productIDs)
        XCTAssertNil(jar.loadMessage)
    }

    /// A tip bought outside the sheet (Ask to Buy approved later, an interrupted purchase, or one
    /// left unfinished last launch) reaches the jar, is counted once and its transaction is
    /// finished, so StoreKit does not offer it again at the next launch. (A purchase from the sheet
    /// needs an on-screen window, so `tip(_:)` itself is covered by SupportMeUITests.)
    func testATipFromTheStoreIsCountedAndFinished() async throws {
        let session = try storeSession()
        let jar = TipJar(productIDs: Tips.productIDs, defaults: TestSupport.defaults(), storageKey: "test.\(UUID())")
        try await session.buyProduct(identifier: Tips.productIDs[1])
        for _ in 0..<50 where jar.tipCount == 0 { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertEqual(jar.tipCount, 1)
        XCTAssertEqual(jar.lastTippedProductID, Tips.productIDs[1])
        var unfinished = 0
        for await result in Transaction.unfinished where Tips.productIDs.contains(result.unsafePayloadValue.productID) {
            unfinished += 1
        }
        XCTAssertEqual(unfinished, 0, "every tip transaction is finished")
    }

    /// A purchase that fails says so plainly and leaves the jar usable.
    func testAFailedTipSaysSoPlainly() async throws {
        let session = try storeSession()
        let jar = TipJar(productIDs: Tips.productIDs, defaults: TestSupport.defaults(), storageKey: "test.\(UUID())")
        await jar.load()
        let small = try XCTUnwrap(jar.tips.first)
        // The test store's settings outlive the session on this simulator, so switch failures off
        // again or later purchases (other tests, the UI tests) fail too.
        session.failTransactionsEnabled = true
        defer { session.failTransactionsEnabled = false }
        await jar.tip(small)
        XCTAssertEqual(jar.tipCount, 0)
        XCTAssertEqual(jar.purchaseMessage, TipJar.purchaseFailedMessage)
        XCTAssertNil(jar.purchasingID)
    }
}
