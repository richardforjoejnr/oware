// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OwareEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OwareEngine", targets: ["OwareEngine"]),
        .library(name: "OwareAI", targets: ["OwareAI"]),
        .executable(name: "oware", targets: ["OwareCLI"]),
    ],
    targets: [
        .target(name: "OwareEngine"),
        .target(name: "OwareAI", dependencies: ["OwareEngine"]),
        .executableTarget(name: "OwareCLI", dependencies: ["OwareEngine", "OwareAI"]),
        .testTarget(name: "OwareEngineTests", dependencies: ["OwareEngine"]),
        .testTarget(name: "OwareAITests", dependencies: ["OwareEngine", "OwareAI"]),
    ]
)
