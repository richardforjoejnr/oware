import Foundation
import Observation
import StoreKit

/// The single one-time purchase: the full Journey (chapters 3–8) plus cosmetic packs.
/// Everything needed to play — AI at all levels, Pass & Play, Learn, riddles, chapters 1–2 — is free.
@MainActor
@Observable
final class StoreManager {
    static let fullJourneyID = "com.richardforjoe.oware.fulljourney"

    private(set) var product: Product?
    private(set) var hasFullJourney: Bool
    private(set) var isLoading = false
    private(set) var lastError: String?
    nonisolated(unsafe) private var updates: Task<Void, Never>?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Cached entitlement so the UI is right before StoreKit answers; verified again on launch.
        hasFullJourney = defaults.bool(forKey: "hasFullJourney") || LaunchOptions.unlockAll
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task { await refresh() }
    }

    deinit { updates?.cancel() }

    var priceText: String { product?.displayPrice ?? "…" }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            product = try await Product.products(for: [Self.fullJourneyID]).first
        } catch {
            lastError = error.localizedDescription
        }
        var owned = LaunchOptions.unlockAll
        for await result in Transaction.currentEntitlements {
            if case let .verified(transaction) = result, transaction.productID == Self.fullJourneyID, transaction.revocationDate == nil {
                owned = true
            }
        }
        setOwned(owned)
    }

    func purchase() async {
        guard let product else { await refresh(); return }
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

    func restore() async {
        lastError = nil
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refresh()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case let .verified(transaction) = result else { return }
        if transaction.productID == Self.fullJourneyID {
            setOwned(transaction.revocationDate == nil)
        }
        await transaction.finish()
    }

    private func setOwned(_ owned: Bool) {
        hasFullJourney = owned
        defaults.set(owned, forKey: "hasFullJourney")
    }
}
