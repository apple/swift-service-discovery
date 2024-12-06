//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2020-2021 Apple Inc. and the SwiftServiceDiscovery project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftServiceDiscovery project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch

/// A service discovery implementation that maps instances to another type using a closure.
public final class MapInstanceServiceDiscovery<BaseDiscovery: ServiceDiscovery, DerivedInstance: Hashable & Sendable> {
    typealias Transformer = @Sendable (BaseDiscovery.Instance) throws -> DerivedInstance

    private let originalSD: BaseDiscovery
    private let transformer: Transformer

    internal init(originalSD: BaseDiscovery, transformer: @escaping Transformer) {
        self.originalSD = originalSD
        self.transformer = transformer
    }
}

extension MapInstanceServiceDiscovery: ServiceDiscovery {
    /// Default timeout for lookup.
    public var defaultLookupTimeout: DispatchTimeInterval { self.originalSD.defaultLookupTimeout }

    /// Performs a lookup for the given service's instances. The result will be sent to `callback`.
    ///
    /// ``defaultLookupTimeout`` will be used to compute `deadline` in case one is not specified.
    ///
    /// ### Threading
    ///
    /// `callback` may be invoked on arbitrary threads, as determined by implementation.
    ///
    /// - Parameters:
    ///   - service: The service to lookup
    ///   - deadline: Lookup is considered to have timed out if it does not complete by this time
    ///   - callback: The closure to receive lookup result
    @preconcurrency public func lookup(
        _ service: BaseDiscovery.Service,
        deadline: DispatchTime?,
        callback: @Sendable @escaping (Result<[DerivedInstance], Error>) -> Void
    ) { self.originalSD.lookup(service, deadline: deadline) { result in callback(self.transform(result)) } }

    /// Subscribes to receive a service's instances whenever they change.
    ///
    /// The service's current list of instances will be sent to `nextResultHandler` when this method is first called. Subsequently,
    /// `nextResultHandler` will only be invoked when the `service`'s instances change.
    ///
    /// ### Threading
    ///
    /// `nextResultHandler` and `completionHandler` may be invoked on arbitrary threads, as determined by implementation.
    ///
    /// - Parameters:
    ///   - service: The service to subscribe to
    ///   - nextResultHandler: The closure to receive update result
    ///   - completionHandler: The closure to invoke when the subscription completes (e.g., when the `ServiceDiscovery` instance exits, etc.),
    ///                 including cancellation requested through `CancellationToken`.
    ///
    /// -  Returns: A ``CancellationToken`` instance that can be used to cancel the subscription in the future.
    @preconcurrency public func subscribe(
        to service: BaseDiscovery.Service,
        onNext nextResultHandler: @Sendable @escaping (Result<[DerivedInstance], Error>) -> Void,
        onComplete completionHandler: @Sendable @escaping (CompletionReason) -> Void
    ) -> CancellationToken {
        self.originalSD.subscribe(
            to: service,
            onNext: { result in nextResultHandler(self.transform(result)) },
            onComplete: completionHandler
        )
    }

    private func transform(_ result: Result<[BaseDiscovery.Instance], Error>) -> Result<[DerivedInstance], Error> {
        switch result {
        case .success(let instances):
            do { return try .success(instances.map(self.transformer)) } catch { return .failure(error) }
        case .failure(let error): return .failure(error)
        }
    }
}
