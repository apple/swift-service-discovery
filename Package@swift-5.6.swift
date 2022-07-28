// swift-tools-version:5.6
import PackageDescription

let package = Package(
    name: "swift-service-discovery",
    products: [
        .library(name: "ServiceDiscovery", targets: ["ServiceDiscovery"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics", from: "1.0.2"),
        .package(url: "https://github.com/apple/swift-log", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
    ],
    targets: [
        .target(name: "ServiceDiscovery", dependencies: [
            .product(name: "Atomics", package: "swift-atomics"),
            .product(name: "Logging", package: "swift-log"),
        ]),

        .testTarget(name: "ServiceDiscoveryTests", dependencies: ["ServiceDiscovery"]),
    ]
)
