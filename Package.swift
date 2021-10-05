// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "swift-service-discovery",
    products: [
        .library(name: "ServiceDiscovery", targets: ["ServiceDiscovery"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics", from: "1.0.2"),
        .package(url: "https://github.com/apple/swift-log", from: "1.2.0"),
    ],
    targets: [
        .target(name: "ServiceDiscovery", dependencies: [
            "Atomics",
            "Logging",
        ]),

        .testTarget(name: "ServiceDiscoveryTests", dependencies: ["ServiceDiscovery"]),
    ]
)
