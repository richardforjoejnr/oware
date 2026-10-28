// swift-tools-version: 6.0
import PackageDescription

// MatchKit: how phones play one game together, for every app in this repo (docs/MULTIPLAYER.md).
// `MatchKit` is pure Swift (Room, Envelope, Framer, LoopbackTransport) and is tested on Linux.
// `MatchKitNearby` finds and connects phones with Network framework; it is empty where Network
// is missing, so the Linux job still builds the whole package.
let package = Package(
    name: "MatchKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MatchKit", targets: ["MatchKit"]),
        .library(name: "MatchKitNearby", targets: ["MatchKitNearby"]),
    ],
    targets: [
        .target(name: "MatchKit"),
        .target(name: "MatchKitNearby", dependencies: ["MatchKit"]),
        .testTarget(name: "MatchKitTests", dependencies: ["MatchKit"]),
        .testTarget(name: "MatchKitNearbyTests", dependencies: ["MatchKit", "MatchKitNearby"]),
    ]
)
