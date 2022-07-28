//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the SwiftServiceDiscovery project authors
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

/// Generic wrapper for ``ServiceDiscovery/ServiceDiscovery`` instance.
public class ServiceDiscoveryBox<Service: Hashable, Instance: Hashable>: ServiceDiscovery {
    private let _underlying: Any

    private let _defaultLookupTimeout: () -> DispatchTimeInterval

    private let _lookup: (Service, DispatchTime?, @escaping (Result<[Instance], Error>) -> Void) -> Void

    private let _subscribe: (Service, @escaping (Result<[Instance], Error>) -> Void, @escaping (CompletionReason) -> Void) -> CancellationToken

    public var defaultLookupTimeout: DispatchTimeInterval {
        self._defaultLookupTimeout()
    }

    public init<ServiceDiscoveryImpl: ServiceDiscovery>(_ serviceDiscovery: ServiceDiscoveryImpl)
        where ServiceDiscoveryImpl.Service == Service, ServiceDiscoveryImpl.Instance == Instance {
        self._underlying = serviceDiscovery
        self._defaultLookupTimeout = { serviceDiscovery.defaultLookupTimeout }

        self._lookup = { service, deadline, callback in
            serviceDiscovery.lookup(service, deadline: deadline, callback: callback)
        }
        self._subscribe = { service, nextResultHandler, completionHandler in
            serviceDiscovery.subscribe(to: service, onNext: nextResultHandler, onComplete: completionHandler)
        }
    }

    public func lookup(_ service: Service, deadline: DispatchTime? = nil, callback: @escaping (Result<[Instance], Error>) -> Void) {
        self._lookup(service, deadline, callback)
    }

    @discardableResult
    public func subscribe(
        to service: Service,
        onNext nextResultHandler: @escaping (Result<[Instance], Error>) -> Void,
        onComplete completionHandler: @escaping (CompletionReason) -> Void = { _ in }
    ) -> CancellationToken {
        self._subscribe(service, nextResultHandler, completionHandler)
    }

    /// Unwraps the underlying ``ServiceDiscovery/ServiceDiscovery`` instance as `ServiceDiscoveryImpl` type.
    ///
    /// - Throws: `TypeErasedServiceDiscoveryError.typeMismatch` when the underlying
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

/// Type-erased wrapper for ``ServiceDiscovery/ServiceDiscovery`` instance.
public class AnyServiceDiscovery: ServiceDiscovery {
    private let _underlying: Any

    private let _defaultLookupTimeout: () -> DispatchTimeInterval

    private let _lookup: (AnyHashable, DispatchTime?, @escaping (Result<[AnyHashable], Error>) -> Void) -> Void

    private let _subscribe: (AnyHashable, @escaping (Result<[AnyHashable], Error>) -> Void, @escaping (CompletionReason) -> Void) -> CancellationToken

    public var defaultLookupTimeout: DispatchTimeInterval {
        self._defaultLookupTimeout()
    }

