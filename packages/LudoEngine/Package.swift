// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LudoEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LudoEngine", targets: ["LudoEngine"]),
        .library(name: "LudoAI", targets: ["LudoAI"]),
    ],
    targets: [
        .target(name: "LudoEngine"),
        .target(name: "LudoAI", dependencies: ["LudoEngine"]),
        .testTarget(name: "LudoEngineTests", dependencies: ["LudoEngine"]),
        .testTarget(name: "LudoAITests", dependencies: ["LudoEngine", "LudoAI"]),
    ]
)
