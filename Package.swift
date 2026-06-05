// swift-tools-version:6.1

//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the SwiftServiceDiscovery project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftServiceDiscovery project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import PackageDescription

let package = Package(
    name: "swift-service-discovery",
    products: [.library(name: "ServiceDiscovery", targets: ["ServiceDiscovery"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics", from: "1.0.2"),
        .package(url: "https://github.com/apple/swift-log", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "ServiceDiscovery",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics"), .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [
                // This is required since `AnyServiceDiscovery` is otherwise not working
                // due to its usage of `AnyHashable` which is not `Sendable`
                .swiftLanguageMode(.v5)
            ]
        ),

        .testTarget(name: "ServiceDiscoveryTests", dependencies: ["ServiceDiscovery"]),
    ]
)

for target in package.targets {
    var settings = target.swiftSettings ?? []
    settings.append(.enableExperimentalFeature("StrictConcurrency=complete"))
    target.swiftSettings = settings
}
