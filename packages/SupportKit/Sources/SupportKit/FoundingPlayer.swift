import Foundation
import Observation
import StoreKit

/// Which builds count as "founding": everyone who first installed up to and including
/// `lastFreeBuild` keeps whatever was free when they arrived, even if it is paid later.
///
/// iOS reports the build number (CFBundleVersion) of the first install, so keep build numbers
/// plain increasing integers and note the last build before any paywall.
public struct FoundingPolicy: Sendable, Equatable {
    /// nil while nothing is paid: everybody is a founding player.
    public var lastFreeBuild: Int?

    public init(lastFreeBuild: Int? = nil) { self.lastFreeBuild = lastFreeBuild }

    /// `originalBuild` is what StoreKit says the player first installed. Anything unreadable (the
    /// sandbox and TestFlight report "1.0") is treated generously.
    public func isFounding(originalBuild: String?) -> Bool {
        guard let lastFreeBuild else { return true }
        guard let text = originalBuild, let build = Int(text) else { return true }
        return build <= lastFreeBuild
    }
}

/// Reads the original install from StoreKit 2's `AppTransaction` once and caches it.
@MainActor
@Observable
public final class FoundingPlayer {
    public let policy: FoundingPolicy
    public private(set) var originalBuild: String?
    private let defaults: UserDefaults
    private static let key = "supportkit.originalBuild"

    public init(policy: FoundingPolicy, defaults: UserDefaults = .standard) {
        self.policy = policy
        self.defaults = defaults
        self.originalBuild = defaults.string(forKey: Self.key)
    }

    public var isFounding: Bool { policy.isFounding(originalBuild: originalBuild) }

    public func check() async {
        guard originalBuild == nil else { return }
        guard let result = try? await AppTransaction.shared, case let .verified(transaction) = result else { return }
        record(originalBuild: transaction.originalAppVersion)
    }

    func record(originalBuild: String) {
        self.originalBuild = originalBuild
        defaults.set(originalBuild, forKey: Self.key)
    }
}
