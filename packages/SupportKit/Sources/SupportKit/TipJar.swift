import Foundation
import Observation
import StoreKit

/// The tip jar: a few consumable StoreKit products, nothing unlocked by buying them.
///
/// Create one per app with that app's product ids (smallest first), put it in the environment,
/// and show `TipJarView`. Tips are remembered only as a count, so the app can say thank you.
///
/// The jar always has something to show: the tips, a loading line, or (when the App Store does not
/// answer or returns no products) a plain message with Try again. App Review rejected a build whose
/// jar showed only "Tips are not available right now."
@MainActor
@Observable
public final class TipJar {
    /// Where the products are in loading.
    public enum LoadState: Equatable, Sendable {
        /// Not asked yet (the view shows the loading line).
        case idle
        case loading
        /// At least one tip loaded.
        case loaded
        /// The App Store gave no tips, failed or took too long; `retry()` asks again.
        case failed
    }

    /// Fetches products for ids. The App Store by default; tests and test launches pass their own.
    public typealias ProductLoader = @Sendable ([String]) async throws -> [Product]

    /// Shown when the tips could not be loaded. Plain and calm: nothing is broken for the player.
    public static let unavailableMessage = "The tips could not be reached just now. Check your internet connection and try again."
    /// Shown when a tip did not go through (not when the player cancels).
    public static let purchaseFailedMessage = "That tip did not go through. You can try again."
    /// Shown when a tip waits for approval (Ask to Buy) or for the bank.
    public static let pendingMessage = "Your tip is waiting for approval. It will go through once it is approved."

    /// Product ids in ascending price order, e.g. `["…tip.small", "…tip.medium", "…tip.large"]`.
    public let productIDs: [String]
    /// Loaded products, in the order of `productIDs`.
    public private(set) var tips: [Product] = []
    public private(set) var loadState: LoadState = .idle
    /// The product being bought, if any; the view disables the buttons meanwhile.
    public private(set) var purchasingID: String?
    /// A line about the last purchase (pending or failed); nil when there is nothing to say.
    public private(set) var purchaseMessage: String?
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

    public var isLoading: Bool { loadState == .loading }
    /// The message to show instead of the tips, when they could not be loaded.
    public var loadMessage: String? { loadState == .failed ? Self.unavailableMessage : nil }
    /// The purchase message, kept under its old name for apps that read it.
    public var lastError: String? { loadMessage ?? purchaseMessage }

    private let defaults: UserDefaults
    private let countKey: String
    private let loader: ProductLoader
    private let loadTimeout: Duration
    @ObservationIgnored private var updates: Task<Void, Never>?

    public init(productIDs: [String], defaults: UserDefaults = .standard, storageKey: String = "supportkit.tipCount",
                loadTimeout: Duration = .seconds(20), loader: ProductLoader? = nil) {
        self.productIDs = productIDs
        self.defaults = defaults
        self.countKey = storageKey
        self.tipCount = defaults.integer(forKey: storageKey)
        self.loadTimeout = loadTimeout
        self.loader = loader ?? { try await Product.products(for: $0) }
        // Also delivers, once at launch, any tip whose transaction was not finished last time.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    isolated deinit { updates?.cancel() }

    public var hasTipped: Bool { tipCount > 0 }

    /// Fetch the products. Safe to call repeatedly: the view calls it on appear; once loaded it
    /// does nothing, and overlapping calls ask the App Store once.
    public func load() async {
        guard loadState != .loading, loadState != .loaded else { return }
        loadState = .loading
        let ids = productIDs
        let products = await Self.fetch(ids, with: loader, timeout: loadTimeout)
        tips = ids.compactMap { id in products.first { $0.id == id } }
        loadState = tips.isEmpty ? .failed : .loaded
    }

    /// Ask the App Store again after a failed load (the Try again button).
    public func retry() async {
        guard loadState == .failed || loadState == .idle else { return }
        loadState = .idle
        await load()
    }

    /// The loader's products, or none if it throws or does not answer within `timeout`. Whichever
    /// comes first wins; a store call that ignores cancellation is left behind, not waited for.
    private nonisolated static func fetch(_ ids: [String], with loader: @escaping ProductLoader, timeout: Duration) async -> [Product] {
        let gate = OnceGate()
        return await withCheckedContinuation { (continuation: CheckedContinuation<[Product], Never>) in
            let work = Task {
                let products = (try? await loader(ids)) ?? []
                if gate.open() { continuation.resume(returning: products) }
            }
            Task {
                try? await Task.sleep(for: timeout)
                if gate.open() {
                    work.cancel()
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// Buy one tip. Consumables are finished immediately; the count is the only thing kept.
    /// - Parameter purchase: how to buy; `TipJarView` passes SwiftUI's `PurchaseAction`, which
    ///   shows Apple's sheet in the right window (iPad can have several). Defaults to `product.purchase()`.
    public func tip(_ product: Product,
                    purchase: (@MainActor (Product) async throws -> Product.PurchaseResult)? = nil) async {
        guard purchasingID == nil else { return }
        purchaseMessage = nil
        purchasingID = product.id
        defer { purchasingID = nil }
        do {
            let result = if let purchase { try await purchase(product) } else { try await product.purchase() }
            switch result {
            case let .success(verification):
                await handle(verification)
            case .pending:
                purchaseMessage = Self.pendingMessage
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseMessage = Self.purchaseFailedMessage
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
        purchaseMessage = nil
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

/// Lets exactly one of two racing tasks resume a continuation.
private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false

    /// True for the first caller only.
    func open() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if opened { return false }
        opened = true
        return true
    }
}
