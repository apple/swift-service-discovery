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

// MARK: - Generic wrapper for `ServiceDiscovery` instance

public class ServiceDiscoveryBox<Service: Hashable, Instance: Hashable>: ServiceDiscovery {
    private let _underlying: Any

    private let _defaultLookupTimeout: () -> DispatchTimeInterval

    private let _lookup: (Service, DispatchTime?) async throws -> [Instance]

    private let _subscribe: (Service) throws -> AsyncThrowingStream<[Instance], Error>

    public var defaultLookupTimeout: DispatchTimeInterval {
        self._defaultLookupTimeout()
    }

    public init<ServiceDiscoveryImpl: ServiceDiscovery>(_ serviceDiscovery: ServiceDiscoveryImpl)
        where ServiceDiscoveryImpl.Service == Service, ServiceDiscoveryImpl.Instance == Instance {
        self._underlying = serviceDiscovery
        self._defaultLookupTimeout = { serviceDiscovery.defaultLookupTimeout }

        self._lookup = { service, deadline in
            try await serviceDiscovery.lookup(service, deadline: deadline)
        }
        self._subscribe = { service in
            AsyncThrowingStream { continuation in
                Task.detached {
                    do {
                        for try await snapshot in try serviceDiscovery.subscribe(to: service) {
                            continuation.yield(snapshot)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    public func lookup(_ service: Service, deadline: DispatchTime? = nil) async throws -> [Instance] {
        try await self._lookup(service, deadline)
    }

    public func subscribe(to service: Service) throws -> AsyncThrowingStream<[Instance], Error> {
        try self._subscribe(service)
    }

    /// Unwraps the underlying `ServiceDiscovery` instance as `ServiceDiscoveryImpl` type.
    ///
    /// - Throws: `TypeErasedServiceDiscoveryError.typeMismatch` when the underlying
    ///           `ServiceDiscovery` instance is not of type `ServiceDiscoveryImpl`.
    public func unwrapAs<ServiceDiscoveryImpl: ServiceDiscovery>(_ serviceDiscoveryType: ServiceDiscoveryImpl.Type) throws -> ServiceDiscoveryImpl {
        guard let unwrapped = self._underlying as? ServiceDiscoveryImpl else {
            throw TypeErasedServiceDiscoveryError.typeMismatch(description: "Cannot unwrap [\(type(of: self._underlying)))] as [\(ServiceDiscoveryImpl.self)]")
        }
        return unwrapped
    }
}

// MARK: - Type-erased wrapper for `ServiceDiscovery` instance

public class AnyServiceDiscovery: ServiceDiscovery {
    private let _underlying: Any

    private let _defaultLookupTimeout: () -> DispatchTimeInterval

    private let _lookup: (AnyHashable, DispatchTime?) async throws -> [AnyHashable]

    private let _subscribe: (AnyHashable) throws -> AsyncThrowingStream<[AnyHashable], Error>

    public var defaultLookupTimeout: DispatchTimeInterval {
        self._defaultLookupTimeout()
    }

    public init<ServiceDiscoveryImpl: ServiceDiscovery>(_ serviceDiscovery: ServiceDiscoveryImpl) {
        self._underlying = serviceDiscovery
        self._defaultLookupTimeout = { serviceDiscovery.defaultLookupTimeout }

        self._lookup = { anyService, deadline in
            guard let service = anyService.base as? ServiceDiscoveryImpl.Service else {
                preconditionFailure("Expected service type to be \(ServiceDiscoveryImpl.Service.self), got \(type(of: anyService.base))")
            }
            return try await serviceDiscovery.lookup(service, deadline: deadline).map(AnyHashable.init)
        }
        self._subscribe = { anyService in
            guard let service = anyService.base as? ServiceDiscoveryImpl.Service else {
                preconditionFailure("Expected service type to be \(ServiceDiscoveryImpl.Service.self), got \(type(of: anyService.base))")
            }

            return AsyncThrowingStream { continuation in
                Task.detached {
                    do {
                        for try await snapshot in try serviceDiscovery.subscribe(to: service) {
                            continuation.yield(snapshot.map(AnyHashable.init))
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    /// See `ServiceDiscovery.lookup`.
    ///
    /// - Warning: If `service` type does not match the underlying `ServiceDiscovery`'s, it would result in a failure.
    public func lookup(_ service: AnyHashable, deadline: DispatchTime? = nil) async throws -> [AnyHashable] {
        try await self._lookup(service, deadline)
    }

    /// See `lookup`.
    ///
    /// - Warning: If `Service` or `Instance` type does not match the underlying `ServiceDiscovery`'s associated types, it would result in a failure.
    public func lookupAndUnwrap<Service, Instance>(_ service: Service, deadline: DispatchTime? = nil) async throws -> [Instance] where Service: Hashable, Instance: Hashable {
        try await self._lookup(AnyHashable(service), deadline).map(self.transform)
    }

    /// See `ServiceDiscovery.subscribe`.
    ///
    /// - Warning: If `service` type does not match the underlying `ServiceDiscovery`'s, it would result in a failure.
    public func subscribe(to service: AnyHashable) throws -> AsyncThrowingStream<[AnyHashable], Error> {
        try self._subscribe(service)
    }

    /// See `subscribe`.
    ///
    /// - Warning: If `Service` or `Instance` type does not match the underlying `ServiceDiscovery`'s associated types, it would result in a failure.
    public func subscribeAndUnwrap<Service, Instance>(to service: Service) throws -> AsyncThrowingStream<[Instance], Error> where Service: Hashable, Instance: Hashable {
        AsyncThrowingStream { continuation in
            Task.detached {
                do {
                    for try await snapshot in try self._subscribe(AnyHashable(service)) {
                        continuation.yield(try snapshot.map(self.transform))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func transform<Instance>(_ anyInstance: AnyHashable) throws -> Instance where Instance: Hashable {
        guard let instance = anyInstance.base as? Instance else {
            throw TypeErasedServiceDiscoveryError.typeMismatch(description: "Expected instance type to be \(Instance.self), got \(type(of: anyInstance.base))")
        }
        return instance
    }

    /// Unwraps the underlying `ServiceDiscovery` instance as `ServiceDiscoveryImpl` type.
    ///
    /// - Throws: `TypeErasedServiceDiscoveryError.typeMismatch` when the underlying
    ///           `ServiceDiscovery` instance is not of type `ServiceDiscoveryImpl`.
    public func unwrapAs<ServiceDiscoveryImpl: ServiceDiscovery>(_ serviceDiscoveryType: ServiceDiscoveryImpl.Type) throws -> ServiceDiscoveryImpl {
        guard let unwrapped = self._underlying as? ServiceDiscoveryImpl else {
            throw TypeErasedServiceDiscoveryError.typeMismatch(description: "Cannot unwrap [\(type(of: self._underlying))] as [\(ServiceDiscoveryImpl.self)]")
        }
        return unwrapped
    }
}

public enum TypeErasedServiceDiscoveryError: Error {
    case typeMismatch(description: String)
}
