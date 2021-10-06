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
    /// Default timeout for lookup.
    public var defaultLookupTimeout: DispatchTimeInterval {
        self.originalSD.defaultLookupTimeout
    }

    public func lookup(_ service: BaseDiscovery.Service, deadline: DispatchTime? = nil) async throws -> [DerivedInstance] {
        try await self.originalSD.lookup(service, deadline: deadline).map(self.transformer)
    }

    public func subscribe(to service: BaseDiscovery.Service) throws -> AsyncThrowingStream<[DerivedInstance], Error> {
        AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    for try await snapshot in try self.originalSD.subscribe(to: service) {
                        continuation.yield(try snapshot.map(self.transformer))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
