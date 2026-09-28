import Foundation
import Observation
import StoreKit

/// The tip jar: a few consumable StoreKit products, nothing unlocked by buying them.
///
/// Create one per app with that app's product ids (smallest first), put it in the environment,
/// and show `TipJarView`. Tips are remembered only as a count, so the app can say thank you.
@MainActor
@Observable
public final class TipJar {
    /// Product ids in ascending price order, e.g. `["…tip.small", "…tip.medium", "…tip.large"]`.
    public let productIDs: [String]
    /// Loaded products, in the order of `productIDs`.
    public private(set) var tips: [Product] = []
    public private(set) var isLoading = false
    public private(set) var lastError: String?
    /// How many tips this device has given, across launches.
    public private(set) var tipCount: Int
    /// Set for a few seconds after a tip so the view can say thank you.
    public private(set) var justTipped = false
    /// The product of the most recent tip on this device (for a thank-you or analytics).
    public private(set) var lastTippedProductID: String?
    /// Called with the product id of every tip counted, whether bought on the tip jar's screen or
    /// delivered later through `Transaction.updates` (Ask to Buy, an interrupted purchase). For
    /// the app's analytics.
    @ObservationIgnored public var onTip: (@MainActor (String) -> Void)?

    private let defaults: UserDefaults
    private let countKey: String
    @ObservationIgnored private var updates: Task<Void, Never>?

    public init(productIDs: [String], defaults: UserDefaults = .standard, storageKey: String = "supportkit.tipCount") {
        self.productIDs = productIDs
        self.defaults = defaults
        self.countKey = storageKey
        self.tipCount = defaults.integer(forKey: storageKey)
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    isolated deinit { updates?.cancel() }

    public var hasTipped: Bool { tipCount > 0 }

    /// Fetch the products. Safe to call repeatedly; the view calls it on appear.
    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let products = try await Product.products(for: productIDs)
            tips = productIDs.compactMap { id in products.first { $0.id == id } }
            lastError = tips.isEmpty ? "Tips are not available right now." : nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Buy one tip. Consumables are finished immediately; the count is the only thing kept.
    public func tip(_ product: Product) async {
        lastError = nil
        do {
            switch try await product.purchase() {
            case let .success(verification):
                await handle(verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        let transaction = result.unsafePayloadValue
        guard productIDs.contains(transaction.productID) else { return }
        // One that fails verification is not counted, but is still finished so StoreKit stops
        // offering it again at every launch.
        if case .verified = result { record(productID: transaction.productID) }
        await transaction.finish()
    }

    /// Remember a tip (also used by tests, which cannot reach StoreKit).
    func record(productID: String) {
        lastTippedProductID = productID
        tipCount += 1
        defaults.set(tipCount, forKey: countKey)
        onTip?(productID)
        justTipped = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.justTipped = false
        }
    }
}
