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

/// A service discovery implementation that maps services using a closure.
public final class MapServiceServiceDiscovery<BaseDiscovery: ServiceDiscovery, ComputedService: Hashable> {
    typealias Transformer = (ComputedService) throws -> BaseDiscovery.Service

    private let originalSD: BaseDiscovery
    private let transformer: Transformer

    internal init(originalSD: BaseDiscovery, transformer: @escaping Transformer) {
        self.originalSD = originalSD
        self.transformer = transformer
    }
}

extension MapServiceServiceDiscovery: ServiceDiscovery {
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
    public func lookup(
        _ service: ComputedService,
        deadline: DispatchTime?,
        callback: @escaping (Result<[BaseDiscovery.Instance], Error>) -> Void
    ) {
        let derivedService: BaseDiscovery.Service

        do { derivedService = try self.transformer(service) } catch {
            callback(.failure(error))
            return
        }

        self.originalSD.lookup(derivedService, deadline: deadline, callback: callback)
    }

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
    public func subscribe(
        to service: ComputedService,
        onNext nextResultHandler: @escaping (Result<[BaseDiscovery.Instance], Error>) -> Void,
        onComplete completionHandler: @escaping (CompletionReason) -> Void
    ) -> CancellationToken {
        let derivedService: BaseDiscovery.Service

        do { derivedService = try self.transformer(service) } catch {
            // Ok, we couldn't transform the service. We want to throw an error into `nextResultHandler` and then immediately cancel.
            let cancellationToken = CancellationToken(isCancelled: true, completionHandler: completionHandler)
            nextResultHandler(.failure(error))
            completionHandler(.failedToMapService)
            return cancellationToken
        }

        return self.originalSD.subscribe(to: derivedService, onNext: nextResultHandler, onComplete: completionHandler)
    }
}
