// swift-tools-version: 6.0
import PackageDescription

// SupportKit — StoreKit pieces shared by every app in this repo: the tip jar (nothing is gated
// behind a tip), a one-time `Unlock` for a paid feature, and `FoundingPlayer` so people who arrived
// while something was free keep it.
let package = Package(
    name: "SupportKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SupportKit", targets: ["SupportKit"]),
    ],
    targets: [
        .target(name: "SupportKit"),
        .testTarget(name: "SupportKitTests", dependencies: ["SupportKit"]),
    ]
)
