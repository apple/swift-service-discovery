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

/// Provides service instances lookup..
public protocol ServiceDiscovery: Sendable {
    /// Service discovery instance type
    associatedtype Instance: Sendable
    /// Service discovery subscription type
    associatedtype Subscription: ServiceDiscoverySubscription where Subscription.Instance == Instance

    /// Performs async lookup for the given service's instances.
    ///
    /// - Returns: A listing of service discovery instances.
    /// - throws when failing to lookup instances
    func lookup() async throws -> [Instance]

    /// Subscribes to receive service discovery change notification whenever service discovery instances change.
    ///
    /// - Returns a ``ServiceDiscoverySubscription`` which produces an ``AsyncSequence`` of changes in  the service discovery instances.
    /// - throws when failing to establish subscription
    func subscribe() async throws -> Subscription
}

/// The ServiceDiscoverySubscription returns an AsyncSequence of Result type, with either the
/// instances discovered or an error if a discovery error has occurred.
/// The client should decide how to best handle errors in this case, e.g. terminate
/// the subscription or continue and handle the errors, for example by recording or
/// propagating them.
public protocol ServiceDiscoverySubscription: Sendable {
    /// Service discovery instance type
    associatedtype Instance: Sendable
    /// AsyncSequence of Service discovery instances
    associatedtype DiscoverySequence: Sendable, AsyncSequence where DiscoverySequence.Element == Result<[Instance], Error>

    /// -  Returns a ``DiscoverySequence``, which is an ``AsyncSequence`` where each of its items is a snapshot listing of service instances.
    func next() async -> DiscoverySequence
}
