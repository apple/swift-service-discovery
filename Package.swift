// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "swift-service-discovery",
    products: [
        .library(name: "ServiceDiscovery", targets: ["ServiceDiscovery"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.2.0"),
    ],
    targets: [
        .target(name: "CServiceDiscoveryHelpers", dependencies: []),
        .target(name: "ServiceDiscoveryHelpers", dependencies: ["CServiceDiscoveryHelpers"]),

        .target(name: "ServiceDiscovery", dependencies: ["ServiceDiscoveryHelpers", "Logging"]),

        .testTarget(name: "ServiceDiscoveryHelpersTests", dependencies: ["ServiceDiscoveryHelpers"]),
        .testTarget(name: "ServiceDiscoveryTests", dependencies: ["ServiceDiscovery"]),
    ]
)