    public init<ServiceDiscoveryImpl: ServiceDiscovery>(_ serviceDiscovery: ServiceDiscoveryImpl) {
        self._underlying = serviceDiscovery
        self._defaultLookupTimeout = { serviceDiscovery.defaultLookupTimeout }

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
                onNext: { result in nextResultHandler(result.map { $0.map(AnyHashable.init) }) },
                onComplete: completionHandler
            )
        }
    }

    /// See ``ServiceDiscovery/lookup(_:deadline:callback:)``.
    ///
    /// - Warning: If `service` type does not match the underlying `ServiceDiscovery`'s, it would result in a failure.
    public func lookup(_ service: AnyHashable, deadline: DispatchTime? = nil, callback: @escaping (Result<[AnyHashable], Error>) -> Void) {
        self._lookup(service, deadline, callback)
    }

    /// See ``ServiceDiscovery/lookup(_:deadline:callback:)``.
    ///
    /// - Warning: If `Service` or `Instance` type does not match the underlying ``ServiceDiscovery/ServiceDiscovery``'s associated types, it would result in a failure.
    public func lookupAndUnwrap<Service, Instance>(
        _ service: Service,
        deadline: DispatchTime? = nil,
        callback: @escaping (Result<[Instance], Error>) -> Void
    ) where Service: Hashable, Instance: Hashable {
        self._lookup(AnyHashable(service), deadline) { result in
            callback(self.transform(result))
        }
    }

    /// See ``ServiceDiscovery/subscribe(to:onNext:onComplete:)``.
    ///
    /// - Warning: If `service` type does not match the underlying ``ServiceDiscovery/ServiceDiscovery``'s, it would result in a failure.
    @discardableResult
    public func subscribe(
        to service: AnyHashable,
        onNext nextResultHandler: @escaping (Result<[AnyHashable], Error>) -> Void,
        onComplete completionHandler: @escaping (CompletionReason) -> Void = { _ in }
    ) -> CancellationToken {
        self._subscribe(service, nextResultHandler, completionHandler)
    }

    /// See ``ServiceDiscovery/subscribe(to:onNext:onComplete:)``.
    ///
    /// - Warning: If `Service` or `Instance` type does not match the underlying ``ServiceDiscovery/ServiceDiscovery``'s associated types, it would result in a failure.
    @discardableResult
    public func subscribeAndUnwrap<Service, Instance>(
        to service: Service,
        onNext nextResultHandler: @escaping (Result<[Instance], Error>) -> Void,
        onComplete completionHandler: @escaping (CompletionReason) -> Void = { _ in }
    ) -> CancellationToken where Service: Hashable, Instance: Hashable {
        self._subscribe(AnyHashable(service), { result in nextResultHandler(self.transform(result)) }, completionHandler)
    }

    private func transform<Instance>(_ result: Result<[AnyHashable], Error>) -> Result<[Instance], Error> where Instance: Hashable {
        result.flatMap { anyInstances in
            var instances = [Instance]()
            for anyInstance in anyInstances {
                do {
                    let instance: Instance = try self.transform(anyInstance)
                    instances.append(instance)
                } catch {
                    return .failure(error)
                }
            }
            return .success(instances)
        }
    }

    private func transform<Instance>(_ anyInstance: AnyHashable) throws -> Instance where Instance: Hashable {
        guard let instance = anyInstance.base as? Instance else {
            throw TypeErasedServiceDiscoveryError.typeMismatch(description: "Expected instance type to be \(Instance.self), got \(type(of: anyInstance.base))")
        }
        return instance
    }

    /// Unwraps the underlying ``ServiceDiscovery/ServiceDiscovery`` instance as `ServiceDiscoveryImpl` type.
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

#if compiler(>=5.5) && canImport(_Concurrency)
public extension AnyServiceDiscovery {
    /// See ``ServiceDiscovery/lookup(_:deadline:)``.
    ///
    /// - Warning: If `Service` or `Instance` type does not match the underlying ``ServiceDiscovery/ServiceDiscovery``'s associated types, it would result in a failure.
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func lookupAndUnwrap<Service, Instance>(_ service: Service, deadline: DispatchTime? = nil) async throws -> [Instance] where Service: Hashable, Instance: Hashable {
        try await self.lookup(service, deadline: deadline).map(self.transform)
    }

    /// See ``ServiceDiscovery/subscribe(to:)``.
    ///
    /// - Warning: If `Service` or `Instance` type does not match the underlying ``ServiceDiscovery/ServiceDiscovery``'s associated types, it would result in a failure.
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func subscribeAndUnwrap<Service, Instance>(to service: Service) -> ServiceSnapshots<Instance> where Service: Hashable, Instance: Hashable {
        ServiceSnapshots(AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await snapshot in self.subscribe(to: service) {
                        continuation.yield(try snapshot.map(self.transform))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        })
    }
}
#endif

public enum TypeErasedServiceDiscoveryError: Error {
    case typeMismatch(description: String)
}
