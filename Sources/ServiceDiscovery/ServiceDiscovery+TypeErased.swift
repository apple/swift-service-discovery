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
@preconcurrency
public class ServiceDiscoveryBox<Service: Hashable & Sendable, Instance: Hashable & Sendable>: ServiceDiscovery {
    private let _underlying: any Sendable

    private let _defaultLookupTimeout: @Sendable () -> DispatchTimeInterval

    private let _lookup:
        @Sendable (Service, DispatchTime?, @Sendable @escaping (Result<[Instance], Error>) -> Void) -> Void

    private let _subscribe:
        @Sendable (
            Service, @Sendable @escaping (Result<[Instance], Error>) -> Void,
            @Sendable @escaping (CompletionReason) -> Void
        ) -> CancellationToken

    public var defaultLookupTimeout: DispatchTimeInterval { self._defaultLookupTimeout() }

    @preconcurrency public init<ServiceDiscoveryImpl: ServiceDiscovery>(_ serviceDiscovery: ServiceDiscoveryImpl)
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

    @preconcurrency public func lookup(
        _ service: Service,
        deadline: DispatchTime? = nil,
        callback: @Sendable @escaping (Result<[Instance], Error>) -> Void
    ) { self._lookup(service, deadline, callback) }

    @preconcurrency @discardableResult public func subscribe(
        to service: Service,
        onNext nextResultHandler: @Sendable @escaping (Result<[Instance], Error>) -> Void,
        onComplete completionHandler: @Sendable @escaping (CompletionReason) -> Void = { _ in }
    ) -> CancellationToken { self._subscribe(service, nextResultHandler, completionHandler) }

    /// Unwraps the underlying ``ServiceDiscovery/ServiceDiscovery`` instance as `ServiceDiscoveryImpl` type.
    ///
    /// - Throws: `TypeErasedServiceDiscoveryError.typeMismatch` when the underlying
    ///           `ServiceDiscovery` instance is not of type `ServiceDiscoveryImpl`.
    @discardableResult public func unwrapAs<ServiceDiscoveryImpl: ServiceDiscovery>(
        _ serviceDiscoveryType: ServiceDiscoveryImpl.Type
    ) throws -> ServiceDiscoveryImpl {
        guard let unwrapped = self._underlying as? ServiceDiscoveryImpl else {
            throw TypeErasedServiceDiscoveryError.typeMismatch(
                description: "Cannot unwrap [\(type(of: self._underlying)))] as [\(ServiceDiscoveryImpl.self)]"
            )
        }
        return unwrapped
    }
}

// MARK: - Type-erased wrapper for `ServiceDiscovery` instance

/// Type-erased wrapper for ``ServiceDiscovery/ServiceDiscovery`` instance.
public final class AnyServiceDiscovery: ServiceDiscovery {
    public typealias Service = AnyHashable
    public typealias Instance = AnyHashable
    private let _underlying: any ServiceDiscovery

    private let _defaultLookupTimeout: @Sendable () -> DispatchTimeInterval

    private let _lookup:
        @Sendable (
            any Hashable & Sendable, DispatchTime?,
            @Sendable @escaping (Result<[any Hashable & Sendable], Error>) -> Void
        ) -> Void

    private let _subscribe:
        @Sendable (
            any Hashable & Sendable, @Sendable @escaping (Result<[any Hashable & Sendable], Error>) -> Void,
            @Sendable @escaping (CompletionReason) -> Void
        ) -> CancellationToken

    public var defaultLookupTimeout: DispatchTimeInterval { self._defaultLookupTimeout() }

    public init<ServiceDiscoveryImpl: ServiceDiscovery>(_ serviceDiscovery: ServiceDiscoveryImpl) {
        self._underlying = serviceDiscovery
        self._defaultLookupTimeout = { serviceDiscovery.defaultLookupTimeout }

        self._lookup = { anyService, deadline, callback in
            guard let service = anyService as? ServiceDiscoveryImpl.Service else {
                preconditionFailure(
                    "Expected service type to be \(ServiceDiscoveryImpl.Service.self), got \(type(of: anyService))"
                )
            }
            serviceDiscovery.lookup(service, deadline: deadline) { result in callback(result.map { $0 }) }
        }
        self._subscribe = { anyService, nextResultHandler, completionHandler in
            guard let service = anyService as? ServiceDiscoveryImpl.Service else {
                preconditionFailure(
                    "Expected service type to be \(ServiceDiscoveryImpl.Service.self), got \(type(of: anyService))"
                )
            }
            return serviceDiscovery.subscribe(
                to: service,
                onNext: { result in nextResultHandler(result.map { $0 }) },
                onComplete: completionHandler
            )
        }
    }

