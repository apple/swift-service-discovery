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

public final class FilterInstanceServiceDiscovery<BaseDiscovery: ServiceDiscovery> {
    typealias Predicate = (BaseDiscovery.Instance) throws -> Bool

    private let originalSD: BaseDiscovery
    private let predicate: Predicate

    internal init(originalSD: BaseDiscovery, predicate: @escaping Predicate) {
        self.originalSD = originalSD
        self.predicate = predicate
    }
}

extension FilterInstanceServiceDiscovery: ServiceDiscovery {
    /// Default timeout for lookup.
    public var defaultLookupTimeout: DispatchTimeInterval {
        self.originalSD.defaultLookupTimeout
    }

    public func lookup(_ service: BaseDiscovery.Service, deadline: DispatchTime?, callback: @escaping (Result<[BaseDiscovery.Instance], Error>) -> Void) {
        self.originalSD.lookup(service, deadline: deadline) { result in callback(self.transform(result)) }
    }

    public func subscribe(to service: BaseDiscovery.Service, onNext nextResultHandler: @escaping (Result<[BaseDiscovery.Instance], Error>) -> Void, onComplete completionHandler: @escaping (CompletionReason) -> Void) -> CancellationToken {
        self.originalSD.subscribe(
            to: service,
            onNext: { result in nextResultHandler(self.transform(result)) },
            onComplete: completionHandler
        )
    }

    private func transform(_ result: Result<[BaseDiscovery.Instance], Error>) -> Result<[BaseDiscovery.Instance], Error> {
        switch result {
        case .success(let instances):
            do {
                return try .success(instances.filter(self.predicate))
            } catch {
                return .failure(error)
            }
        case .failure(let error):
            return .failure(error)
        }
    }
}
