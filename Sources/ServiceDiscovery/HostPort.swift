//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2019-2020 Apple Inc. and the SwiftServiceDiscovery project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftServiceDiscovery project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// Represents a service instance with host and port.
public struct HostPort: Hashable, CustomStringConvertible, Sendable {
    /// The hostname.
    public let host: String

    /// The port number.
    public let port: Int

    /// Create a new `HostPort`.
    /// - Parameters:
    ///   - host: The hostname.
    ///   - port: The port number.
    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    // swift-format-ignore: AllPublicDeclarationsHaveDocumentation
    public var description: String { "\(self.host):\(self.port)" }
}
