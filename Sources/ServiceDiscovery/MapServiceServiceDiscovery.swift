//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2020 Apple Inc. and the SwiftServiceDiscovery project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftServiceDiscovery project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
import Dispatch
import ServiceDiscoveryHelpers

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
    public var defaultLookupTimeout: DispatchTimeInterval {
        self.originalSD.defaultLookupTimeout
    }

    public func lookup(_ service: ComputedService, deadline: DispatchTime?, callback: @escaping (Result<[BaseDiscovery.Instance], Error>) -> Void) {
        let derivedService: BaseDiscovery.Service

        do {
            derivedService = try self.transformer(service)
        } catch {
            callback(.failure(error))
            return
        }

        self.originalSD.lookup(derivedService, deadline: deadline, callback: callback)
    }

    public func subscribe(to service: ComputedService, onNext nextResultHandler: @escaping (Result<[BaseDiscovery.Instance], Error>) -> Void, onComplete completionHandler: @escaping (CompletionReason) -> Void) -> CancellationToken {
        let derivedService: BaseDiscovery.Service

        do {
            derivedService = try self.transformer(service)
        } catch {
            // Ok, we couldn't transform the service. We want to throw an error into `nextResultHandler` and then immediately cancel.
            let cancellationToken = CancellationToken(isCancelled: true, completionHandler: completionHandler)
            nextResultHandler(.failure(error))
            completionHandler(.failedToMapService)
            return cancellationToken
        }

        return self.originalSD.subscribe(
            to: derivedService,
            onNext: nextResultHandler,
            onComplete: completionHandler
        )
    }
}
