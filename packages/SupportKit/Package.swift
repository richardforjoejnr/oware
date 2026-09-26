// swift-tools-version: 6.0
import PackageDescription

// SupportKit — a tip jar shared by every app in this repo. Nothing is gated behind a tip: the
// apps stay fully free; this only lets people who enjoy them say thank you through StoreKit.
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
