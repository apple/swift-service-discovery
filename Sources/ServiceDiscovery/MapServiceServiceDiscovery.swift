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

    public func lookup(_ service: ComputedService, deadline: DispatchTime? = nil) async throws -> [BaseDiscovery.Instance] {
        let derivedService = try self.transformer(service)
        return try await self.originalSD.lookup(derivedService, deadline: deadline)
    }

    public func subscribe(to service: ComputedService) throws -> BaseDiscovery.InstancesSnapshotSequence {
        let derivedService = try self.transformer(service)
        return try self.originalSD.subscribe(to: derivedService)
    }
}
