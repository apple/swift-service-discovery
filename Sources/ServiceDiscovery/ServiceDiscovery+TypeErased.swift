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

// MARK: - Generic wrapper for `ServiceDiscovery` instance

public class ServiceDiscoveryBox<Service: Hashable, Instance: Hashable>: ServiceDiscovery {
    private let _underlying: Any

    private let _defaultLookupTimeout: () -> DispatchTimeInterval

    private let _instancesToExclude: () -> Set<Instance>?

    private let _lookup: (Service, DispatchTime?, @escaping (Result<[Instance], Error>) -> Void) -> Void

    private let _subscribe: (Service, @escaping (Result<[Instance], Error>) -> Void, @escaping (CompletionReason) -> Void) -> CancellationToken

    public var defaultLookupTimeout: DispatchTimeInterval {
        self._defaultLookupTimeout()
    }

    public var instancesToExclude: Set<Instance>? {
        self._instancesToExclude()
    }

    public init<ServiceDiscoveryImpl: ServiceDiscovery>(_ serviceDiscovery: ServiceDiscoveryImpl)
        where ServiceDiscoveryImpl.Service == Service, ServiceDiscoveryImpl.Instance == Instance {
        self._underlying = serviceDiscovery
        self._defaultLookupTimeout = { serviceDiscovery.defaultLookupTimeout }
        self._instancesToExclude = { serviceDiscovery.instancesToExclude }

        self._lookup = { service, deadline, callback in
            serviceDiscovery.lookup(service, deadline: deadline, callback: callback)
        }
        self._subscribe = { service, nextResultHandler, completionHandler in
            serviceDiscovery.subscribe(to: service, nextResultHandler: nextResultHandler, completionHandler: completionHandler)
        }
    }

    public func lookup(_ service: Service, deadline: DispatchTime? = nil, callback: @escaping (Result<[Instance], Error>) -> Void) {
        self._lookup(service, deadline, callback)
    }

    @discardableResult
    public func subscribe(
        to service: Service,
        nextResultHandler: @escaping (Result<[Instance], Error>) -> Void,
        completionHandler: @escaping (CompletionReason) -> Void = { _ in }
    ) -> CancellationToken {
        self._subscribe(service, nextResultHandler, completionHandler)
    }

    /// Unwraps the underlying `ServiceDiscovery` instance as `ServiceDiscoveryImpl` type.
    ///
    /// - Throws: ` TypeErasedServiceDiscoveryError.typeMismatch` when the underlying
    ///           `ServiceDiscovery` instance is not of type `ServiceDiscoveryImpl`.
    @discardableResult
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

    private let _instancesToExclude: () -> Set<AnyHashable>?

    private let _lookup: (AnyHashable, DispatchTime?, @escaping (Result<[AnyHashable], Error>) -> Void) -> Void

    private let _subscribe: (AnyHashable, @escaping (Result<[AnyHashable], Error>) -> Void, @escaping (CompletionReason) -> Void) -> CancellationToken

    public var defaultLookupTimeout: DispatchTimeInterval {
        self._defaultLookupTimeout()
    }

    public var instancesToExclude: Set<AnyHashable>? {
        self._instancesToExclude()
    }

    public init<ServiceDiscoveryImpl: ServiceDiscovery>(_ serviceDiscovery: ServiceDiscoveryImpl) {
        self._underlying = serviceDiscovery
        self._defaultLookupTimeout = { serviceDiscovery.defaultLookupTimeout }
        self._instancesToExclude = { serviceDiscovery.instancesToExclude }

        self._lookup = { anyService, deadline, callback in
            guard let service = anyService.base as? ServiceDiscoveryImpl.Service else {
                preconditionFailure("Expected service type to be \(ServiceDiscoveryImpl.Service.self), got \(type(of: anyService.base))")
            }
            serviceDiscovery.lookup(service, deadline: deadline) { result in
                callback(result.map { $0.map(AnyHashable.init) })
            }
        }
        self._subscribe = { anyService, nextResultHandler, completionHandler in
            guard let service = anyService.base as? ServiceDiscoveryImpl.Service else {
                preconditionFailure("Expected service type to be \(ServiceDiscoveryImpl.Service.self), got \(type(of: anyService.base))")
            }
            return serviceDiscovery.subscribe(
                to: service,
                nextResultHandler: { result in nextResultHandler(result.map { $0.map(AnyHashable.init) }) },
                completionHandler: completionHandler
            )
        }
    }

    /// See `ServiceDiscovery.lookup`.
    ///
    /// - Warning: If `service` type does not match the underlying `ServiceDiscovery`'s, it would result in a failure.
    public func lookup(_ service: AnyHashable, deadline: DispatchTime? = nil, callback: @escaping (Result<[AnyHashable], Error>) -> Void) {
        self._lookup(service, deadline, callback)
    }

    /// See `lookup`.
    ///
    /// - Warning: If `Service` or `Instance` type does not match the underlying `ServiceDiscovery`'s associated types, it would result in a failure.
    public func lookupAndUnwrap<Service, Instance>(
        _ service: Service,
        deadline: DispatchTime? = nil,
        callback: @escaping (Result<[Instance], Error>) -> Void
    ) where Service: Hashable, Instance: Hashable {
        self._lookup(AnyHashable(service), deadline) { result in
            callback(self.transform(result))
        }
    }

    /// See `ServiceDiscovery.subscribe`.
    ///
    /// - Warning: If `service` type does not match the underlying `ServiceDiscovery`'s, it would result in a failure.
    @discardableResult
    public func subscribe(
        to service: AnyHashable,
        nextResultHandler: @escaping (Result<[AnyHashable], Error>) -> Void,
        completionHandler: @escaping (CompletionReason) -> Void = { _ in }
    ) -> CancellationToken {
        self._subscribe(service, nextResultHandler, completionHandler)
    }

    /// See `subscribe`.
    ///
    /// - Warning: If `Service` or `Instance` type does not match the underlying `ServiceDiscovery`'s associated types, it would result in a failure.
    @discardableResult
    public func subscribeAndUnwrap<Service, Instance>(
        to service: Service,
        nextResultHandler: @escaping (Result<[Instance], Error>) -> Void,
        completionHandler: @escaping (CompletionReason) -> Void = { _ in }
    ) -> CancellationToken where Service: Hashable, Instance: Hashable {
        self._subscribe(AnyHashable(service), { result in nextResultHandler(self.transform(result)) }, completionHandler)
    }

    private func transform<Instance>(_ result: Result<[AnyHashable], Error>) -> Result<[Instance], Error> where Instance: Hashable {
        result.flatMap { anyInstances in
            var instances = [Instance]()
            for anyInstance in anyInstances {
                guard let instance = anyInstance.base as? Instance else {
                    return .failure(TypeErasedServiceDiscoveryError.typeMismatch(description: "Expected instance type to be \(Instance.self), got \(type(of: anyInstance.base))"))
                }
                instances.append(instance)
            }
            return .success(instances)
        }
    }

    /// Unwraps the underlying `ServiceDiscovery` instance as `ServiceDiscoveryImpl` type.
    ///
    /// - Throws: ` TypeErasedServiceDiscoveryError.typeMismatch` when the underlying
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
