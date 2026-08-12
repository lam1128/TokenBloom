// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenBloom",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TokenBloom", targets: ["TokenBloom"])],
    targets: [
        .executableTarget(
            name: "TokenBloom",
            path: "Sources/TokenBloom",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "TokenBloomTests", dependencies: ["TokenBloom"], path: "Tests/TokenBloomTests")
    ]
)