    /// See ``ServiceDiscovery/lookup(_:deadline:callback:)``.
    ///
    /// - Warning: If `service` type does not match the underlying `ServiceDiscovery`'s, it would result in a failure.
    public func lookup(
        _ service: any Hashable & Sendable,
        deadline: DispatchTime? = nil,
        callback: @Sendable @escaping (Result<[any Hashable & Sendable], Error>) -> Void
    ) { self._lookup(service, deadline, callback) }

    /// See ``ServiceDiscovery/lookup(_:deadline:callback:)``.
    ///
    /// - Warning: If `service` type does not match the underlying `ServiceDiscovery`'s, it would result in a failure.
    @preconcurrency
    @available(*, deprecated, message: "Use the lookup variant with an (any Hashable & Sendable) service instead")
    public func lookup(
        _ service: AnyHashable,
        deadline: DispatchTime? = nil,
        callback: @Sendable @escaping (Result<[AnyHashable], Error>) -> Void
    ) {
        guard service.base is (any Hashable) else {
            callback(
                .failure(
                    TypeErasedServiceDiscoveryError.typeMismatch(
                        description: "Expected service type to be Hashable, but \(type(of: service)) isn't"
                    )
                )
            )
            return
        }
        // Force casting here again as we can't dynamically cast just to get the Sendable conformance.
        // This is safe, as the hashability is already verified above.
        self._lookup(service.base as! (any Hashable & Sendable), deadline) { result in
            callback(result.map { array in array.map { item in AnyHashable(item) } })
        }
    }

    /// See ``ServiceDiscovery/lookup(_:deadline:callback:)``.
    ///
    /// - Warning: If `Service` or `Instance` type does not match the underlying ``ServiceDiscovery/ServiceDiscovery``'s associated types, it would result in a failure.
    @preconcurrency public func lookupAndUnwrap<Service, Instance>(
        _ service: Service,
        deadline: DispatchTime? = nil,
        callback: @Sendable @escaping (Result<[Instance], Error>) -> Void
    ) where Service: Hashable & Sendable, Instance: Hashable & Sendable {
        self._lookup(service, deadline) { result in callback(self.transform(result)) }
    }

    /// See ``ServiceDiscovery/subscribe(to:onNext:onComplete:)``.
    ///
    /// - Warning: If `service` type does not match the underlying ``ServiceDiscovery/ServiceDiscovery``'s, it would result in a failure.
    @discardableResult public func subscribe(
        to service: any Hashable & Sendable,
        onNext nextResultHandler: @Sendable @escaping (Result<[any Hashable & Sendable], Error>) -> Void,
        onComplete completionHandler: @Sendable @escaping (CompletionReason) -> Void = { _ in }
    ) -> CancellationToken { self._subscribe(service, nextResultHandler, completionHandler) }

    /// See ``ServiceDiscovery/subscribe(to:onNext:onComplete:)``.
    ///
    /// - Warning: If `service` type does not match the underlying ``ServiceDiscovery/ServiceDiscovery``'s, it would result in a failure.
    @preconcurrency @discardableResult
    @available(*, deprecated, message: "Use the subscribe variant with an (any Hashable & Sendable) service instead")
    public func subscribe(
        to service: AnyHashable,
        onNext nextResultHandler: @Sendable @escaping (Result<[AnyHashable], Error>) -> Void,
        onComplete completionHandler: @Sendable @escaping (CompletionReason) -> Void = { _ in }
    ) -> CancellationToken {
        guard service.base is (any Hashable) else {
            completionHandler(.failedToMapService)
            return CancellationToken(isCancelled: true)
        }
        // Force casting here again as we can't dynamically cast just to get the Sendable conformance.
        // This is safe, as the hashability is already verified above.
        return self._subscribe(
            service.base as! (any Hashable & Sendable),
            { result in nextResultHandler(result.map { array in array.map { item in AnyHashable(item) } }) },
            completionHandler
        )
    }

