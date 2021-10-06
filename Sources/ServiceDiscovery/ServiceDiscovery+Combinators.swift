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

// MARK: - Map and filter

public extension ServiceDiscovery {
    /// Creates a new `ServiceDiscovery` implementation based on this one, transforming the instances according to
    /// the derived function.
    ///
    /// It is not necessarily safe to block in this closure. This closure should not block for safety.
    func mapInstance<DerivedInstance: Hashable>(_ transformer: @escaping (Instance) throws -> DerivedInstance) -> MapInstanceServiceDiscovery<Self, DerivedInstance> {
        MapInstanceServiceDiscovery(originalSD: self, transformer: transformer)
    }

    /// Creates a new `ServiceDiscovery` implementation based on this one, transforming the services according to
    /// the derived function.
    ///
    /// It is not necessarily safe to block in this closure. This closure should not block for safety.
    func mapService<ComputedService: Hashable>(serviceType: ComputedService.Type = ComputedService.self,
                                               _ transformer: @escaping (ComputedService) throws -> Service) -> MapServiceServiceDiscovery<Self, ComputedService>
    {
        MapServiceServiceDiscovery(originalSD: self, transformer: transformer)
    }

    /// Creates a new `ServiceDiscovery` implementation based on this one, filtering instances with the given predicate.
    ///
    /// It is not necessarily safe to block in this closure. This closure should not block for safety.
    func filterInstance(_ predicate: @escaping (Instance) throws -> Bool) -> FilterInstanceServiceDiscovery<Self> {
        FilterInstanceServiceDiscovery(originalSD: self, predicate: predicate)
    }
}
