// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "codex-afm-bridge",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "codex-afm-bridge", targets: ["CodexAFMBridge"])
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "CodexAFMBridge",
            dependencies: [
                .product(name: "Hummingbird", package: "hummingbird")
            ],
            path: "Sources/CodexAFMBridge"
        ),
        .testTarget(
            name: "CodexAFMBridgeTests",
            dependencies: [
                "CodexAFMBridge",
                .product(name: "HummingbirdTesting", package: "hummingbird")
            ],
            path: "Tests/CodexAFMBridgeTests"
        )
    ]
)
