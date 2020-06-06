//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftServiceDiscovery open source project
//
// Copyright (c) 2019-2020 Apple Inc. and the SwiftServiceDiscovery project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftServiceDiscovery project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch
import Foundation // for NSLock
import ServiceDiscoveryHelpers

/// Provides lookup for service instances that are stored in-memory.
public class InMemoryServiceDiscovery<Service: Hashable, Instance: Hashable>: ServiceDiscovery {
    private let configuration: Configuration

    private let serviceInstancesLock = NSLock()
    private var serviceInstances: [Service: [Instance]]

    private let serviceSubscriptionsLock = NSLock()
    private var serviceSubscriptions: [Service: [Subscription]] = [:]

    private let queue: DispatchQueue

    public var defaultLookupTimeout: DispatchTimeInterval {
        self.configuration.defaultLookupTimeout
    }

    public var instancesToExclude: Set<Instance>? {
        self.configuration.instancesToExclude
    }

    private let _isShutdown = SDAtomic<Bool>(false)

    public var isShutdown: Bool {
        self._isShutdown.load()
    }

    public init(configuration: Configuration, queue: DispatchQueue = .init(label: "InMemoryServiceDiscovery", attributes: .concurrent)) {
        self.configuration = configuration
        self.serviceInstances = configuration.serviceInstances
        self.queue = queue
    }

    public func lookup(_ service: Service, deadline: DispatchTime? = nil, callback: @escaping (Result<[Instance], Error>) -> Void) {
        guard !self.isShutdown else {
            callback(.failure(ServiceDiscoveryError.unavailable))
            return
        }

        let isDone = SDAtomic<Bool>(false)

        let lookupWorkItem = DispatchWorkItem {
            var result: Result<[Instance], Error>! // !-safe because if-else block always set `result`

            self.serviceInstancesLock.withLock {
                if var instances = self.serviceInstances[service] {
                    if let instancesToExclude = self.instancesToExclude {
                        instances.removeAll { instancesToExclude.contains($0) }
                    }
                    result = .success(instances)
                } else {
                    result = .failure(LookupError.unknownService)
                }
            }

            if isDone.compareAndExchange(expected: false, desired: true) {
                callback(result)
            }
        }

        self.queue.async(execute: lookupWorkItem)

        // Timeout handler
        self.queue.asyncAfter(deadline: deadline ?? DispatchTime.now() + self.defaultLookupTimeout) {
            lookupWorkItem.cancel()

            if isDone.compareAndExchange(expected: false, desired: true) {
                callback(.failure(LookupError.timedOut))
            }
        }
    }

    @discardableResult
    public func subscribe(to service: Service, onNext: @escaping (Result<[Instance], Error>) -> Void, onComplete: @escaping (CompletionReason) -> Void = { _ in }) -> CancellationToken {
        guard !self.isShutdown else {
            onComplete(.serviceDiscoveryUnavailable)
            return CancellationToken(isCancelled: true)
        }

        // Call `lookup` once and send result to subscriber
        self.lookup(service, callback: onNext)

        let cancellationToken = CancellationToken(completionHandler: onComplete)
        let subscription = Subscription(onNext: onNext, onComplete: onComplete, cancellationToken: cancellationToken)

        // Save the subscription
        self.serviceSubscriptionsLock.withLock {
            var subscriptions = self.serviceSubscriptions.removeValue(forKey: service) ?? [Subscription]()
            subscriptions.append(subscription)
            self.serviceSubscriptions[service] = subscriptions
        }

        return cancellationToken
    }

    /// Registers a service and its `instances`.
    public func register(_ service: Service, instances: [Instance]) {
        guard !self.isShutdown else { return }

        var previousInstances: [Instance]?
        self.serviceInstancesLock.withLock {
            previousInstances = self.serviceInstances[service]
            self.serviceInstances[service] = instances
        }

        self.serviceSubscriptionsLock.withLock {
            if !self.isShutdown, instances != previousInstances, let subscriptions = self.serviceSubscriptions[service] {
                // Notify subscribers whenever instances change
                subscriptions
                    .filter { !$0.cancellationToken.isCancelled }
                    .forEach { $0.onNext(.success(instances)) }
            }
        }
    }

    public func shutdown() {
        guard self._isShutdown.compareAndExchange(expected: false, desired: true) else { return }

        self.serviceSubscriptionsLock.withLock {
            self.serviceSubscriptions.values.forEach { subscriptions in
                subscriptions
                    .filter { !$0.cancellationToken.isCancelled }
                    .forEach { $0.onComplete(.serviceDiscoveryUnavailable) }
            }
        }
    }

    private struct Subscription {
        let onNext: (Result<[Instance], Error>) -> Void
        let onComplete: (CompletionReason) -> Void
        let cancellationToken: CancellationToken
    }
}

extension InMemoryServiceDiscovery {
    public struct Configuration {
        /// Default configuration
        public static var `default`: Configuration {
            .init()
        }

        /// Lookup timeout in case `deadline` is not specified
        public var defaultLookupTimeout: DispatchTimeInterval = .milliseconds(100)

        /// Instances to exclude from lookup results
        public var instancesToExclude: Set<Instance>?

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

extension NSLock {
    fileprivate func withLock(_ body: () -> Void) {
        self.lock()
        defer {
            self.unlock()
        }
        body()
    }
}
