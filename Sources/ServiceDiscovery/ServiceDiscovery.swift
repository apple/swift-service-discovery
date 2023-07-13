//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2019-2023 Apple Inc. and the SwiftServiceDiscovery project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftServiceDiscovery project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// MARK: - Service discovery protocol

/// Provides service instances lookup.
///
/// ### Threading
///
/// `ServiceDiscovery` implementations **MUST be thread-safe**.
public protocol ServiceDiscovery: Sendable {
    /// Service instance type
    associatedtype Instance: Sendable

    associatedtype Subscription: AsyncSequence where Subscription.Element == [Instance]

    /// Performs async lookup for the given service's instances.
    ///
    /// -  Returns: A listing of service instances.
    func lookup() async throws -> [Instance]

    /// Subscribes to receive a service's instances whenever they change.
    ///
    /// Returns a ``ServiceDiscoveryInstancesSequence``, which is an `AsyncSequence` and each of its items is a snapshot listing of service instances.
    ///
    /// -  Returns: A ``Subscription`` async sequence.
    func subscribe() async throws -> Subscription
}
