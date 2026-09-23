// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OwareEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OwareEngine", targets: ["OwareEngine"]),
    ],
    targets: [
        .target(name: "OwareEngine"),
        .testTarget(name: "OwareEngineTests", dependencies: ["OwareEngine"]),
    ]
)
