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
import Foundation // for NSLock

/// Provides lookup for service instances that are stored in-memory.
public class InMemoryServiceDiscovery<Service: Hashable, Instance: Hashable>: ServiceDiscovery {
    private let configuration: Configuration

    private let lock = NSLock()
    private var _isShutdown: Bool = false
    private var _serviceInstances: [Service: [Instance]]
    private var _serviceSubscriptions: [Service: [Subscription]] = [:]

    private let queue: DispatchQueue

    public var defaultLookupTimeout: DispatchTimeInterval {
        self.configuration.defaultLookupTimeout
    }

    public var isShutdown: Bool {
        self.lock.withLock {
            self._isShutdown
        }
    }

    public init(configuration: Configuration, queue: DispatchQueue = .init(label: "InMemoryServiceDiscovery", attributes: .concurrent)) {
        self.configuration = configuration
        self._serviceInstances = configuration.serviceInstances
        self.queue = queue
    }

    public func lookup(_ service: Service, deadline: DispatchTime? = nil, callback: @escaping (Result<[Instance], Error>) -> Void) {
        let isDone = ManagedAtomic<Bool>(false)

        let lookupWorkItem = DispatchWorkItem {
            let result = self.lock.withLock { () -> Result<[Instance], Error> in
                if self._isShutdown {
                    return .failure(ServiceDiscoveryError.unavailable)
                }

                if let instances = self._lookupNow(service) {
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

        // Timeout handler
        self.queue.asyncAfter(deadline: deadline ?? DispatchTime.now() + self.defaultLookupTimeout) {
            lookupWorkItem.cancel()

            if isDone.compareExchange(expected: false, desired: true, ordering: .acquiring).exchanged {
                callback(.failure(LookupError.timedOut))
            }
        }
    }

    private enum SubscribeAction {
        case cancelSinceShutdown
        case yieldFirstElement([Instance]?)
    }

    @discardableResult
    public func subscribe(
        to service: Service,
        onNext nextResultHandler: @escaping (Result<[Instance], Error>) -> Void,
        onComplete completionHandler: @escaping (CompletionReason) -> Void = { _ in }
    ) -> CancellationToken {
        let cancellationToken = CancellationToken(completionHandler: completionHandler)
        let subscription = Subscription(
            nextResultHandler: nextResultHandler,
            completionHandler: completionHandler,
            cancellationToken: cancellationToken
        )

        let action = self.lock.withLock { () -> SubscribeAction in
            guard !self._isShutdown else {
                return .cancelSinceShutdown
            }

            // first add the subscription
            var subscriptions = self._serviceSubscriptions.removeValue(forKey: service) ?? [Subscription]()
            subscriptions.append(subscription)
            self._serviceSubscriptions[service] = subscriptions

            return .yieldFirstElement(self._lookupNow(service))
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
            guard !self._isShutdown else { return nil }

            let previousInstances = self._serviceInstances[service]
            guard previousInstances != newInstances else { return nil }

            self._serviceInstances[service] = newInstances

            let subscriptions = self._serviceSubscriptions[service]
            return subscriptions
        }

        guard let subscriptions = maybeSubscriptions else { return }
        for sub in subscriptions.lazy.filter({ !$0.cancellationToken.isCancelled }) {
            sub.nextResultHandler(.success(newInstances))
        }
    }

    public func shutdown() {
        let maybeServiceSubscriptions = self.lock.withLock { () -> Dictionary<Service, [Subscription]>.Values? in
            if self._isShutdown {
                return nil
            }

            self._isShutdown = true
            let subscriptions = self._serviceSubscriptions
            self._serviceSubscriptions = [:]
            self._serviceInstances = [:]
            return subscriptions.values
        }

        guard let serviceSubscriptions = maybeServiceSubscriptions else {
            return
        }

        for subscriptions in serviceSubscriptions {
            for sub in subscriptions.lazy.filter({ !$0.cancellationToken.isCancelled }) {
                sub.completionHandler(.serviceDiscoveryUnavailable)
            }
        }
    }

    private func _lookupNow(_ service: Service) -> [Instance]? {
        if let instances = self._serviceInstances[service] {
            return instances
        } else {
            return nil
        }
    }

    private struct Subscription {
        let nextResultHandler: (Result<[Instance], Error>) -> Void
        let completionHandler: (CompletionReason) -> Void
        let cancellationToken: CancellationToken
    }
}

public extension InMemoryServiceDiscovery {
    struct Configuration {
        /// Default configuration
        public static var `default`: Configuration {
            .init()
        }

        /// Lookup timeout in case `deadline` is not specified
        public var defaultLookupTimeout: DispatchTimeInterval = .milliseconds(100)

        internal var serviceInstances: [Service: [Instance]]

        public init() {
            self.init(serviceInstances: [:])
        }

        /// Initializes `InMemoryServiceDiscovery` with the given service to instances mappings.
        public init(serviceInstances: [Service: [Instance]]) {
            self.serviceInstances = serviceInstances
        }

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
        defer {
            self.unlock()
        }
        return try body()
    }
}
