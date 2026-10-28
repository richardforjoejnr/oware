import Foundation
import Observation

/// Who may use a feature. Every feature goes through one of these, so making a free feature paid
/// later is a change to the app's table, not to its screens.
public enum Access: Sendable, Equatable {
    /// Built, but not shown.
    case off
    case free
    /// A one-time purchase. With `hostPays`, a player who has it can invite anyone, and invited
    /// friends play that match free. With `foundingIncluded`, founding players have it too.
    case unlock(productID: String, hostPays: Bool, foundingIncluded: Bool)

    public var isShown: Bool { self != .off }

    public func canUse(purchased: Bool, founding: Bool) -> Bool {
        switch self {
        case .off: false
        case .free: true
        case let .unlock(_, _, foundingIncluded): purchased || (foundingIncluded && founding)
        }
    }

    public func canJoin(invitedByHostWhoCanUse invited: Bool, purchased: Bool, founding: Bool) -> Bool {
        if canUse(purchased: purchased, founding: founding) { return true }
        if case let .unlock(_, hostPays, _) = self { return hostPays && invited }
        return false
    }
}

/// The app's switchboard: its table of features, the purchases that unlock them and the founding
/// check. Screens only ask `isShown`, `canUse` and `canJoin`.
@MainActor
@Observable
public final class FeatureGate {
    public let table: [String: Access]
    public let unlocks: [String: Unlock]
    public let founding: FoundingPlayer

    /// `unlocks` is keyed by feature, for the features whose access is `.unlock`.
    public init(_ table: [String: Access], unlocks: [String: Unlock], founding: FoundingPlayer) {
        self.table = table
        self.unlocks = unlocks
        self.founding = founding
    }

    private func access(_ feature: String) -> Access { table[feature] ?? .off }
    private func purchased(_ feature: String) -> Bool { unlocks[feature]?.isPurchased ?? false }

    /// Off (or missing from the table) → false.
    public func isShown(_ feature: String) -> Bool { access(feature).isShown }

    /// Free, purchased, or included for founding players.
    public func canUse(_ feature: String) -> Bool {
        access(feature).canUse(purchased: purchased(feature), founding: founding.isFounding)
    }

    public func canJoin(_ feature: String, invitedByHostWhoCanUse invited: Bool) -> Bool {
        access(feature).canJoin(invitedByHostWhoCanUse: invited, purchased: purchased(feature), founding: founding.isFounding)
    }

    /// Loads the products and what this Apple ID owns, and checks the original install.
    public func load() async {
        for unlock in unlocks.values { await unlock.load() }
        await founding.check()
    }
}
