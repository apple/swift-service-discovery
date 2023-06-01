// swift-tools-version:5.7

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
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "ServiceDiscovery", targets: ["ServiceDiscovery"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics", from: "1.0.2"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
    ],
    targets: [
        .target(name: "ServiceDiscovery", dependencies: []),

        .testTarget(name: "ServiceDiscoveryTests", dependencies: [
            "ServiceDiscovery",
            .product(name: "Atomics", package: "swift-atomics"),
        ]),
    ]
)
