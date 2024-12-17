//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2019-2021 Apple Inc. and the SwiftServiceDiscovery project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftServiceDiscovery project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Atomics
import Dispatch
import Foundation  // for NSLock

/// Provides lookup for service instances that are stored in-memory.
@preconcurrency
public class InMemoryServiceDiscovery<Service: Hashable & Sendable, Instance: Hashable & Sendable>: ServiceDiscovery,
    @unchecked Sendable
{
    private let configuration: Configuration

    private let lock = NSLock()
    private var locked_isShutdown: Bool = false
    private var locked_serviceInstances: [Service: [Instance]]
    private var locked_serviceSubscriptions: [Service: [Subscription]] = [:]

    private let queue: DispatchQueue

    public var defaultLookupTimeout: DispatchTimeInterval { self.configuration.defaultLookupTimeout }

    public var isShutdown: Bool { self.lock.withLock { self.locked_isShutdown } }

    public init(
        configuration: Configuration,
        queue: DispatchQueue = .init(label: "InMemoryServiceDiscovery", attributes: .concurrent)
    ) {
        self.configuration = configuration
        self.locked_serviceInstances = configuration.serviceInstances
        self.queue = queue
    }

    @preconcurrency public func lookup(
        _ service: Service,
        deadline: DispatchTime? = nil,
        callback: @Sendable @escaping (Result<[Instance], Error>) -> Void
    ) {
        let isDone = ManagedAtomic<Bool>(false)

        let lookupWorkItem = DispatchWorkItem {
            let result = self.lock.withLock { () -> Result<[Instance], Error> in
                if self.locked_isShutdown { return .failure(ServiceDiscoveryError.unavailable) }

                if let instances = self.locked_lookupNow(service) {
                    return .success(instances)
                } else {
                    return .failure(LookupError.unknownService)
                }
            }

            if isDone.compareExchange(expected: false, desired: true, ordering: .acquiring).exchanged {
                callback(result.mapError { $0 as Error })
            }
        }

        self.queue.async(execute: lookupWorkItem)

        let lookupWorkItemBox = UncheckedSendableBox(lookupWorkItem)

        // Timeout handler
        self.queue.asyncAfter(deadline: deadline ?? DispatchTime.now() + self.defaultLookupTimeout) {
            lookupWorkItemBox.value.cancel()

            if isDone.compareExchange(expected: false, desired: true, ordering: .acquiring).exchanged {
                callback(.failure(LookupError.timedOut))
            }
        }
    }

    private enum SubscribeAction {
        case cancelSinceShutdown
        case yieldFirstElement([Instance]?)
    }

    @preconcurrency @discardableResult public func subscribe(
        to service: Service,
        onNext nextResultHandler: @Sendable @escaping (Result<[Instance], Error>) -> Void,
        onComplete completionHandler: @Sendable @escaping (CompletionReason) -> Void = { _ in }
    ) -> CancellationToken {
        let cancellationToken = CancellationToken(completionHandler: completionHandler)
        let subscription = Subscription(
            nextResultHandler: nextResultHandler,
            completionHandler: completionHandler,
            cancellationToken: cancellationToken
        )

        let action = self.lock.withLock { () -> SubscribeAction in
            guard !self.locked_isShutdown else { return .cancelSinceShutdown }

            // first add the subscription
            var subscriptions = self.locked_serviceSubscriptions.removeValue(forKey: service) ?? [Subscription]()
            subscriptions.append(subscription)
            self.locked_serviceSubscriptions[service] = subscriptions

            return .yieldFirstElement(self.locked_lookupNow(service))
        }

        switch action {
        case .cancelSinceShutdown:
            completionHandler(.serviceDiscoveryUnavailable)
            return CancellationToken(isCancelled: true)
        case .yieldFirstElement(.some(let instances)):
            self.queue.async { nextResultHandler(.success(instances)) }
            return cancellationToken
        case .yieldFirstElement(.none):
            self.queue.async { nextResultHandler(.failure(LookupError.unknownService)) }
            return cancellationToken
        }
    }

    /// Registers a service and its `instances`.
    public func register(_ service: Service, instances newInstances: [Instance]) {
        let maybeSubscriptions = self.lock.withLock { () -> [Subscription]? in
            guard !self.locked_isShutdown else { return nil }

            let previousInstances = self.locked_serviceInstances[service]
            guard previousInstances != newInstances else { return nil }

            self.locked_serviceInstances[service] = newInstances

            let subscriptions = self.locked_serviceSubscriptions[service]
            return subscriptions
        }

        guard let subscriptions = maybeSubscriptions else { return }
        for sub in subscriptions.lazy.filter({ !$0.cancellationToken.isCancelled }) {
            sub.nextResultHandler(.success(newInstances))
        }
    }

    public func shutdown() {
        let maybeServiceSubscriptions = self.lock.withLock { () -> Dictionary<Service, [Subscription]>.Values? in
            if self.locked_isShutdown { return nil }

            self.locked_isShutdown = true
            let subscriptions = self.locked_serviceSubscriptions
            self.locked_serviceSubscriptions = [:]
            self.locked_serviceInstances = [:]
            return subscriptions.values
        }

        guard let serviceSubscriptions = maybeServiceSubscriptions else { return }

        for subscriptions in serviceSubscriptions {
            for sub in subscriptions.lazy.filter({ !$0.cancellationToken.isCancelled }) {
                sub.completionHandler(.serviceDiscoveryUnavailable)
            }
        }
    }

    private func locked_lookupNow(_ service: Service) -> [Instance]? {
        if let instances = self.locked_serviceInstances[service] { return instances } else { return nil }
    }

    private struct Subscription {
        let nextResultHandler: (Result<[Instance], Error>) -> Void
        let completionHandler: (CompletionReason) -> Void
        let cancellationToken: CancellationToken
    }
}

/// A box for wrapping types that aren't marked as Sendable, but are known to be thread-safe.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    private let _value: T
    init(_ value: T) { self._value = value }
    var value: T { _value }
}

public extension InMemoryServiceDiscovery {
    struct Configuration: Sendable {
        /// Default configuration
        public static var `default`: Configuration { .init() }

        /// Lookup timeout in case `deadline` is not specified
        public var defaultLookupTimeout: DispatchTimeInterval = .milliseconds(100)

        internal var serviceInstances: [Service: [Instance]]

        public init() { self.init(serviceInstances: [:]) }

        /// Initializes `InMemoryServiceDiscovery` with the given service to instances mappings.
        public init(serviceInstances: [Service: [Instance]]) { self.serviceInstances = serviceInstances }

        /// Registers `service` and its `instances`.
        public mutating func register(service: Service, instances: [Instance]) {
            self.serviceInstances[service] = instances
        }
    }
}

// MARK: - NSLock extensions

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        self.lock()
        defer { self.unlock() }
        return try body()
    }
}
