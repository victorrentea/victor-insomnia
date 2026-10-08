// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VictorInsomnia",
    platforms: [.macOS(.v13)],
    targets: [
        // One executable target: the tests `@testable import` it directly.
        .executableTarget(name: "VictorInsomnia"),
        .testTarget(name: "VictorInsomniaTests", dependencies: ["VictorInsomnia"]),
    ]
)
