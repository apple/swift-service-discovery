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

public final class MapInstanceServiceDiscovery<BaseDiscovery: ServiceDiscovery, DerivedInstance: Hashable> {
    typealias Transformer = (BaseDiscovery.Instance) throws -> DerivedInstance

    private let originalSD: BaseDiscovery
    private let transformer: Transformer

    internal init(originalSD: BaseDiscovery, transformer: @escaping Transformer) {
        self.originalSD = originalSD
        self.transformer = transformer
    }
}

extension MapInstanceServiceDiscovery: ServiceDiscovery {
    // This is derived from the base implementation and the transformer.
    public var instancesToExclude: Set<DerivedInstance>? {
        // We have to crash if the transformer throws here, as we cannot error.
        self.originalSD.instancesToExclude.map { try! Set($0.map(self.transformer)) }
    }

    /// Default timeout for lookup.
    public var defaultLookupTimeout: DispatchTimeInterval {
        self.originalSD.defaultLookupTimeout
    }

    public func lookup(_ service: BaseDiscovery.Service, deadline: DispatchTime?, callback: @escaping (Result<[DerivedInstance], Error>) -> Void) {
        self.originalSD.lookup(service, deadline: deadline) { result in callback(self.transform(result)) }
    }

    public func subscribe(to service: BaseDiscovery.Service, onNext nextResultHandler: @escaping (Result<[DerivedInstance], Error>) -> Void, onComplete completionHandler: @escaping (CompletionReason) -> Void) -> CancellationToken {
        self.originalSD.subscribe(
            to: service,
            onNext: { result in nextResultHandler(self.transform(result)) },
            onComplete: completionHandler
        )
    }

    private func transform(_ result: Result<[BaseDiscovery.Instance], Error>) -> Result<[DerivedInstance], Error> {
        switch result {
        case .success(let instances):
            do {
                return try .success(instances.map(self.transformer))
            } catch {
                return .failure(error)
            }
        case .failure(let error):
            return .failure(error)
        }
    }
}
