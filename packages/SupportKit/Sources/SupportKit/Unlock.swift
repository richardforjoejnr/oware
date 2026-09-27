import Foundation
import Observation
import StoreKit

/// A one-time purchase (non-consumable) that unlocks a feature, such as online play.
///
/// The purchase is read from StoreKit's current entitlements, so it follows the Apple ID across
/// devices and survives reinstalling; the last known answer is cached so the app knows at launch.
@MainActor
@Observable
public final class Unlock {
    public let productID: String
    public private(set) var product: Product?
    public private(set) var isPurchased: Bool
    public private(set) var isWorking = false
    public private(set) var lastError: String?

    private let defaults: UserDefaults
    private let cacheKey: String
    @ObservationIgnored private var updates: Task<Void, Never>?

    public init(productID: String, defaults: UserDefaults = .standard) {
        self.productID = productID
        self.defaults = defaults
        self.cacheKey = "supportkit.unlock.\(productID)"
        self.isPurchased = defaults.bool(forKey: cacheKey)
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    isolated deinit { updates?.cancel() }

    /// Load the product and check what this Apple ID already owns.
    public func load() async {
        do {
            product = try await Product.products(for: [productID]).first
        } catch {
            lastError = error.localizedDescription
        }
        await refresh()
    }

    /// Re-read ownership from StoreKit (covers refunds and Family Sharing changes).
    public func refresh() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case let .verified(t) = result, t.productID == productID, t.revocationDate == nil { owned = true }
        }
        set(purchased: owned)
    }

    public func purchase() async {
        guard let product, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        do {
            if case let .success(verification) = try await product.purchase() {
                await handle(verification)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// "Restore purchases": asks the App Store to sync, then re-reads ownership.
    public func restore() async {
        isWorking = true
        defer { isWorking = false }
        do { try await AppStore.sync() } catch { lastError = error.localizedDescription }
        await refresh()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case let .verified(transaction) = result, transaction.productID == productID else { return }
        set(purchased: transaction.revocationDate == nil)
        await transaction.finish()
    }

    /// Records ownership (also used by tests, which cannot reach StoreKit).
    func set(purchased: Bool) {
        isPurchased = purchased
        defaults.set(purchased, forKey: cacheKey)
    }
}
