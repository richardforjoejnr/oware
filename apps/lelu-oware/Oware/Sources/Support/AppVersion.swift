import Foundation
import StoreKit

/// Where this copy of the app came from: the App Store, StoreKit's sandbox or Xcode.
enum AppChannel: String, Sendable {
    case appStore = ""
    /// TestFlight *and* App Review: both run in StoreKit's sandbox and cannot be told apart, so
    /// this is never labelled "Beta" (App Review read that as a pre-release, guideline 2.2).
    case sandbox = "Sandbox"
    case development = "Development"

    /// TestFlight and App Review builds run in StoreKit's sandbox; App Store builds in production.
    static func current() async -> AppChannel {
        #if DEBUG
        return .development
        #else
        guard let result = try? await AppTransaction.shared else { return .appStore }
        return result.unsafePayloadValue.environment == .sandbox ? .sandbox : .appStore
        #endif
    }
}

/// "Version 1.2.0 (202609271730)" for Settings, with "· Development" for Xcode builds only.
/// Versions are set by the release pipeline.
enum AppVersion {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }

    static func label(version: String = version, build: String = build, channel: AppChannel) -> String {
        let base = "Version \(version) (\(build))"
        return channel == .development ? "\(base) · \(channel.rawValue)" : base
    }
}
