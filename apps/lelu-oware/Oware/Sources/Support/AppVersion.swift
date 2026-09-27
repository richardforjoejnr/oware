import Foundation
import StoreKit

/// Where this copy of the app came from: the App Store, TestFlight (a beta) or Xcode.
enum AppChannel: String, Sendable {
    case appStore = ""
    case testFlight = "Beta"
    case development = "Development"

    /// TestFlight builds run in StoreKit's sandbox; App Store builds in production.
    static func current() async -> AppChannel {
        #if DEBUG
        return .development
        #else
        guard let result = try? await AppTransaction.shared else { return .appStore }
        return result.unsafePayloadValue.environment == .sandbox ? .testFlight : .appStore
        #endif
    }
}

/// "Version 1.2.0 (202609271730) · Beta" for Settings. Versions are set by the release pipeline.
enum AppVersion {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }

    static func label(version: String = version, build: String = build, channel: AppChannel) -> String {
        let base = "Version \(version) (\(build))"
        return channel == .appStore ? base : "\(base) · \(channel.rawValue)"
    }
}
