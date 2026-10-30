import Foundation
import Observation

/// Switches for trying unfinished features before they ship (Settings ▸ Test features). Shown in
/// TestFlight and Xcode builds; a copy from the App Store never shows them and ignores them.
@MainActor
@Observable
final class TestFeatures {
    static let shared = TestFeatures()
    static let nearbyPlayKey = "testFeatures.nearbyPlay"

    /// Where this copy came from; App Store (switches off) until it is known at launch.
    var channel: AppChannel = .appStore

    static func isAvailable(on channel: AppChannel) -> Bool { channel != .appStore }

    static func nearbyPlay(on channel: AppChannel, switchOn: Bool) -> Bool { isAvailable(on: channel) && switchOn }

    /// Settings ▸ Test features ▸ Nearby play, on this copy.
    static var nearbyPlay: Bool {
        nearbyPlay(on: shared.channel, switchOn: UserDefaults.standard.bool(forKey: nearbyPlayKey))
    }
}
