import Foundation

/// Switches for trying unfinished features on TestFlight. They exist only in a build made with
/// TEST_FEATURES, which the TestFlight workflow sets when it is run by hand with "test features"
/// ticked; such builds are not tagged, so App Store Release cannot send one for review. Every
/// other build, including all App Store builds, compiles this to "off" with nothing in Settings.
enum TestFeatures {
    #if TEST_FEATURES
    static let isBuiltIn = true
    #else
    static let isBuiltIn = false
    #endif

    static let nearbyPlayKey = "testFeatures.nearbyPlay"

    /// Settings ▸ Test features ▸ Nearby play.
    static var nearbyPlay: Bool { isBuiltIn && UserDefaults.standard.bool(forKey: nearbyPlayKey) }
}