    /// See ``ServiceDiscovery/subscribe(to:onNext:onComplete:)``.
    ///
    /// - Warning: If `Service` or `Instance` type does not match the underlying ``ServiceDiscovery/ServiceDiscovery``'s associated types, it would result in a failure.
    @discardableResult @preconcurrency public func subscribeAndUnwrap<Service, Instance>(
        to service: Service,
        onNext nextResultHandler: @Sendable @escaping (Result<[Instance], Error>) -> Void,
        onComplete completionHandler: @Sendable @escaping (CompletionReason) -> Void = { _ in }
    ) -> CancellationToken where Service: Hashable & Sendable, Instance: Hashable & Sendable {
        self._subscribe(service, { result in nextResultHandler(self.transform(result)) }, completionHandler)
    }

    private func transform<Instance>(_ result: Result<[any Hashable & Sendable], Error>) -> Result<[Instance], Error>
    where Instance: Hashable & Sendable {
        result.flatMap { anyInstances in
            var instances: [Instance] = []
            for anyInstance in anyInstances {
                do {
                    let instance: Instance = try self.transform(anyInstance)
                    instances.append(instance)
                } catch { return .failure(error) }
            }
            return .success(instances)
        }
    }

    private func transform<Instance>(_ anyInstance: any Hashable & Sendable) throws -> Instance
    where Instance: Hashable & Sendable {
        guard let instance = anyInstance as? Instance else {
            throw TypeErasedServiceDiscoveryError.typeMismatch(
                description: "Expected instance type to be \(Instance.self), got \(type(of: anyInstance))"
            )
        }
        return instance
    }

    /// Unwraps the underlying ``ServiceDiscovery/ServiceDiscovery`` instance as `ServiceDiscoveryImpl` type.
    ///
    /// - Throws: `TypeErasedServiceDiscoveryError.typeMismatch` when the underlying
    ///           `ServiceDiscovery` instance is not of type `ServiceDiscoveryImpl`.
    public func unwrapAs<ServiceDiscoveryImpl: ServiceDiscovery>(_ serviceDiscoveryType: ServiceDiscoveryImpl.Type)
        throws -> ServiceDiscoveryImpl
    {
        guard let unwrapped = self._underlying as? ServiceDiscoveryImpl else {
            throw TypeErasedServiceDiscoveryError.typeMismatch(
                description: "Cannot unwrap [\(type(of: self._underlying))] as [\(ServiceDiscoveryImpl.self)]"
            )
        }
        return unwrapped
    }
}

extension AnyServiceDiscovery {
    /// See ``ServiceDiscovery/lookup(_:deadline:)``.
    ///
    /// - Warning: If `Service` or `Instance` type does not match the underlying ``ServiceDiscovery/ServiceDiscovery``'s associated types, it would result in a failure.
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *) @preconcurrency public func lookupAndUnwrap<Service, Instance>(
        _ service: Service,
        deadline: DispatchTime? = nil
    ) async throws -> [Instance] where Service: Hashable & Sendable, Instance: Hashable & Sendable {
        try await self.lookup(service, deadline: deadline).map(self.transform)
    }

    /// See ``ServiceDiscovery/subscribe(to:)``.
    ///
    /// - Warning: If `Service` or `Instance` type does not match the underlying ``ServiceDiscovery/ServiceDiscovery``'s associated types, it would result in a failure.
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *) @preconcurrency
    public func subscribeAndUnwrap<Service, Instance>(to service: Service) -> ServiceSnapshots<Instance>
    where Service: Hashable & Sendable, Instance: Hashable & Sendable {
        ServiceSnapshots(
            AsyncThrowingStream { continuation in
                Task {
                    do {
                        for try await snapshot in self.subscribe(to: service) {
                            continuation.yield(try snapshot.map(self.transform))
                        }
                        continuation.finish()
                    } catch { continuation.finish(throwing: error) }
                }
            }
        )
    }
}

public enum TypeErasedServiceDiscoveryError: Error, Sendable { case typeMismatch(description: String) }
