// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LudoEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LudoEngine", targets: ["LudoEngine"]),
    ],
    targets: [
        .target(name: "LudoEngine"),
        .testTarget(name: "LudoEngineTests", dependencies: ["LudoEngine"]),
    ]
)
