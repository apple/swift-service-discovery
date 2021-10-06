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

    public func lookup(_ service: BaseDiscovery.Service, deadline: DispatchTime? = nil) async throws -> [BaseDiscovery.Instance] {
        try await self.originalSD.lookup(service, deadline: deadline).filter(self.predicate)
    }

    public func subscribe(to service: BaseDiscovery.Service) throws -> AsyncThrowingStream<[BaseDiscovery.Instance], Error> {
        AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    for try await snapshot in try self.originalSD.subscribe(to: service) {
                        continuation.yield(try snapshot.filter(self.predicate))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
